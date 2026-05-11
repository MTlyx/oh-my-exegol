# Prompt for important Exegol tool updates on the first interactive shell.
_oh_my_exegol_state_dir="${HOME}/.config/oh-my-exegol"
_oh_my_exegol_prompt_file="${_oh_my_exegol_state_dir}/prompt-important-tool-updates"
_oh_my_exegol_choice_file="${_oh_my_exegol_state_dir}/important-tool-updates.choice"
_oh_my_exegol_log_file="${_oh_my_exegol_state_dir}/important-tool-updates.log"
_oh_my_exegol_netexec_dir="/opt/tools/NetExec"

if [[ -t 1 ]]; then
  _oh_my_exegol_color_blue=$'\033[1;34m'
  _oh_my_exegol_color_green=$'\033[1;32m'
  _oh_my_exegol_color_yellow=$'\033[1;33m'
  _oh_my_exegol_color_red=$'\033[1;31m'
  _oh_my_exegol_color_reset=$'\033[0m'
else
  _oh_my_exegol_color_blue=""
  _oh_my_exegol_color_green=""
  _oh_my_exegol_color_yellow=""
  _oh_my_exegol_color_red=""
  _oh_my_exegol_color_reset=""
fi

_oh_my_exegol_log() {
  local marker="$1"
  local color="$2"
  local message="$3"

  printf "%s%s%s %s%s%s\n" "$color" "$marker" "$_oh_my_exegol_color_reset" "$color" "$message" "$_oh_my_exegol_color_reset"
}

_oh_my_exegol_log_info() {
  _oh_my_exegol_log "[*]" "$_oh_my_exegol_color_blue" "$1"
}

_oh_my_exegol_log_success() {
  _oh_my_exegol_log "[+]" "$_oh_my_exegol_color_green" "$1"
}

_oh_my_exegol_log_warn() {
  _oh_my_exegol_log "[!]" "$_oh_my_exegol_color_yellow" "$1"
}

_oh_my_exegol_log_error() {
  _oh_my_exegol_log "[-]" "$_oh_my_exegol_color_red" "$1"
}

_oh_my_exegol_log_to_file() {
  printf "%s\n" "$1" >> "$_oh_my_exegol_log_file"
}

