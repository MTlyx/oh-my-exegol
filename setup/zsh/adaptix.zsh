# =============================================================================
# adaptix.zsh — Adaptix C2 helpers for Exegol
#
# Sourced automatically via zshrc → oh-my-exegol.zsh.
# On first container start: prompts to install AdaptixC2 (build, SSL, profile).
# After install: adaptixserver/adaptixclient are available.
# =============================================================================

# ── Paths ─────────────────────────────────────────────────────────────────────
_adaptix_dir="/opt/AdaptixC2"
_adaptix_server="${_adaptix_dir}/dist/adaptixserver"
_adaptix_profile="${_adaptix_dir}/dist/profile.yaml"
_adaptix_ssl_key="${_adaptix_dir}/dist/server.rsa.key"
_adaptix_ssl_crt="${_adaptix_dir}/dist/server.rsa.crt"

_adaptix_appimage="${_adaptix_dir}/AdaptixClient-x86_64.AppImage"
_adaptix_client_dir="${_adaptix_dir}/squashfs-root"
_adaptix_client_bin="${_adaptix_client_dir}/AppRun"

# install-adaptix.sh lives next to this file in setup/zsh/
_adaptix_install_script="${${(%):-%x}:A:h}/install-adaptix.sh"

_adaptix_state_dir="${HOME}/.config/oh-my-exegol"
_adaptix_prompt_file="${_adaptix_state_dir}/prompt-adaptix-install"
_adaptix_choice_file="${_adaptix_state_dir}/adaptix-install.choice"
_adaptix_install_choice_asked=0

# ── Colour helpers ────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  _adaptix_blue=$'\033[1;34m'
  _adaptix_green=$'\033[1;32m'
  _adaptix_yellow=$'\033[1;33m'
  _adaptix_red=$'\033[1;31m'
  _adaptix_reset=$'\033[0m'
else
  _adaptix_blue="" _adaptix_green="" _adaptix_yellow="" _adaptix_red="" _adaptix_reset=""
fi

_adaptix_info()    { printf "%s[*]%s %s\n" "$_adaptix_blue"   "$_adaptix_reset" "$*"; }
_adaptix_success() { printf "%s[+]%s %s\n" "$_adaptix_green"  "$_adaptix_reset" "$*"; }
_adaptix_warn()    { printf "%s[!]%s %s\n" "$_adaptix_yellow" "$_adaptix_reset" "$*"; }
_adaptix_error()   { printf "%s[-]%s %s\n" "$_adaptix_red"    "$_adaptix_reset" "$*"; }

# ── SSL generation ────────────────────────────────────────────────────────────
_adaptix_gen_ssl() {
  if [[ -f "$_adaptix_ssl_crt" && -f "$_adaptix_ssl_key" ]]; then
    return 0  # already generated
  fi

  (cd "${_adaptix_dir}/dist" && \
    openssl req -x509 -nodes -newkey rsa:2048 \
      -keyout server.rsa.key \
      -out    server.rsa.crt \
      -days   3650 \
      -subj   "/CN=exegol.com/O=exegol/C=FR") 2>/dev/null

  if [[ -f "$_adaptix_ssl_crt" && -f "$_adaptix_ssl_key" ]]; then
    _adaptix_success "SSL certificate generated"
  else
    _adaptix_error "SSL generation failed"
    return 1
  fi
}

