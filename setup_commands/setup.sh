#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Ahmed’s Linux bootstrap – modular, fault-tolerant, interactive 🛠️
# ---------------------------------------------------------------------------
#  • Idempotent: safe to re-run, each module checks if work is needed.
#  • Continues after errors; summary at the end.
#  • CLI:  -h help   -l list modules   -i interactive picker.
# ---------------------------------------------------------------------------

##############################################################################
### 0. Guard-rails, colours, helpers                                      ####
##############################################################################
set -Eeuo pipefail
trap 'err "aborted on line $LINENO"' ERR
shopt -s nocasematch

info()  { printf '\e[1;32m[INFO]\e[0m %s\n' "$*"; }
warn()  { printf '\e[1;33m[WARN]\e[0m %s\n' "$*"; }
err()   { printf '\e[1;31m[ERR]\e[0m  %s\n' "$*"; }

FAILED_STEPS=()
run_step() {
  local step="$1"; shift
  info "▶ $step …"
  if "$@"; then
    info "✔ $step done"
  else
    warn "$step failed – skipping the rest of that module"
    FAILED_STEPS+=("$step")
  fi
  echo
}

LOGFILE=${HOME:-/root}/setup.log
[[ $EUID -eq 0 && -w /var/log ]] && LOGFILE="/var/log/setup-$(date +%F_%H-%M-%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

# ----- detect “target” user & sudo helper -----
TARGET_USER=""; HOME_DIR=""; SUDO=""
RAU() { :; }   # placeholder

detect_user() {
  if [[ -n ${SUDO_USER:-} && $EUID -eq 0 ]]; then
    TARGET_USER=$SUDO_USER
  else
    TARGET_USER=$USER
  fi
  HOME_DIR=$(eval echo "~$TARGET_USER")

  if [[ $EUID -eq 0 ]]; then
    SUDO=""
    if [[ $TARGET_USER == root ]]; then
      RAU() { bash -c "$*"; }
    elif command -v sudo &>/dev/null; then
      RAU() { sudo -u "$TARGET_USER" -H bash -c "$*"; }
    elif command -v runuser &>/dev/null; then
      RAU() { runuser -u "$TARGET_USER" -- bash -c "$*"; }
    else
      RAU() { su - "$TARGET_USER" -c "$*"; }
    fi
  else
    SUDO="sudo"
    RAU() { bash -c "$*"; }
  fi
  info "Installing for user: $TARGET_USER ($HOME_DIR)"
}
detect_user

##############################################################################
### 0b. CLI helpers – help, list, interactive menu                        ####
##############################################################################
show_help() {
  cat <<EOF
Usage: $0 [options] [module1 module2 …]
Options:
  -h            Show this help and exit
  -l            List available modules and exit
  -i            Interactive mode – pick modules via menu
EOF
}