_oh_my_exegol_run_with_spinner() {
  setopt local_options no_monitor no_notify

  local label="$1"
  shift

  local spinner_frames=( "⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏" )
  local frame_index=1
  local command_pid=0
  local command_status=0
  local tmp_log=""

  tmp_log="$(mktemp)"
  _oh_my_exegol_log_to_file ""
  _oh_my_exegol_log_to_file "==> ${label}"

  ( "$@" < /dev/null > "$tmp_log" 2>&1 ) &
  command_pid=$!

  while kill -0 "$command_pid" 2>/dev/null; do
    printf "\r%s%s%s %s" \
      "$_oh_my_exegol_color_yellow" "${spinner_frames[$frame_index]}" "$_oh_my_exegol_color_reset" \
      "$label"
    frame_index=$(( frame_index % ${#spinner_frames[@]} + 1 ))
    sleep 0.12
  done

  wait "$command_pid"
  command_status=$?

  printf "\r\033[K"
  cat "$tmp_log" >> "$_oh_my_exegol_log_file"
  rm -f "$tmp_log"

  if [[ "$command_status" -eq 0 ]]; then
    _oh_my_exegol_log_success "${label} finished"
  else
    _oh_my_exegol_log_error "${label} failed"
  fi

  return "$command_status"
}

_oh_my_exegol_update_netexec() {
  cd "$_oh_my_exegol_netexec_dir" &&
    git pull &&
    pipx install . --force
}

_oh_my_exegol_update_pip() {
  python3 -m pip install --upgrade pip --break-system-packages
}

_oh_my_exegol_apt_update() {
  DEBIAN_FRONTEND=noninteractive \
  APT_LISTCHANGES_FRONTEND=none \
  NEEDRESTART_MODE=a \
  apt-get \
    -o Acquire::Retries=3 \
    -o Dpkg::Use-Pty=0 \
    -o APT::Color=0 \
    update
}

_oh_my_exegol_apt_upgrade() {
  DEBIAN_FRONTEND=noninteractive \
  APT_LISTCHANGES_FRONTEND=none \
  NEEDRESTART_MODE=a \
  apt-get \
    -o Acquire::Retries=3 \
    -o Dpkg::Use-Pty=0 \
    -o APT::Color=0 \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold \
    --fix-missing \
    -y upgrade
}

_oh_my_exegol_prompt_important_tools_update() {
  local reply=""
  local update_failed=0

  if [[ ! -o interactive || ! -t 0 || ! -t 1 ]]; then
    return
  fi

  if [[ ! -f "$_oh_my_exegol_prompt_file" || -f "$_oh_my_exegol_choice_file" ]]; then
    return
  fi

  mkdir -p "$_oh_my_exegol_state_dir"

  printf "%s[?]%s Update important tools now? This will run apt-get update/upgrade, update pip and update NetExec. %s[y/N]%s " "$_oh_my_exegol_color_blue" "$_oh_my_exegol_color_reset" "$_oh_my_exegol_color_yellow" "$_oh_my_exegol_color_reset"
  read -r reply

  case "$reply" in
    [Yy]|[Yy][Ee][Ss])
      printf "yes\n" > "$_oh_my_exegol_choice_file"
      : > "$_oh_my_exegol_log_file"

      _oh_my_exegol_log_info "Important tools update output will be saved to $_oh_my_exegol_log_file"
      _oh_my_exegol_log_to_file "Important tools update output"

      if command -v apt-get >/dev/null 2>&1; then
        if ! _oh_my_exegol_run_with_spinner "apt update" _oh_my_exegol_apt_update; then
          update_failed=1
        fi
      else
        _oh_my_exegol_log_warn "apt-get is not available, skipping apt update"
        _oh_my_exegol_log_to_file "apt-get is not available, skipping apt update"
      fi

      if command -v apt-get >/dev/null 2>&1; then
        if ! _oh_my_exegol_run_with_spinner "apt upgrade" _oh_my_exegol_apt_upgrade; then
          update_failed=1
        fi
      else
        _oh_my_exegol_log_warn "apt-get is not available, skipping apt upgrade"
        _oh_my_exegol_log_to_file "apt-get is not available, skipping apt upgrade"
      fi

      if command -v python3 >/dev/null 2>&1 && python3 -m pip --version >/dev/null 2>&1; then
        if ! _oh_my_exegol_run_with_spinner "pip update" _oh_my_exegol_update_pip; then
          update_failed=1
        fi
      else
        _oh_my_exegol_log_warn "python3 pip is not available, skipping pip update"
        _oh_my_exegol_log_to_file "python3 pip is not available, skipping pip update"
      fi

      if [[ ! -d "$_oh_my_exegol_netexec_dir" ]]; then
        update_failed=1
        _oh_my_exegol_log_error "NetExec directory not found: $_oh_my_exegol_netexec_dir"
        _oh_my_exegol_log_to_file "NetExec directory not found: $_oh_my_exegol_netexec_dir"
      elif ! command -v git >/dev/null 2>&1; then
        update_failed=1
        _oh_my_exegol_log_error "git is not available, cannot update NetExec"
        _oh_my_exegol_log_to_file "git is not available, cannot update NetExec"
      elif ! command -v pipx >/dev/null 2>&1; then
        update_failed=1
        _oh_my_exegol_log_error "pipx is not available, cannot update NetExec"
        _oh_my_exegol_log_to_file "pipx is not available, cannot update NetExec"
      else
        if ! _oh_my_exegol_run_with_spinner "NetExec update" _oh_my_exegol_update_netexec; then
          update_failed=1
        fi
      fi

      if [[ "$update_failed" -eq 0 ]]; then
        _oh_my_exegol_log_success "Important tools update finished successfully"
        _oh_my_exegol_log_to_file "Important tools update finished successfully"
      else
        _oh_my_exegol_log_error "Important tools update finished with errors"
        _oh_my_exegol_log_to_file "Important tools update finished with errors"
      fi
      ;;
    *)
      printf "no\n" > "$_oh_my_exegol_choice_file"
      _oh_my_exegol_log_info "Skipping important tools update"
      ;;
  esac

  rm -f "$_oh_my_exegol_prompt_file"
}

_oh_my_exegol_prompt_important_tools_update

unset _oh_my_exegol_state_dir
unset _oh_my_exegol_prompt_file
unset _oh_my_exegol_choice_file
unset _oh_my_exegol_log_file
unset _oh_my_exegol_netexec_dir
unset _oh_my_exegol_color_blue
unset _oh_my_exegol_color_green
unset _oh_my_exegol_color_yellow
unset _oh_my_exegol_color_red
unset _oh_my_exegol_color_reset
unfunction _oh_my_exegol_prompt_important_tools_update
unfunction _oh_my_exegol_log
unfunction _oh_my_exegol_log_info
unfunction _oh_my_exegol_log_success
unfunction _oh_my_exegol_log_warn
unfunction _oh_my_exegol_log_error
unfunction _oh_my_exegol_log_to_file
unfunction _oh_my_exegol_run_with_spinner
unfunction _oh_my_exegol_update_netexec
unfunction _oh_my_exegol_update_pip
unfunction _oh_my_exegol_apt_update
unfunction _oh_my_exegol_apt_upgrade
