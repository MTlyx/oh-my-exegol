#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SETUP_DIR="$SCRIPT_DIR/setup"
DEFAULT_MY_RESOURCES="$HOME/.exegol/my-resources"
EXEGOL_CONFIG_FILE="$HOME/.exegol/config.yml"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

MARKER_BEGIN="# BEGIN oh-my-exegol"
MARKER_END="# END oh-my-exegol"
LEGACY_SYSTEM_UPDATE_MARKER_BEGIN="# BEGIN exegol-system-update-template"
LEGACY_SYSTEM_UPDATE_MARKER_END="# END exegol-system-update-template"

UNINSTALL=0

if [[ -t 1 ]]; then
  COLOR_BLUE=$'\033[1;34m'
  COLOR_GREEN=$'\033[1;32m'
  COLOR_YELLOW=$'\033[1;33m'
  COLOR_RED=$'\033[1;31m'
  COLOR_DIM=$'\033[2m'
  COLOR_RESET=$'\033[0m'
else
  COLOR_BLUE=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_RED=""
  COLOR_DIM=""
  COLOR_RESET=""
fi

status_color() {
  case "$1" in
    add|chmod|done|update) printf '%s' "$COLOR_GREEN" ;;
    backup|keep|skip) printf '%s' "$COLOR_YELLOW" ;;
    remove|warn) printf '%s' "$COLOR_RED" ;;
    *) printf '%s' "$COLOR_BLUE" ;;
  esac
}

log_info() {
  printf '%s[*]%s %s\n' "$COLOR_BLUE" "$COLOR_RESET" "$1"
}

log_success() {
  printf '%s[+]%s %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$1"
}

log_warning() {
  printf '%s[!]%s %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$1"
}

log_error() {
  printf '%s[-]%s %s\n' "$COLOR_RED" "$COLOR_RESET" "$1"
}

log_detail() {
  printf '  %s%s%s\n' "$COLOR_DIM" "$1" "$COLOR_RESET"
}

log_status() {
  local status="$1"
  local message="$2"
  if [[ "${VERBOSE:-0}" -eq 1 ]]; then
    printf '  %s%-7s%s %s\n' "$(status_color "$status")" "$status" "$COLOR_RESET" "$message"
  fi
}

usage() {
  cat <<'EOF'
Usage: ./install.sh [--uninstall]

Installs oh-my-exegol hooks into your Exegol my-resources path.

Options:
  --uninstall      Remove oh-my-exegol hooks from your my-resources path
  -h, --help       Show this help
EOF
}

expand_path() {
  local path="$1"
  if [[ "$path" == "~/"* ]]; then
    printf '%s\n' "$HOME/${path#~/}"
  else
    printf '%s\n' "$path"
  fi
}

detect_my_resources_path() {
  local detected=""

  if [[ -f "$EXEGOL_CONFIG_FILE" ]]; then
    detected="$(
      awk '
        /^[[:space:]]*my_resources_path:/ {
          sub(/^[[:space:]]*my_resources_path:[[:space:]]*/, "", $0)
          print
          exit
        }
      ' "$EXEGOL_CONFIG_FILE"
    )"
  fi

  if [[ -z "$detected" ]]; then
    printf '%s\n' "$DEFAULT_MY_RESOURCES"
  else
    expand_path "$detected"
  fi
}

backup_file() {
  local file_path="$1"
  if [[ -f "$file_path" ]]; then
    cp -a "$file_path" "${file_path}.bak.${TIMESTAMP}"
    log_status "backup" "$file_path -> ${file_path}.bak.${TIMESTAMP}"
  fi
}

copy_if_missing_or_force() {
  local src="$1"
  local dst="$2"
  local force="${3:-0}"
  local backup="${4:-1}"

  mkdir -p "$(dirname "$dst")"

  if [[ -f "$dst" ]]; then
    if cmp -s "$src" "$dst"; then
      log_status "keep" "$dst"
      return
    fi
    if [[ "$force" -eq 1 ]]; then
      if [[ "$backup" -eq 1 ]]; then
        backup_file "$dst"
      fi
      cp -a "$src" "$dst"
      log_status "update" "$dst"
    else
      log_status "keep" "$dst"
    fi
  else
    cp -a "$src" "$dst"
    log_status "add" "$dst"
  fi
}

