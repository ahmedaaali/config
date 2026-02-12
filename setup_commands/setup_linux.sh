#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Ahmed’s Linux bootstrap – robust, idempotent, interactive 🚀
# ---------------------------------------------------------------------------
#  ▸ Re-run safely – every module checks before doing work.
#  ▸ Falls back to GitHub binaries for Neovim, eza, pyenv, lazygit, etc.
#  ▸ Interactive CLI   -h help   -l list modules   -c menu picker   -n quick numeric    -s skip ssh add to github
# ---------------------------------------------------------------------------

##############################################################################
### 0. Guard-rails, colours, helpers                                     ####
##############################################################################
set -Eeuo pipefail
trap 'err "aborted on line $LINENO"' ERR
shopt -s nocasematch

info(){ printf '\e[1;32m[INFO]\e[0m %s\n' "$*"; }
warn(){ printf '\e[1;33m[WARN]\e[0m %s\n' "$*"; }
err (){ printf '\e[1;31m[ERR]\e[0m  %s\n' "$*"; }

FAILED_STEPS=()
run_step(){ local s="$1";shift; info "▶ $s …"
  if "$@";then info "✔ $s done"
  else warn "$s failed – skipping the rest of that module"; FAILED_STEPS+=("$s");fi;echo;}

LOGFILE=${HOME:-/root}/setup.log
[[ $EUID -eq 0 && -w /var/log ]] && LOGFILE="/var/log/setup-$(date +%F_%H-%M-%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

##############################################################################
### 0a. Target user, sudo shim, RAU helper                               ####
##############################################################################
TARGET_USER=""; HOME_DIR=""; SUDO=""
SKIP_SSH_WAIT=0
RAU(){ :; }

detect_user(){
  if [[ -n ${SUDO_USER:-} && $EUID -eq 0 ]];then TARGET_USER=$SUDO_USER
  else TARGET_USER=$USER;fi
  HOME_DIR=$(eval echo "~$TARGET_USER")

  if [[ $EUID -eq 0 ]];then
    SUDO=""
    if [[ $TARGET_USER == root ]];then RAU(){ bash -c "$*"; }
    elif command -v sudo &>/dev/null;then RAU(){ sudo -u "$TARGET_USER" -H bash -c "$*"; }
    elif command -v runuser &>/dev/null;then RAU(){ runuser -u "$TARGET_USER" -- bash -c "$*"; }
    else RAU(){ su - "$TARGET_USER" -c "$*"; }
    fi
  else
    SUDO="sudo"; RAU(){ bash -c "$*"; }
  fi
  info "Installing for user: $TARGET_USER ($HOME_DIR)"
}
detect_user

##############################################################################
### 0b. CLI helpers – help, list, pickers                                ####
##############################################################################
show_help(){ cat <<EOF
Usage: $0 [options] [module1 module2 …]
  -h  Show this help and exit
  -l  List available modules and exit
  -c  Interactive menu picker (whiptail / vanilla)
  -n  Quick numeric selector (e.g. “-c” then “1,3,7”)
  -s  Skip pause after SSH key copy
If no modules are supplied the full run executes sequentially.
EOF
}