# ── Profile generation ────────────────────────────────────────────────────────
# All paths are relative — server runs from dist/ via (cd dist && ./adaptixserver)
_adaptix_gen_profile() {
  _adaptix_info "Writing profile.yaml"
  cat > "$_adaptix_profile" << 'PROFILE'
Teamserver:
  interface: "0.0.0.0"
  port: 8443
  endpoint: "/endpoint"
  password: "exegol4thewin"
  only_password: true
  cert: "server.rsa.crt"
  key: "server.rsa.key"
  extenders:
    - "extenders/beacon_listener_http/config.yaml"
    - "extenders/beacon_listener_smb/config.yaml"
    - "extenders/beacon_listener_tcp/config.yaml"
    - "extenders/beacon_listener_dns/config.yaml"
    - "extenders/beacon_agent/config.yaml"
    - "extenders/gopher_listener_tcp/config.yaml"
    - "extenders/gopher_agent/config.yaml"
  axscripts:
  access_token_live_hours: 12
  refresh_token_live_hours: 168

HttpServer:
  error:
    status: 404
    headers:
      Content-Type: "text/html; charset=UTF-8"
      Server: "nginx"
    page: "404page.html"
  http:
    max_header_bytes: 8192
    read_header_timeout_sec: 0
    read_timeout_sec: 0
    write_timeout_sec: 0
    idle_timeout_sec: 0
    request_timeout_sec: 300
    request_timeout_message: "504 Gateway Timeout"
    disable_keep_alives: false
    enable_http2: true
  tls:
    min_version: "TLS1.2"
    max_version: "TLS1.3"
    prefer_server_cipher_suites: false
    cipher_suites:
      - "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
      - "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
      - "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
      - "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
      - "TLS_RSA_WITH_AES_128_GCM_SHA256"
      - "TLS_RSA_WITH_AES_256_GCM_SHA384"
PROFILE

  if [[ -f "$_adaptix_profile" ]]; then
    _adaptix_success "profile.yaml written at $_adaptix_profile"
  else
    _adaptix_error "Failed to write profile.yaml"
    return 1
  fi
}

# ── AppImage extraction ───────────────────────────────────────────────────────
_adaptix_extract_client() {
  if [[ ! -f "$_adaptix_appimage" ]]; then
    return 0  # no AppImage present, skip silently
  fi

  if [[ -x "$_adaptix_client_bin" ]]; then
    return 0  # already extracted
  fi

  (cd "$_adaptix_dir" && "$_adaptix_appimage" --appimage-extract > /dev/null 2>&1)

  if [[ -x "$_adaptix_client_bin" ]]; then
    _adaptix_success "AdaptixClient extracted at $_adaptix_client_dir"
  else
    _adaptix_error "AppImage extraction failed"
    return 1
  fi
}

# ── Client profile generation ─────────────────────────────────────────────────
_adaptix_gen_client_profile() {
  local db_dir="/root/.adaptix"
  local db_file="${db_dir}/storage-v1.db"
  local project_name="exegol"
  local project_dir="/root/AdaptixProjects/${project_name}"

  if ! command -v sqlite3 >/dev/null 2>&1; then
    _adaptix_warn "sqlite3 not found, skipping client profile generation"
    return 0
  fi

  mkdir -p "$db_dir" "$project_dir"

  sqlite3 "$db_file" "CREATE TABLE IF NOT EXISTS Projects ( project TEXT UNIQUE PRIMARY KEY, data TEXT );"
  sqlite3 "$db_file" "CREATE TABLE IF NOT EXISTS Extensions ( filepath TEXT UNIQUE PRIMARY KEY, enabled BOOLEAN );"
  sqlite3 "$db_file" "CREATE TABLE IF NOT EXISTS Settings ( key TEXT UNIQUE PRIMARY KEY, data TEXT );"
  sqlite3 "$db_file" "CREATE TABLE IF NOT EXISTS ListenerProfiles ( project TEXT, name TEXT, data TEXT, PRIMARY KEY (project, name) );"
  sqlite3 "$db_file" "CREATE TABLE IF NOT EXISTS AgentProfiles ( project TEXT, name TEXT, data TEXT, PRIMARY KEY (project, name) );"

  sqlite3 "$db_file" "INSERT OR REPLACE INTO Projects VALUES(
    '${project_name}',
    '{\"consoleMultiuser\":true,\"endpoint\":\"/endpoint\",\"host\":\"127.0.0.1\",\"password\":\"exegol4thewin\",\"port\":\"8443\",\"projectDir\":\"${project_dir}\",\"subscriptions\":[\"chat_history\",\"downloads_history\",\"screenshot_history\",\"credentials_history\",\"targets_history\",\"console_history\",\"tasks_history\",\"chat_realtime\",\"downloads_realtime\",\"screenshot_realtime\",\"credentials_realtime\",\"targets_realtime\",\"notifications\",\"tunnels\",\"tasks_manager\"],\"username\":\"exegol\"}'
  );"

  if [[ $? -eq 0 ]]; then
    _adaptix_success "AdaptixClient profile '${project_name}' created in ${db_file}"
  else
    _adaptix_error "Failed to create AdaptixClient profile"
    return 1
  fi
}

