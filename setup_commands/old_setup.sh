#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Ahmed’s Linux bootstrap – modular, fault-tolerant
# ---------------------------------------------------------------------------
#  • Runs unattended except for ONE pause: adding the new SSH key to GitHub.
#  • Safe to re-run (idempotent); each step checks whether work is needed.
#  • If a module errors it’s logged and the script continues; summary at end.
#  • Colourised logs for quick scanning.
# ---------------------------------------------------------------------------

##############################################################################
### 0. Guard-rails, colours, helpers                                      ####
##############################################################################
set -Eeuo pipefail
trap 'err "aborted on line $LINENO"' ERR
shopt -s nocasematch

# ----- colours -----
info() { printf '\e[1;32m[INFO]\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m[WARN]\e[0m %s\n' "$*"; }
err () { printf '\e[1;31m[ERR]\e[0m  %s\n' "$*"; }

# ----- per-step bookkeeping -----
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

# ----- logging to file -----
LOGFILE=${HOME:-/root}/setup.log
[[ $EUID -eq 0 && -w /var/log ]] && LOGFILE="/var/log/setup-$(date +%F_%H-%M-%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

# ----- detect “target” user & sudo helper -----
detect_user() {
  if [[ -n ${SUDO_USER:-} && $EUID -eq 0 ]]; then
    TARGET_USER=$SUDO_USER          # script run via sudo
  else
    TARGET_USER=$USER               # normal user or pure root
  fi
  HOME_DIR=$(eval echo "~$TARGET_USER")

  if [[ $EUID -eq 0 ]]; then
    SUDO=""
    # run-as-user helper
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
detect_user        # always run – we need $HOME_DIR, RAU, SUDO

##############################################################################
### 1. Minimal prerequisites                                             ####
##############################################################################
install_prereqs() {
  $SUDO apt-get update -y
  local pkgs=(git openssh-client curl wget gnupg ca-certificates lsb-release xclip xsel unzip)
  $SUDO apt-get install -y "${pkgs[@]}"
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

    # 🛡️ Don’t overwrite authorized_keys if it’s a Proxmox symlink
    if RAU "[[ -L '$AUTH_KEYS' ]]"; then
      warn "'authorized_keys' is a symlink – skipping any overwrite"
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

  read -r  # Wait for confirmation
  RAU "ssh -o StrictHostKeyChecking=no -T git@github.com" || warn "GitHub SSH test may fail on first run"
}

##############################################################################
### 3. Full upgrade & base toolchain                                     ####
##############################################################################
install_toolchain() {
  info "Upgrading system …"
  $SUDO apt-get full-upgrade -y

  # --- packages you asked for (minus eza fallback logic) ---
  local pkgs=(
    xsel xclip python3 python3-venv npm bat screen fzf zoxide
    zsh git ripgrep tmux thefuck delta git-delta
    build-essential cmake gcc fontconfig jq curl wget gnupg ca-certificates
    eza                     # try first via APT
  )
  $SUDO apt-get install -y "${pkgs[@]}" || warn "Some APT packages failed – continuing"

  # --- if eza is still missing, fetch latest GitHub binary ---
  if ! command -v eza &>/dev/null; then
    warn "eza not in APT – installing from GitHub …"
    local ver arch url tmp
    ver=$(curl -s https://api.github.com/repos/eza-community/eza/releases/latest \
            | grep -Po '"tag_name": *"v\\K[^"]+')
    arch=$(dpkg --print-architecture | sed 's/amd64/x86_64/;s/arm64/aarch64/')
    url="https://github.com/eza-community/eza/releases/download/v${ver}/eza_${ver}_linux_${arch}.tar.gz"

    tmp=$(mktemp -d)
    if curl -sL "$url" -o "$tmp/eza.tar.gz"; then
      tar -xzf "$tmp/eza.tar.gz" -C "$tmp"
      $SUDO install "$tmp"/eza*/eza -t /usr/local/bin
      rm -rf "$tmp"
    else
      warn "GitHub download failed"
      rm -rf "$tmp"
    fi
  fi

  # --- final fallback: exa ➜ eza symlink -----------------------------------
  if ! command -v eza &>/dev/null; then
    warn "eza still missing – falling back to exa if available"
    if command -v exa &>/dev/null; then
      $SUDO ln -sf "$(command -v exa)" /usr/local/bin/eza
      info "Created /usr/local/bin/eza → exa"
    else
      warn "exa also not present – no colourful ls replacement installed"
    fi
  else
    info "✔ eza ready at $(command -v eza)"
  fi
}

##############################################################################
### 4. Neovim – grab newest stable tag with ANY valid tarball name        ####
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
    current=$(RAU "nvim --version | head -n1 | awk '{print \$2}'")
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
### 5. Z-shell, Oh-My-Zsh, Powerlevel10k                                 ####
##############################################################################
setup_zsh() {
  $SUDO chsh -s "$(command -v zsh)" "$TARGET_USER" || true

  [[ -d "$HOME_DIR/.oh-my-zsh" ]] || \
    RAU "sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" '' --unattended"

  RAU "mkdir -p '$HOME_DIR/.oh-my-zsh/custom/themes' '$HOME_DIR/.oh-my-zsh/custom/plugins'"
  [[ -d "$HOME_DIR/.oh-my-zsh/custom/themes/powerlevel10k" ]] || \
    RAU "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git '$HOME_DIR/.oh-my-zsh/custom/themes/powerlevel10k'"

  for repo in \
    zsh-users/zsh-autosuggestions \
    zsh-users/zsh-syntax-highlighting \
    joshskidmore/zsh-fzf-history-search; do
      local name=${repo##*/}
      [[ -d "$HOME_DIR/.oh-my-zsh/custom/plugins/$name" ]] || \
        RAU "git clone --depth=1 https://github.com/$repo '$HOME_DIR/.oh-my-zsh/custom/plugins/$name'"
  done
}

##############################################################################
### 6. Clone dotfiles (SSH → HTTPS fallback)                              ####
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

  # ALWAYS sync sub-modules
  RAU "git -C '$proj/config' submodule update --init --recursive"
}

##############################################################################
### 7. Symlink configuration                                              ####
##############################################################################
create_symlinks() {
  local proj="$HOME_DIR/projects"
  RAU "mkdir -p '$HOME_DIR/.config' '$HOME_DIR/.local/share/fonts'"

  #link() { RAU "ln -snf '$1' '$2'"; }
  link() {
    local src="$1" dest="$2"
    RAU "[[ -e '$dest' || -L '$dest' ]]" && RAU "rm -rf '$dest'"
    RAU "ln -s '$src' '$dest'"
  }

  # core
  link "$proj/config/nvim"            "$HOME_DIR/.config/nvim"
  link "$proj/config/tmux"            "$HOME_DIR/.config/tmux"
  link "$proj/config/home/zshrc"      "$HOME_DIR/.zshrc"
  link "$proj/config/bat"             "$HOME_DIR/.config/bat"
  link "$proj/config/home/gitconfig"  "$HOME_DIR/.gitconfig"
  link "$proj/config/home/p10k.zsh"   "$HOME_DIR/.p10k.zsh"

  # extras (long list the user provided)
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
### 8. Nerd Font                                                          ####
##############################################################################
install_font() {
  local dir="$HOME_DIR/.local/share/fonts"
  [[ -f "$dir/MesloLGS NF Regular.ttf" ]] && return 0
  wget -qO /tmp/Meslo.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/Meslo.zip
  RAU "unzip -oq /tmp/Meslo.zip -d '$dir'"
  rm /tmp/Meslo.zip
  fc-cache -fv
}

##############################################################################
### 9. Lazygit                                                            ####
##############################################################################
install_lazygit() {
  RAU "command -v lazygit" &>/dev/null && return 0
  local ver arch url
  ver=$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest \
        | grep -Po '"tag_name": *"v\K[^"]+')
  arch=$(dpkg --print-architecture | sed 's/amd64/x86_64/;s/arm64/aarch64/')
  url="https://github.com/jesseduffield/lazygit/releases/download/v${ver}/lazygit_${ver}_Linux_${arch}.tar.gz"
  curl -sL "$url" -o /tmp/lazygit.tar.gz
  tar -xf /tmp/lazygit.tar.gz -C /tmp lazygit
  $SUDO install /tmp/lazygit -t /usr/local/bin
  rm /tmp/lazygit /tmp/lazygit.tar.gz
}

##############################################################################
### 10. (optional) telescope-fzf-native build                             ####
##############################################################################
build_telescope_fzf() {
  RAU "test -d '$HOME_DIR/.local/share/nvim/lazy/telescope-fzf-native.nvim'" \
    || { info "telescope-fzf-native not present – skipping"; return 0; }
  RAU "make -C '$HOME_DIR/.local/share/nvim/lazy/telescope-fzf-native.nvim'"
}

##############################################################################
### 11. Sync Neovim plugins (Lazy.nvim)                                   ####
##############################################################################
sync_nvim_plugins() {
  info "Syncing Neovim plugins …"
  RAU "nvim --headless '+Lazy! sync' +qa" || warn "Lazy sync failed"
}

##############################################################################
### 12. Rebuild bat cache                                                 ####
##############################################################################
rebuild_bat_cache() {
  RAU "test -d '$HOME_DIR/.config/bat/themes'" || return 0
  if command -v batcat &>/dev/null; then
    RAU "batcat cache --build"
  else
    RAU "bat cache --build"
  fi
}

############################################################################
### 13.  CLI short-circuit  ★ NEW ★                                    ###
############################################################################
if (( $# )); then
  # user passed module names: run only those, then exit
  for mod in "$@"; do
    if declare -f "$mod" >/dev/null; then
      run_step "$mod" "$mod"
    else
      warn "No such module: $mod"; FAILED_STEPS+=("$mod (not found)")
    fi
  done

  if ((${#FAILED_STEPS[@]})); then
    warn "Finished with ${#FAILED_STEPS[@]} module(s) needing attention:"
    for s in "${FAILED_STEPS[@]}"; do warn "  • $s"; done
  else
    info "Requested module(s) completed successfully."
  fi
  exit
fi

############################################################################
### 14.  Normal full-run sequence (unchanged order)                     ###
############################################################################
run_step "Prerequisites"              install_prereqs
run_step "Git & SSH setup"            setup_git_ssh
run_step "System upgrade & toolchain" install_toolchain
run_step "Neovim"                     install_neovim
run_step "Zsh / Oh-My-Zsh"            setup_zsh
run_step "Clone dotfiles"             clone_dotfiles
run_step "Create symlinks"            create_symlinks
run_step "Nerd Font"                  install_font
run_step "Lazygit"                    install_lazygit
run_step "telescope-fzf build"        build_telescope_fzf
run_step "sync nvim plugins"          sync_nvim_plugins
run_step "bat cache rebuild"          rebuild_bat_cache

############################################################################
### 15.  Wrap-up (unchanged)                                            ###
############################################################################
if ((${#FAILED_STEPS[@]})); then
  warn "Finished with ${#FAILED_STEPS[@]} module(s) needing attention:"
  for s in "${FAILED_STEPS[@]}"; do warn "  • $s"; done
  warn "Re-run the script after fixing or network issues – it's safe."
else
  info "🎉 All modules completed successfully!  Open a new terminal (zsh + P10k) and enjoy."
fi