numeric_picker(){
  echo -e "\nChoose modules to run:"
  for i in "${!ALL_MODULES[@]}";do printf "  [%2d] %s\n" $((i+1)) "${ALL_MODULES[i]}";done
  echo; read -rp "Enter numbers (e.g. 1,3 or 'all'): " sel
  if [[ $sel =~ all ]];then SELECTED_MODULES=("${ALL_MODULES[@]}");else
    IFS=',' read -ra nums <<< "$sel"; SELECTED_MODULES=()
    for n in "${nums[@]}";do n=${n//[^0-9]/}
      (( n>=1 && n<=${#ALL_MODULES[@]} )) && SELECTED_MODULES+=("${ALL_MODULES[n-1]}")
    done
  fi
  (( ${#SELECTED_MODULES[@]} )) || { warn "Nothing selected."; exit 1; }
}

interactive_menu(){
  local opts=() i=1; for m in "${ALL_MODULES[@]}";do opts+=("$i" "$m" off); ((i++));done
  local nums
  if command -v whiptail &>/dev/null;then
    nums=$(whiptail --title "Ahmed's Bootstrap" --checklist \
      "Select modules to run (Space to toggle)" 20 78 12 "${opts[@]}" 3>&1 1>&2 2>&3) || {
        warn "Cancelled."; exit 1; }
  else numeric_picker; return; fi
  [[ $nums == *all* ]] && SELECTED_MODULES=("${ALL_MODULES[@]}") || {
    SELECTED_MODULES=(); for n in $nums;do n=${n//[!0-9]}; \
      (( n>=1 && n<=${#ALL_MODULES[@]} )) && SELECTED_MODULES+=("${ALL_MODULES[n-1]}");done;}
  (( ${#SELECTED_MODULES[@]} )) || { warn "Nothing selected."; exit 1; }
}

##############################################################################
### 1. Minimal prerequisites & update                                    ####
##############################################################################
install_prereqs(){
  $SUDO apt update -y
  $SUDO apt install -y git openssh-client curl wget gnupg ca-certificates \
        lsb-release xclip xsel unzip whiptail jq
}

##############################################################################
### 2. Git identity + SSH key                                            ####
##############################################################################
setup_git_ssh(){
  local GIT_NAME=${GIT_NAME:-"Ahmed Ali"} GIT_EMAIL=${GIT_EMAIL:-"ahmedaali2025@gmail.com"}
  RAU "git config --global user.name  '$GIT_NAME'"
  RAU "git config --global user.email '$GIT_EMAIL'"

  #local SSH_DIR="$HOME_DIR/.ssh" KEY="$SSH_DIR/id_ed25519" PUBKEY="$key.pub" AUTH_KEYS="$SSH_DIR/authorized_keys"
  local SSH_DIR="$HOME_DIR/.ssh"
  local KEY="$SSH_DIR/id_ed25519"
  local AUTH_KEYS="$SSH_DIR/authorized_keys"

  if [[ ! -f $KEY ]];then
    info "Generating new SSH key …"
    RAU "install -d -m 700 '$SSH_DIR'"
    RAU "[[ -L '$AUTH_KEYS' ]]" && warn "'authorized_keys' is symlink – leaving untouched"
    RAU "ssh-keygen -q -t ed25519 -C '$GIT_EMAIL' -f '$KEY' -N 'Ahmed'"
  fi
  RAU "eval \$(ssh-agent -s); ssh-add -q '$KEY'"
  if command -v xclip &>/dev/null && [[ -n ${DISPLAY:-} ]];then
    RAU "xclip -sel clip < '${KEY}.pub'"; info "Key copied to clipboard – add to GitHub then press Enter"
  else
    info $'\nAdd this key to GitHub, then press Enter (key shown below):\n'; cat "${KEY}.pub"
  fi; #read -r
  if (( ! SKIP_SSH_WAIT )); then
    read -r
  else
    info "-s supplied – continuing without pause."
  fi

  RAU "ssh -o StrictHostKeyChecking=no -T git@github.com" || warn "SSH test may fail first time"
}

##############################################################################
### 3. System upgrade + base toolchain                                   ####
##############################################################################
install_toolchain(){
  info "Upgrading system …"; $SUDO apt full-upgrade -y
  local pkgs=(python3 python3-venv npm bat screen fzf zoxide zsh git ripgrep tmux \
              thefuck git-delta build-essential cmake gcc fontconfig jq curl wget \
              gnupg ca-certificates eza)
  $SUDO apt install -y "${pkgs[@]}" || warn "Some packages failed – continuing"

  # ---------- eza fallback ----------
  if ! command -v eza &>/dev/null;then
    warn "eza not in repo – installing latest release"
    local ver arch tmp
    ver=$(curl -s https://api.github.com/repos/eza-community/eza/releases/latest | jq -r '.tag_name' | tr -d v)
    arch=$(dpkg --print-architecture | sed 's/amd64/x86_64/;s/arm64/aarch64/')
    tmp=$(mktemp -d)
    curl -sL "https://github.com/eza-community/eza/releases/download/v${ver}/eza_${ver}_linux_${arch}.tar.gz" \
      -o "$tmp/eza.tar.gz" && tar -xzf "$tmp/eza.tar.gz" -C "$tmp" \
      && $SUDO install "$tmp"/eza*/eza -t /usr/local/bin || warn "eza download failed"
    rm -rf "$tmp"
  fi
  [[ $(command -v eza) ]] || { warn "eza still absent (and exa missing)"; }
}

##############################################################################
### 4. Clone dotfiles                                                   ####
##############################################################################
clone_dotfiles(){
  local proj="$HOME_DIR/projects"; RAU "mkdir -p '$proj'"
  if [[ ! -d "$proj/config/.git" ]];then
    RAU "git clone git@github.com:ahmedaaali/config.git '$proj/config'" \
      || RAU "git clone https://github.com/ahmedaaali/config.git '$proj/config'"
  else RAU "git -C '$proj/config' pull --ff-only"; fi
  RAU "git -C '$proj/config' submodule update --init --recursive"
}

##############################################################################
### 5. Symlink configuration                                            ####
##############################################################################
create_symlinks() {
  local proj="$HOME_DIR/projects/config"
  RAU "mkdir -p '$HOME_DIR/.config' '$HOME_DIR/.local/share/fonts'"

  link() {
    local src="$1" dst="$2"
    RAU "[[ -e '$dst' || -L '$dst' ]]" && RAU "rm -rf '$dst'"
    RAU "ln -s '$src' '$dst'"
  }

  # Direct config directories
  link "$proj/nvim"                "$HOME_DIR/.config/nvim"
  link "$proj/tmux"                "$HOME_DIR/.config/tmux"
  link "$proj/bat"                 "$HOME_DIR/.config/bat"
  link "$proj/thefuck"             "$HOME_DIR/.config/thefuck"

  # Home files
  link "$proj/home/zshrc"          "$HOME_DIR/.zshrc"
  link "$proj/home/p10k.zsh"       "$HOME_DIR/.p10k.zsh"
  link "$proj/home/gitconfig"      "$HOME_DIR/.gitconfig"
  link "$proj/home/screenrc"       "$HOME_DIR/.screenrc"
  link "$proj/home/viminfo"        "$HOME_DIR/.viminfo"
  link "$proj/home/zprofile"       "$HOME_DIR/.zprofile"
  link "$proj/home/zhistory"       "$HOME_DIR/.zhistory"
  link "$proj/home/zsh_history"    "$HOME_DIR/.zsh_history"
  link "$proj/home/zsh_sessions"   "$HOME_DIR/.zsh_sessions"
  link "$proj/home/wezterm.lua"    "$HOME_DIR/.wezterm.lua"
  link "$proj/home/vscode"         "$HOME_DIR/.vscode"
  link "$proj/home/fzf-git.sh"     "$HOME_DIR/fzf-git.sh"

  # Additional dirs
  link "$proj/setup_commands"      "$HOME_DIR/setup_commands"
  link "$proj/tmux/.tmux"          "$HOME_DIR/.tmux"

  # Theme
  link "$proj/coolnight.itermcolors" "$HOME_DIR/.config/coolnight.itermcolors"
}

##############################################################################
### 6. Z-shell, Oh-My-Zsh, Powerlevel10k                                ####
##############################################################################
setup_zsh() {
  # make zsh the login shell (ignore failure if already set)
  $SUDO chsh -s "$(command -v zsh)" "$TARGET_USER" || true

  # if ~/.oh-my-zsh is a symlink or junk, remove it first
  if RAU "[[ -L '$HOME_DIR/.oh-my-zsh' || -f '$HOME_DIR/.oh-my-zsh' ]]"; then
    info "Removing pre-existing ~/.oh-my-zsh symlink/file"
    RAU "rm -rf '$HOME_DIR/.oh-my-zsh'"
  fi

  # fresh clone if directory absent
  if RAU "[[ ! -d '$HOME_DIR/.oh-my-zsh' ]]"; then
    RAU "git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git '$HOME_DIR/.oh-my-zsh'"
  fi

  # ensure custom dirs exist
  RAU "mkdir -p '$HOME_DIR/.oh-my-zsh/custom/themes' '$HOME_DIR/.oh-my-zsh/custom/plugins'"

  # ─── theme ────────────────────────────────────────────────
  if RAU "[[ ! -d '$HOME_DIR/.oh-my-zsh/custom/themes/powerlevel10k' ]]"; then
    RAU "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
         '$HOME_DIR/.oh-my-zsh/custom/themes/powerlevel10k'"
  fi

  # ─── plugins ──────────────────────────────────────────────
  for repo in zsh-users/zsh-autosuggestions \
              zsh-users/zsh-syntax-highlighting \
              joshskidmore/zsh-fzf-history-search; do
    local name=${repo##*/}
    RAU "[[ -d '$HOME_DIR/.oh-my-zsh/custom/plugins/$name' ]]" && continue
    RAU "git clone --depth=1 https://github.com/$repo \
         '$HOME_DIR/.oh-my-zsh/custom/plugins/$name'"
  done
}

##############################################################################
### 7. Neovim (latest stable)                                           ####
##############################################################################
install_neovim() {
  # ---- asset patterns by arch ----
  local arch pattern
  arch=$(dpkg --print-architecture)
  case $arch in
    amd64|x86_64)   pattern='^nvim-linux(-x86_64|64)\.tar\.gz$' ;;
    arm64|aarch64)  pattern='^nvim-linux-arm64\.tar\.gz$'       ;;
    *)  warn "Unsupported arch $arch – skipping Neovim"; return 1 ;;
  esac

  # ---- discover latest release tag that ships a matching asset ----
  local api='https://api.github.com/repos/neovim/neovim/releases?per_page=100'
  local release
  release=$(curl -s "$api" | jq -r \
    --arg PAT "$pattern" '
      .[] | select(.prerelease==false) |
      select([ .assets[].name ] | map(test($PAT)) | any) |
      .tag_name' | head -n1)

  [[ -z $release ]] && { warn "No release has asset matching $pattern"; return 1; }

  local ver=${release#v}                # strip leading „v“
  local current=""
  if RAU "command -v nvim" &>/dev/null; then
    current=$(RAU "nvim --version | head -1 | awk '{print \$2}'")
  fi
  [[ $ver == "$current" ]] && { info "Neovim already at newest ($ver)"; return 0; }

  # ---- grab the actual asset name for that release ----
  local asset
  asset=$(curl -s "$api" | jq -r \
      --arg TAG "$release" --arg PAT "$pattern" '
        .[] | select(.tag_name==$TAG) |
        .assets[] | select(.name|test($PAT)) | .name' | head -n1)

  local url="https://github.com/neovim/neovim/releases/download/${release}/${asset}"
  local sha_url="${url}.sha256sum"

  local tmp; tmp=$(mktemp -d); pushd "$tmp" >/dev/null
  info "Downloading Neovim ${ver} ($asset)…"
  wget -q "$url" -O "$asset" || { warn "Download failed"; popd; rm -rf "$tmp"; return 1; }
  wget -q "$sha_url" -O "${asset}.sha256sum" && sha256sum -c "${asset}.sha256sum" || warn "Checksum skipped"

  tar -xzf "$asset"
  local dir; dir=$(find . -maxdepth 1 -type d -name 'nvim-*' | head -n1)

  $SUDO rm -rf /opt/neovim          # wipe any old copy
  $SUDO mkdir -p /opt
  $SUDO mv "$dir" /opt/neovim
  $SUDO ln -sf /opt/neovim/bin/nvim /usr/local/bin/nvim

  popd >/dev/null && rm -rf "$tmp"
}

##############################################################################
### 8. Nerd Font                                                        ####
##############################################################################
install_font(){
  local dir="$HOME_DIR/.local/share/fonts"
  [[ -f "$dir/MesloLGS NF Regular.ttf" ]] && return 0
  curl -sL -o /tmp/Meslo.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/Meslo.zip
  RAU "unzip -oq /tmp/Meslo.zip -d '$dir'"; rm /tmp/Meslo.zip; fc-cache -fv
}

##############################################################################
### 9. Pyenv (+virtualenv)                                              ####
##############################################################################
install_pyenv_virtualenv(){
  if ! RAU "command -v pyenv" &>/dev/null;then
    info "Installing pyenv…"; RAU "git clone --depth=1 https://github.com/pyenv/pyenv.git '$HOME_DIR/.pyenv'"
  fi
  local plugin="$HOME_DIR/.pyenv/plugins/pyenv-virtualenv"
  [[ -d $plugin ]] || RAU "git clone --depth=1 https://github.com/pyenv/pyenv-virtualenv.git '$plugin'"
}

##############################################################################
### 10. Lazygit                                                         ####
##############################################################################
install_lazygit(){
  RAU "command -v lazygit" &>/dev/null && return 0
  local ver=$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r '.tag_name' | tr -d v)
  local arch=$(dpkg --print-architecture | sed 's/amd64/x86_64/;s/arm64/aarch64/')
  curl -sL "https://github.com/jesseduffield/lazygit/releases/download/v${ver}/lazygit_${ver}_Linux_${arch}.tar.gz" \
    -o /tmp/lg.tgz && tar xzf /tmp/lg.tgz -C /tmp lazygit
  $SUDO install /tmp/lazygit -t /usr/local/bin; rm /tmp/lazygit /tmp/lg.tgz
}

##############################################################################
### 11. Tmux plugins                                                    ####
##############################################################################
setup_tmux_plugins(){
  command -v tmux >/dev/null || { warn "tmux not installed – skipping"; return; }
  local tpm="$HOME_DIR/.tmux/plugins/tpm"
  [[ -d $tpm ]] || RAU "git clone https://github.com/tmux-plugins/tpm '$tpm'"
  RAU "$tpm/bin/install_plugins" || warn "tmux plugin install failed"
}

##############################################################################
### 12. telescope-fzf native build                                      ####
##############################################################################
build_telescope_fzf(){
  RAU "test -d '$HOME_DIR/.local/share/nvim/lazy/telescope-fzf-native.nvim'" || return 0
  RAU "make -C '$HOME_DIR/.local/share/nvim/lazy/telescope-fzf-native.nvim'"
}

##############################################################################
### 13. Sync Neovim plugins                                             ####
##############################################################################
sync_nvim_plugins(){ RAU "nvim --headless '+Lazy! sync' +qa" || warn "Lazy sync failed"; }

##############################################################################
### 14. Rebuild bat cache                                               ####
##############################################################################
rebuild_bat_cache(){
  RAU "test -d '$HOME_DIR/.config/bat/themes'" || return 0
  local batcmd; batcmd=$(RAU "command -v batcat" || true); [[ $batcmd ]] || batcmd=$(RAU "command -v bat" || true)
  [[ $batcmd ]] && RAU "$batcmd cache --build" || warn "bat not installed"
}

##############################################################################
### 15. First zsh initialise (non-fatal)                                ####
##############################################################################
reload_shell(){
  command -v zsh >/dev/null || return 0
  info "Running a one-off non-interactive zsh login (errors ignored)…"
  RAU "TERM=\$TERM zsh -lic 'exit 0'" || true
}

##############################################################################
### 16. Ensure tmux works with terminal                                 ####
##############################################################################
ensure_utf8_locale() {
  if ! locale | grep -q 'UTF-8'; then
    info "Generating UTF-8 locale …"
    $SUDO apt install -y locales
    $SUDO locale-gen en_US.UTF-8
    $SUDO update-locale LANG=en_US.UTF-8
    info "Locale set to en_US.UTF-8 – please log out/in once."
  fi
}

##############################################################################
### Module registry & CLI dispatch                                      ####
##############################################################################
ALL_MODULES=(
  install_prereqs
  setup_git_ssh
  install_toolchain
  clone_dotfiles
  create_symlinks
  setup_zsh
  install_neovim
  install_font
  install_pyenv_virtualenv
  install_lazygit
  setup_tmux_plugins
  build_telescope_fzf
  sync_nvim_plugins
  rebuild_bat_cache
  ensure_utf8_locale
  reload_shell
)

INTERACTIVE=0 CHOICE_MODE=0
while getopts ":hlcns" opt;do case $opt in
  h) show_help; exit 0 ;;
  l) printf '%s\n' "${ALL_MODULES[@]}"; exit 0 ;;
  c) INTERACTIVE=1 ;;
  n) CHOICE_MODE=1 ;;
  s) SKIP_SSH_WAIT=1 ;;
  \?) warn "Unknown option -$OPTARG"; show_help; exit 1 ;;
esac;done; shift $((OPTIND-1))

if (( INTERACTIVE ));then interactive_menu; set -- "${SELECTED_MODULES[@]}"; fi
if (( CHOICE_MODE )); then numeric_picker; set -- "${SELECTED_MODULES[@]}"; fi

if (( $# ));then
  for m in "$@";do declare -f "$m" >/dev/null && run_step "$m" "$m" \
        || { warn "No such module: $m"; FAILED_STEPS+=("$m (not found)"); }
  done
else for m in "${ALL_MODULES[@]}";do run_step "$m" "$m";done; fi

##############################################################################
### Wrap-up                                                              ####
##############################################################################
if (( ${#FAILED_STEPS[@]} ));then
  warn "Finished with ${#FAILED_STEPS[@]} module(s) needing attention:"
  for s in "${FAILED_STEPS[@]}";do warn "  • $s";done
  warn "Re-run after fixing / network issues – safe to repeat."
else info "🎉 All modules completed successfully!  Open a new terminal (zsh + P10k) and enjoy."; fi