ensure_marker_block() {
  local file_path="$1"
  local block_content="$2"

  mkdir -p "$(dirname "$file_path")"

  if [[ ! -f "$file_path" ]]; then
    printf '%s\n' "$block_content" > "$file_path"
    log_status "add" "$file_path"
    return
  fi

  if grep -Fq "$MARKER_BEGIN" "$file_path"; then
    log_status "keep" "$file_path"
    return
  fi

  backup_file "$file_path"
  printf '\n%s\n' "$block_content" >> "$file_path"
  log_status "update" "$file_path"
}

remove_marker_block() {
  local file_path="$1"
  local marker_begin="${2:-$MARKER_BEGIN}"
  local marker_end="${3:-$MARKER_END}"
  local tmp_file=""
  local normalized_contents=""

  if [[ ! -f "$file_path" ]]; then
    log_status "skip" "$file_path"
    return
  fi

  if ! grep -Fq "$marker_begin" "$file_path"; then
    log_status "skip" "$file_path"
    return
  fi

  tmp_file="$(mktemp)"

  awk -v begin="$marker_begin" -v end="$marker_end" '
    index($0, begin) { skipping=1; next }
    index($0, end) { skipping=0; next }
    !skipping { print }
  ' "$file_path" > "$tmp_file"

  normalized_contents="$(sed -e 's/[[:space:]]//g' "$tmp_file")"

  if [[ ! -s "$tmp_file" ]] || \
     ! grep -q '[^[:space:]]' "$tmp_file" || \
     [[ "$normalized_contents" == "#!/bin/bash" ]] || \
     [[ "$normalized_contents" == "#!/usr/bin/envbash" ]]; then
    rm -f "$file_path"
    log_status "remove" "$file_path"
  else
    backup_file "$file_path"
    mv "$tmp_file" "$file_path"
    log_status "update" "$file_path"
    return
  fi

  rm -f "$tmp_file"
}

remove_marker_block_if_present() {
  local file_path="$1"
  local marker_begin="$2"
  local marker_end="$3"

  if [[ -f "$file_path" ]] && grep -Fq "$marker_begin" "$file_path"; then
    remove_marker_block "$file_path" "$marker_begin" "$marker_end"
  fi
}

remove_file_if_exists() {
  local file_path="$1"
  local backup="${2:-1}"

  if [[ ! -f "$file_path" ]]; then
    log_status "skip" "$file_path"
    return
  fi

  if [[ "$backup" -eq 1 ]]; then
    backup_file "$file_path"
  fi
  rm -f "$file_path"
  log_status "remove" "$file_path"
}

remove_legacy_file_if_exists() {
  local file_path="$1"

  if [[ -f "$file_path" ]]; then
    remove_file_if_exists "$file_path"
  fi
}

remove_owned_file_if_exists() {
  local file_path="$1"

  if [[ -f "$file_path" ]]; then
    remove_file_if_exists "$file_path" 0
  fi
}

remove_owned_backup_files() {
  local file_path="$1"
  local backup_file=""

  shopt -s nullglob
  for backup_file in "${file_path}".bak.*; do
    rm -f "$backup_file"
    log_status "remove" "$backup_file"
  done
  shopt -u nullglob
}

remove_legacy_system_update_load_user_if_owned() {
  local file_path="$1"

  if [[ ! -f "$file_path" ]]; then
    return
  fi

  if grep -Fq '/root/.config/exegol-tooling' "$file_path" && \
     grep -Fq 'prompt-system-update' "$file_path" && \
     grep -Fq 'System update prompt scheduled' "$file_path"; then
    remove_file_if_exists "$file_path" 0
  fi
}