interactive_menu() {
  local menu_opts=() chosen_numbers
  local i=1
  for m in "${ALL_MODULES[@]}"; do
    menu_opts+=("$i" "$m" off); ((i++))
  done

  if command -v whiptail &>/dev/null; then
    chosen_numbers=$(whiptail --title "Ahmed's Bootstrap" \
      --checklist "Select modules to run (Space to toggle):" 20 78 12 \
      "${menu_opts[@]}" 3>&1 1>&2 2>&3) || { warn "Cancelled."; exit 1; }
  else
    echo "Interactive mode: enter numbers separated by space (or 'all')"
    local j=1; for m in "${ALL_MODULES[@]}"; do echo "  [$j] $m"; ((j++)); done
    read -rp $'Selection: ' chosen_numbers
  fi

  if [[ $chosen_numbers == *all* ]]; then
    SELECTED_MODULES=("${ALL_MODULES[@]}")
  else
    SELECTED_MODULES=()
    for n in $chosen_numbers; do
      n=${n//[!0-9]}; (( n>=1 && n<=${#ALL_MODULES[@]} )) && \
        SELECTED_MODULES+=("${ALL_MODULES[n-1]}")
    done
    ((${#SELECTED_MODULES[@]})) || { warn "Nothing selected"; exit 1; }
  fi
}

##############################################################################
### 1. Minimal prerequisites                                             ####
##############################################################################
install_prereqs() {
  $SUDO apt-get update -y
  $SUDO apt-get install -y git openssh-client curl wget gnupg ca-certificates \
      lsb-release xclip xsel unzip whiptail
}

##############################################################################
### 2. Git identity & SSH key                                            ####
##############################################################################
setup_git_ssh() {
  local GIT_NAME=${GIT_NAME:-"Ahmed Ali"}
  local GIT_EMAIL=${GIT_EMAIL:-"ahmedaali2025@gmail.com"}

  RAU "git config --global user.name  '$GIT_NAME'"
  RAU "git config --global user.email '$GIT_EMAIL'"

  local SSH_DIR="$HOME_DIR/.ssh"
  local KEY="$SSH_DIR/id_ed25519"
  local AUTH_KEYS="$SSH_DIR/authorized_keys"

  if [[ ! -f $KEY ]]; then
    info "Generating new SSH key …"
    RAU "install -d -m 700 '$SSH_DIR'"

    if RAU "[[ -L '$AUTH_KEYS' ]]"; then
      warn "'authorized_keys' is a symlink – skipping overwrite"
    fi

    RAU "ssh-keygen -q -t ed25519 -C '$GIT_EMAIL' -f '$KEY' -N ''"
  fi

  RAU "eval \$(ssh-agent -s); ssh-add -q '$KEY'"

  if command -v xclip &>/dev/null && [[ -n ${DISPLAY:-} ]]; then
    RAU "xclip -sel clip < '${KEY}.pub'"
    info "Key copied to clipboard – add to GitHub then press <Enter>"
  else
    info $'\nAdd this key to GitHub, then press <Enter> (shown below):\n'
    cat "${KEY}.pub"
  fi

  read -r
  RAU "ssh -o StrictHostKeyChecking=no -T git@github.com" || warn "GitHub SSH test may fail on first run"
}

##############################################################################
### 3. Full upgrade & base toolchain                                     ####
##############################################################################
install_toolchain() {
  info "Upgrading system …"
  $SUDO apt-get full-upgrade -y

  local pkgs=(xsel xclip python3 python3-venv npm bat screen fzf zoxide zsh git
              ripgrep tmux thefuck delta git-delta build-essential cmake gcc
              fontconfig jq curl wget gnupg ca-certificates eza)
  $SUDO apt-get install -y "${pkgs[@]}" || warn "Some APT packages failed – continuing"

  # --- eza fallback to GitHub release ---
  if ! command -v eza &>/dev/null; then
    warn "eza not in APT – installing from GitHub …"
    local ver arch url tmp
    ver=$(curl -s https://api.github.com/repos/eza-community/eza/releases/latest |
          grep -Po '"tag_name": *"v\K[^"]+')
    arch=$(dpkg --print-architecture | sed 's/amd64/x86_64/;s/arm64/aarch64/')
    url="https://github.com/eza-community/eza/releases/download/v${ver}/eza_${ver}_linux_${arch}.tar.gz"

    tmp=$(mktemp -d)
    if curl -sL "$url" -o "$tmp/eza.tar.gz"; then
      tar -xzf "$tmp/eza.tar.gz" -C "$tmp"
      $SUDO install "$tmp"/eza*/eza -t /usr/local/bin
    else
      warn "GitHub download failed"
    fi
    rm -rf "$tmp"
  fi

  if ! command -v eza &>/dev/null && command -v exa &>/dev/null; then
    $SUDO ln -sf "$(command -v exa)" /usr/local/bin/eza
    info "Created /usr/local/bin/eza → exa"
  fi
}

##############################################################################
### 4. Neovim – newest stable                                            ####
##############################################################################
install_neovim() {
  local arch pattern
  arch=$(dpkg --print-architecture)
  case $arch in
    amd64|x86_64) pattern='^nvim-linux(-x86_64|64)\.tar\.gz$' ;;
    arm64|aarch64) pattern='^nvim-linux-arm64\.tar\.gz$' ;;
    *)  warn "Unsupported arch $arch – skipping Neovim"; return 1 ;;
  esac

  local api='https://api.github.com/repos/neovim/neovim/releases?per_page=100'
  local release
  release=$(curl -s "$api" | jq -r --arg PAT "$pattern" '
      .[] | select(.prerelease==false) |
      select([ .assets[].name ] | map(test($PAT)) | any) |
      .tag_name' | head -n1) || true
  [[ -z $release ]] && { warn "No matching Neovim release found"; return 1; }

  local ver=${release#v} current=""
  RAU "command -v nvim" &>/dev/null && current=$(RAU "nvim --version | head -n1 | awk '{print \$2}'")
  [[ $ver == "$current" ]] && { info "Neovim already at newest ($ver)"; return 0; }

  local asset
  asset=$(curl -s "$api" | jq -r --arg TAG "$release" --arg PAT "$pattern" '
      .[] | select(.tag_name==$TAG) |
      .assets[] | select(.name|test($PAT)) | .name' | head -n1)

  local url="https://github.com/neovim/neovim/releases/download/${release}/${asset}"
  local tmp; tmp=$(mktemp -d); pushd "$tmp" >/dev/null
  wget -q "$url" -O "$asset" || { warn "Download failed"; popd; rm -rf "$tmp"; return 1; }
  tar -xzf "$asset"
  $SUDO rm -rf /opt/neovim
  $SUDO mv nvim-linux* /opt/neovim
  $SUDO ln -sf /opt/neovim/bin/nvim /usr/local/bin/nvim
  popd >/dev/null && rm -rf "$tmp"
}

##############################################################################
### 5. Z-shell, Oh-My-Zsh, Powerlevel10k                                 ####
##############################################################################
setup_zsh() {
  $SUDO chsh -s "$(command -v zsh)" "$TARGET_USER" || true

  [[ -d "$HOME_DIR/.oh-my-zsh" ]] || \
    RAU "sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" '' --unattended"

  RAU "mkdir -p '$HOME_DIR/.oh-my-zsh/custom/themes' '$HOME_DIR/.oh-my-zsh/custom/plugins'"

  [[ -d "$HOME_DIR/.oh-my-zsh/custom/themes/powerlevel10k" ]] || \
    RAU "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
         '$HOME_DIR/.oh-my-zsh/custom/themes/powerlevel10k'"

  for repo in zsh-users/zsh-autosuggestions \
              zsh-users/zsh-syntax-highlighting \
              joshskidmore/zsh-fzf-history-search; do
    local name=${repo##*/}
    [[ -d "$HOME_DIR/.oh-my-zsh/custom/plugins/$name" ]] || \
      RAU "git clone --depth=1 https://github.com/$repo \
           '$HOME_DIR/.oh-my-zsh/custom/plugins/$name'"
  done
}

##############################################################################
### 6. Clone dotfiles                                                    ####
##############################################################################
clone_dotfiles() {
  local proj="$HOME_DIR/projects"
  RAU "mkdir -p '$proj'"
  if [[ ! -d "$proj/config/.git" ]]; then
    RAU "git clone git@github.com:ahmedaaali/config.git '$proj/config'" \
      || RAU "git clone https://github.com/ahmedaaali/config.git '$proj/config'"
  else
    RAU "git -C '$proj/config' pull --ff-only"
  fi
  RAU "git -C '$proj/config' submodule update --init --recursive"
}

##############################################################################
### 7. Symlink configuration                                             ####
##############################################################################
create_symlinks() {
  local proj="$HOME_DIR/projects"
  RAU "mkdir -p '$HOME_DIR/.config' '$HOME_DIR/.local/share/fonts'"

  link() {
    local src="$1" dest="$2"
    RAU "[[ -e '$dest' || -L '$dest' ]]" && RAU "rm -rf '$dest'"
    RAU "ln -s '$src' '$dest'"
  }

  link "$proj/config/nvim"            "$HOME_DIR/.config/nvim"
  link "$proj/config/tmux"            "$HOME_DIR/.config/tmux"
  link "$proj/config/home/zshrc"      "$HOME_DIR/.zshrc"
  link "$proj/config/bat"             "$HOME_DIR/.config/bat"
  link "$proj/config/home/gitconfig"  "$HOME_DIR/.gitconfig"
  link "$proj/config/home/p10k.zsh"   "$HOME_DIR/.p10k.zsh"

  # extra stuff
  link "$proj/config/home/oh-my-zsh"        "$HOME_DIR/.oh-my-zsh-custom"
  link "$proj/config/home/fzf-git.sh"       "$HOME_DIR/fzf-git.sh"
  link "$proj/config/home/screenrc"         "$HOME_DIR/.screenrc"
  link "$proj/config/home/viminfo"          "$HOME_DIR/.viminfo"
  link "$proj/config/home/vscode"           "$HOME_DIR/.vscode"
  link "$proj/config/home/wezterm.lua"      "$HOME_DIR/.wezterm.lua"
  link "$proj/config/home/zhistory"         "$HOME_DIR/.zhistory"
  link "$proj/config/home/zprofile"         "$HOME_DIR/.zprofile"
  link "$proj/config/home/zsh_history"      "$HOME_DIR/.zsh_history"
  link "$proj/config/home/zsh_sessions"     "$HOME_DIR/.zsh_sessions"
  link "$proj/config/setup_commands"        "$HOME_DIR/setup_commands"
  link "$proj/config/coolnight.itermcolors" "$HOME_DIR/.config/coolnight.itermcolors"
}

##############################################################################
### 8. Nerd Font                                                         ####
##############################################################################
install_font() {
  local dir="$HOME_DIR/.local/share/fonts"
  [[ -f "$dir/MesloLGS NF Regular.ttf" ]] && return 0
  wget -qO /tmp/Meslo.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/Meslo.zip
  RAU "unzip -oq /tmp/Meslo.zip -d '$dir'"; rm /tmp/Meslo.zip; fc-cache -fv
}

##############################################################################
### 9. Pyenv & virtualenv                                                ####
##############################################################################
install_pyenv_virtualenv() {
  if ! RAU "command -v pyenv" &>/dev/null; then
    info "Installing pyenv …"
    RAU "curl https://pyenv.run | bash"
  fi
  local plugin_dir="$HOME_DIR/.pyenv/plugins/pyenv-virtualenv"
  [[ -d "$plugin_dir" ]] || \
    RAU "git clone https://github.com/pyenv/pyenv-virtualenv.git '$plugin_dir'"
}

##############################################################################
### 10. Lazygit                                                          ####
##############################################################################
install_lazygit() {
  RAU "command -v lazygit" &>/dev/null && return 0
  local ver arch url
  ver=$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest |
        grep -Po '"tag_name": *"v\K[^"]+')
  arch=$(dpkg --print-architecture | sed 's/amd64/x86_64/;s/arm64/aarch64/')
  url="https://github.com/jesseduffield/lazygit/releases/download/v${ver}/lazygit_${ver}_Linux_${arch}.tar.gz"
  curl -sL "$url" -o /tmp/lazygit.tar.gz
  tar -xf /tmp/lazygit.tar.gz -C /tmp lazygit
  $SUDO install /tmp/lazygit -t /usr/local/bin
  rm /tmp/lazygit /tmp/lazygit.tar.gz
}

##############################################################################
### 11. Tmux plugins                                                     ####
##############################################################################
setup_tmux_plugins() {
  command -v tmux >/dev/null || { warn "tmux not installed – skipping plugins"; return 0; }
  local tpm_dir="$HOME_DIR/.tmux/plugins/tpm"
  [[ -d "$tpm_dir" ]] || RAU "git clone https://github.com/tmux-plugins/tpm '$tpm_dir'"
  RAU "$tpm_dir/bin/install_plugins" || warn "tmux plugin install failed"
}

##############################################################################
### 12. (optional) telescope-fzf-native build                             ####
##############################################################################
build_telescope_fzf() {
  RAU "test -d '$HOME_DIR/.local/share/nvim/lazy/telescope-fzf-native.nvim'" || return 0
  RAU "make -C '$HOME_DIR/.local/share/nvim/lazy/telescope-fzf-native.nvim'"
}

##############################################################################
### 13. Sync Neovim plugins                                              ####
##############################################################################
sync_nvim_plugins() {
  info "Syncing Neovim plugins …"
  RAU "nvim --headless '+Lazy! sync' +qa" || warn "Lazy sync failed"
}

##############################################################################
### 14. Rebuild bat cache                                                ####
##############################################################################
rebuild_bat_cache() {
  RAU "test -d '$HOME_DIR/.config/bat/themes'" || return 0
  local bat_cmd=""
  if RAU "command -v batcat" &>/dev/null; then
    bat_cmd="batcat"
  elif RAU "command -v bat" &>/dev/null; then
    bat_cmd="bat"
  else
    warn "bat is not installed – skipping cache rebuild"; return 0
  fi
  RAU "$bat_cmd cache --build"
}

##############################################################################
### 15. Reload shell (safe)                                              ####
##############################################################################
reload_shell() {
  command -v zsh >/dev/null || return 0
  info "Launching a login zsh once to let Oh-My-Zsh initialise …"
  RAU "zsh -lic 'echo \"Oh-My-Zsh initialisation complete\"'"
}

##############################################################################
### 16. Module registry & CLI dispatch                                   ####
##############################################################################
ALL_MODULES=(
  install_prereqs
  setup_git_ssh
  install_toolchain
  install_neovim
  setup_zsh
  clone_dotfiles
  create_symlinks
  install_font
  install_pyenv_virtualenv
  install_lazygit
  setup_tmux_plugins
  build_telescope_fzf
  sync_nvim_plugins
  rebuild_bat_cache
  reload_shell
)

INTERACTIVE=0
while getopts ":hli" opt; do
  case $opt in
    h) show_help; exit 0 ;;
    l) printf '%s\n' "${ALL_MODULES[@]}"; exit 0 ;;
    i) INTERACTIVE=1 ;;
    \?) warn "Unknown option: -$OPTARG"; show_help; exit 1 ;;
  esac
done
shift $((OPTIND-1))

if (( INTERACTIVE )); then interactive_menu; set -- "${SELECTED_MODULES[@]}"; fi

if (( $# )); then
  for mod in "$@"; do
    if declare -f "$mod" >/dev/null; then
      run_step "$mod" "$mod"
    else
      warn "No such module: $mod"; FAILED_STEPS+=("$mod (not found)")
    fi
  done
else
  # normal full run
  for mod in "${ALL_MODULES[@]}"; do run_step "$mod" "$mod"; done
fi

##############################################################################
### Wrap-up                                                              ####
##############################################################################
if (( ${#FAILED_STEPS[@]} )); then
  warn "Finished with ${#FAILED_STEPS[@]} module(s) needing attention:"
  for s in "${FAILED_STEPS[@]}"; do warn "  • $s"; done
  warn "Re-run the script after fixing those issues – it's safe."
else
  info "🎉 All modules completed successfully!  Open a new terminal (zsh + P10k) and enjoy."
fi