# ── First-start install prompt ────────────────────────────────────────────────
_adaptix_prompt_install_choice() {
  local reply=""

  if [[ ! -o interactive || ! -t 0 || ! -t 1 ]]; then
    return
  fi

  if [[ ! -f "$_adaptix_prompt_file" || -f "$_adaptix_choice_file" ]]; then
    return
  fi

  _adaptix_install_choice_asked=1

  printf "%s[?]%s Install AdaptixC2 now? This will build the server, generate SSL and create profile.yaml. %s[y/N]%s " \
    "$_adaptix_blue" "$_adaptix_reset" "$_adaptix_yellow" "$_adaptix_reset"
  read -r reply

  case "$reply" in
    [Yy]|[Yy][Ee][Ss])
      printf "yes\n" > "$_adaptix_choice_file"
      ;;
    *)
      printf "no\n" > "$_adaptix_choice_file"
      ;;
  esac

  rm -f "$_adaptix_prompt_file"
}

_adaptix_run_install_choice() {
  if [[ "$_adaptix_install_choice_asked" -ne 1 || ! -f "$_adaptix_choice_file" ]]; then
    return
  fi

  if [[ "$(cat "$_adaptix_choice_file")" != "yes" ]]; then
    _adaptix_info "Skipping AdaptixC2 install"
    return
  fi

  if [[ ! -f "$_adaptix_install_script" ]]; then
    _adaptix_error "install-adaptix.sh not found at $_adaptix_install_script"
    return 1
  fi

  _oh_my_exegol_run_with_spinner "AdaptixC2 build"      bash "$_adaptix_install_script" || {
    _adaptix_error "install-adaptix.sh failed — check $_oh_my_exegol_log_file"
    return 1
  }
  _oh_my_exegol_run_with_spinner "AdaptixC2 SSL"        _adaptix_gen_ssl
  _oh_my_exegol_run_with_spinner "AdaptixC2 profile"    _adaptix_gen_profile
  _oh_my_exegol_run_with_spinner "AdaptixClient extract" _adaptix_extract_client
  _oh_my_exegol_run_with_spinner "AdaptixClient profile" _adaptix_gen_client_profile
}

# ── adaptixserver ─────────────────────────────────────────────────────────────
adaptixserver() {
  if [[ ! -x "$_adaptix_server" ]]; then
    _adaptix_error "adaptixserver binary not found at $_adaptix_server"
    _adaptix_info  "Answer [y] at the install prompt on next shell start, or re-open the container"
    return 1
  fi

  if [[ ! -f "$_adaptix_profile" ]]; then
    _adaptix_error "profile.yaml not found at $_adaptix_profile"
    _adaptix_info  "Run: _adaptix_gen_ssl && _adaptix_gen_profile"
    return 1
  fi

  local log_file="/opt/AdaptixC2/adaptixserver.log"

  _adaptix_info "Starting AdaptixC2 — port 8443 — profile: $_adaptix_profile"

  (cd "${_adaptix_dir}/dist" && "$_adaptix_server" --profile "$_adaptix_profile" "$@") > "$log_file" 2>&1 &

  local pid=$!
  local i=0
  while [[ $i -lt 30 ]]; do
    if grep -q "The AdaptixC2 server is ready" "$log_file" 2>/dev/null; then
      break
    fi
    sleep 1
    (( i++ ))
  done

  if grep -q "The AdaptixC2 server is ready" "$log_file" 2>/dev/null; then
    _adaptix_success "AdaptixC2 is running in background (PID ${pid}) — logs: ${log_file}"
  else
    _adaptix_error "AdaptixC2 did not become ready in time — check ${log_file}"
  fi
}

# ── adaptixclient ─────────────────────────────────────────────────────────────
adaptixclient() {
  _adaptix_extract_client || return 1

  if [[ ! -x "$_adaptix_client_bin" ]]; then
    _adaptix_error "AdaptixClient not found at $_adaptix_client_bin"
    _adaptix_info  "AppImage may be missing from /opt/AdaptixC2 — check load_user_setup.sh ran correctly"
    return 1
  fi

  "$_adaptix_client_bin" "$@"
}