remove_dir_if_empty() {
  local dir_path="$1"

  if [[ -d "$dir_path" ]] && [[ -z "$(find "$dir_path" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    rmdir "$dir_path"
    log_status "remove" "$dir_path"
  fi
}

ensure_executable_if_possible() {
  local file_path="$1"

  if [[ ! -f "$file_path" ]]; then
    return
  fi

  if [[ -x "$file_path" ]]; then
    return
  fi

  if chmod +x "$file_path" 2>/dev/null; then
    log_status "chmod" "$file_path"
  else
    log_status "warn" "could not chmod $file_path; keeping current mode" >&2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

TARGET_MY_RESOURCES="$(detect_my_resources_path)"
TARGET_SETUP_DIR="$TARGET_MY_RESOURCES/setup"
TARGET_ZSH_DIR="$TARGET_SETUP_DIR/zsh"

LOAD_USER_SETUP_BLOCK="$(cat <<'EOF'
# BEGIN oh-my-exegol
mkdir -p /root/.config/oh-my-exegol
touch /root/.config/oh-my-exegol/prompt-important-tool-updates
printf "[*] Important tools update prompt scheduled for the first interactive shell\n"
# END oh-my-exegol
EOF
)"

ZSHRC_BLOCK="$(cat <<'EOF'
# BEGIN oh-my-exegol
if [[ -f /opt/my-resources/setup/zsh/oh-my-exegol.zsh ]]; then
  source /opt/my-resources/setup/zsh/oh-my-exegol.zsh
fi
# END oh-my-exegol
EOF
)"

if [[ "$UNINSTALL" -eq 1 ]]; then
  log_info "Uninstalling oh-my-exegol"
  log_detail "Target path: $TARGET_MY_RESOURCES"

  remove_marker_block "$TARGET_SETUP_DIR/load_user_setup.sh"
  remove_marker_block "$TARGET_ZSH_DIR/zshrc"
  remove_marker_block_if_present "$TARGET_ZSH_DIR/zshrc" "$LEGACY_SYSTEM_UPDATE_MARKER_BEGIN" "$LEGACY_SYSTEM_UPDATE_MARKER_END"
  remove_legacy_system_update_load_user_if_owned "$TARGET_SETUP_DIR/load_user_setup.sh"

  remove_owned_file_if_exists "$TARGET_ZSH_DIR/oh-my-exegol.zsh"
  remove_owned_backup_files "$TARGET_ZSH_DIR/oh-my-exegol.zsh"
  remove_owned_file_if_exists "$TARGET_ZSH_DIR/system-update-prompt.zsh"
  remove_owned_backup_files "$TARGET_ZSH_DIR/system-update-prompt.zsh"

  remove_dir_if_empty "$TARGET_ZSH_DIR"
  remove_dir_if_empty "$TARGET_SETUP_DIR"

  log_success "oh-my-exegol uninstalled"
  exit 0
fi

log_info "Installing oh-my-exegol"
log_detail "Target path: $TARGET_MY_RESOURCES"

mkdir -p "$TARGET_ZSH_DIR"

copy_if_missing_or_force "$SOURCE_SETUP_DIR/zsh/oh-my-exegol.zsh" "$TARGET_ZSH_DIR/oh-my-exegol.zsh" 1 0
remove_marker_block_if_present "$TARGET_ZSH_DIR/zshrc" "$LEGACY_SYSTEM_UPDATE_MARKER_BEGIN" "$LEGACY_SYSTEM_UPDATE_MARKER_END"
remove_owned_file_if_exists "$TARGET_ZSH_DIR/system-update-prompt.zsh"

if [[ -f "$TARGET_SETUP_DIR/load_user_setup.sh" ]]; then
  remove_legacy_system_update_load_user_if_owned "$TARGET_SETUP_DIR/load_user_setup.sh"
fi

if [[ -f "$TARGET_SETUP_DIR/load_user_setup.sh" ]]; then
  ensure_marker_block "$TARGET_SETUP_DIR/load_user_setup.sh" "$LOAD_USER_SETUP_BLOCK"
else
  copy_if_missing_or_force "$SOURCE_SETUP_DIR/load_user_setup.sh" "$TARGET_SETUP_DIR/load_user_setup.sh" 1
fi

ensure_marker_block "$TARGET_ZSH_DIR/zshrc" "$ZSHRC_BLOCK"

ensure_executable_if_possible "$TARGET_SETUP_DIR/load_user_setup.sh"

log_success "oh-my-exegol installed"
log_info "Start or reopen a container shell, e.g. exegol start mybox full"
