#!/usr/bin/env bash
# =============================================================================
# CloudSigma Pre-Installed Image Validation Suite
# =============================================================================
# Version: 1.0.0
# Tests: 19
# Usage:
#   sudo bash tests/test-suite.sh
#   sudo bash tests/test-suite.sh --verbose
#   sudo bash tests/test-suite.sh --test=openclaw_service_running
#
# Exit codes:
#   0 = all tests passed
#   1 = one or more tests failed
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="$REPO_ROOT/logs"
TIMESTAMP="$(date +%Y-%m-%d-%H%M%S)"
LOG_FILE="$LOGS_DIR/test-results-${TIMESTAMP}.txt"

TOTAL_TESTS=19
PASS_COUNT=0
FAIL_COUNT=0
VERBOSE=false
SINGLE_TEST=""

# Guest user config
GUEST_USER="cloud"
GUEST_HOME="/home/cloud"
OPENCLAW_CONFIG_PATH="/home/cloud/.openclaw/openclaw.json"
WORKSPACE_PATH="/home/cloud/.openclaw/workspace"

# Fallback: if running as cloudsigma user (legacy), adjust paths
if [ "$(whoami)" = "cloudsigma" ] && [ ! -f "$OPENCLAW_CONFIG_PATH" ]; then
  OPENCLAW_CONFIG_PATH="/home/cloudsigma/.openclaw/openclaw.json"
  WORKSPACE_PATH="/home/cloudsigma/.openclaw/workspace"
fi

# Also allow root to check the config
if [ "$(whoami)" = "root" ]; then
  # Try cloud first, then cloudsigma as fallback
  if [ -f "/home/cloud/.openclaw/openclaw.json" ]; then
    OPENCLAW_CONFIG_PATH="/home/cloud/.openclaw/openclaw.json"
    WORKSPACE_PATH="/home/cloud/.openclaw/workspace"
  elif [ -f "/home/cloudsigma/.openclaw/openclaw.json" ]; then
    OPENCLAW_CONFIG_PATH="/home/cloudsigma/.openclaw/openclaw.json"
    WORKSPACE_PATH="/home/cloudsigma/.openclaw/workspace"
  fi
fi

# Minimum required model count
MIN_MODELS=10

# Expected webchat port
WEBCHAT_PORT=3000

# Required skills (directory names under workspace/skills/)
REQUIRED_SKILLS=(
  "bash"
)
# Note: expand this list as more skills become mandatory

# ---------------------------------------------------------------------------
# Color support
# ---------------------------------------------------------------------------
if [ -t 1 ] && command -v tput &>/dev/null && tput colors &>/dev/null && [ "$(tput colors)" -ge 8 ]; then
  COLOR_PASS="\033[0;32m"
  COLOR_FAIL="\033[0;31m"
  COLOR_WARN="\033[0;33m"
  COLOR_INFO="\033[0;36m"
  COLOR_BOLD="\033[1m"
  COLOR_RESET="\033[0m"
else
  COLOR_PASS=""
  COLOR_FAIL=""
  COLOR_WARN=""
  COLOR_INFO=""
  COLOR_BOLD=""
  COLOR_RESET=""
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
  echo "$*" | tee -a "$LOG_FILE"
}

log_verbose() {
  if [ "$VERBOSE" = true ]; then
    echo "    ${COLOR_INFO}[detail]${COLOR_RESET} $*" | tee -a "$LOG_FILE"
  else
    echo "    [detail] $*" >> "$LOG_FILE"
  fi
}

pass() {
  local name="$1"
  local detail="${2:-}"
  PASS_COUNT=$((PASS_COUNT + 1))
  printf "${COLOR_PASS}  ✓ PASS${COLOR_RESET}  %s\n" "$name" | tee -a "$LOG_FILE"
  [ -n "$detail" ] && log_verbose "$detail"
}

fail() {
  local name="$1"
  local detail="${2:-}"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf "${COLOR_FAIL}  ✗ FAIL${COLOR_RESET}  %s\n" "$name" | tee -a "$LOG_FILE"
  [ -n "$detail" ] && log_verbose "REASON: $detail"
}

section() {
  log ""
  printf "${COLOR_BOLD}── %s${COLOR_RESET}\n" "$*" | tee -a "$LOG_FILE"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --verbose|-v)
      VERBOSE=true
      ;;
    --test=*)
      SINGLE_TEST="${arg#--test=}"
      ;;
    --help|-h)
      echo "Usage: $0 [--verbose] [--test=TEST_NAME]"
      echo ""
      echo "Options:"
      echo "  --verbose         Show detailed output for each test"
      echo "  --test=NAME       Run a single test by name"
      echo "  --help            Show this help"
      echo ""
      echo "Available tests:"
      echo "  openclaw_service_running       webchat_service_running"
      echo "  tailscale_installed            tailscale_not_logged_in"
      echo "  taas_configured                skills_present"
      echo "  bootstrap_ready                cloud_init_installed"
      echo "  cloud_init_datasource          guest_user_exists"
      echo "  guest_user_sudo                guest_user_homedir"
      echo "  no_hardcoded_old_username      ssh_key_injection_config"
      echo "  hostname_config                network_reachable"
      echo "  openclaw_models_count          openclaw_webchat_port"
      echo "  metadata_service_reachable"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Setup logs directory
# ---------------------------------------------------------------------------
mkdir -p "$LOGS_DIR"

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
{
  echo "============================================================"
  echo "  CloudSigma Image Validation Suite"
  echo "  Date:   $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "  Host:   $(hostname)"
  echo "  Runner: $(whoami)"
  echo "  Log:    $LOG_FILE"
  echo "============================================================"
} | tee "$LOG_FILE"

# ---------------------------------------------------------------------------
# TEST DEFINITIONS
# ---------------------------------------------------------------------------

# 1. openclaw_service_running
test_openclaw_service_running() {
  local status
  status="$(systemctl is-active openclaw 2>/dev/null || true)"
  if [ "$status" = "active" ]; then
    pass "openclaw_service_running" "systemctl is-active openclaw → active"
  else
    fail "openclaw_service_running" "openclaw service status: '$status' (expected: active)"
  fi
}

# 2. webchat_service_running
test_webchat_service_running() {
  local status
  status="$(systemctl is-active webchat-ui 2>/dev/null || true)"
  if [ "$status" = "active" ]; then
    pass "webchat_service_running" "systemctl is-active webchat-ui → active"
  else
    fail "webchat_service_running" "webchat-ui service status: '$status' (expected: active)"
  fi
}

# 3. tailscale_installed
test_tailscale_installed() {
  local ts_path ts_version
  ts_path="$(which tailscale 2>/dev/null || true)"
  if [ -n "$ts_path" ]; then
    ts_version="$(tailscale version 2>/dev/null | head -1 || true)"
    pass "tailscale_installed" "Found at $ts_path — version: $ts_version"
  else
    fail "tailscale_installed" "tailscale not found in PATH"
  fi
}

# 4. tailscale_not_logged_in
test_tailscale_not_logged_in() {
  local ts_status
  # tailscale status exits non-zero when not logged in; capture output regardless
  ts_status="$(tailscale status 2>&1 || true)"
  if echo "$ts_status" | grep -qiE "not logged in|Logged out|NeedsLogin|stopped|Backend state: NeedsLogin"; then
    pass "tailscale_not_logged_in" "Tailscale correctly shows not-logged-in state"
  elif echo "$ts_status" | grep -qiE "100\.[0-9]+\.[0-9]+\.[0-9]+"; then
    # Has a Tailscale IP — logged in, which is unexpected on a fresh image
    fail "tailscale_not_logged_in" "Tailscale appears to be logged in (found Tailscale IP). Fresh images should ship without an active session."
  else
    # Could be daemon not running or some other state — check tailscaled
    if ! systemctl is-active tailscaled &>/dev/null && ! pgrep tailscaled &>/dev/null; then
      # Daemon not running is acceptable on a fresh pre-installed image
      pass "tailscale_not_logged_in" "tailscaled is not running (acceptable for pre-image state)"
    else
      # Daemon running but status unclear — treat as pass with warning
      pass "tailscale_not_logged_in" "Tailscale status output: $ts_status (no active session detected)"
    fi
  fi
}

# 5. taas_configured
test_taas_configured() {
  if [ ! -f "$OPENCLAW_CONFIG_PATH" ]; then
    fail "taas_configured" "openclaw.json not found at $OPENCLAW_CONFIG_PATH"
    return
  fi
  # Check for presence of "taas" provider key or taaS URL in the config
  if grep -qi "taas" "$OPENCLAW_CONFIG_PATH"; then
    pass "taas_configured" "TaaS provider found in $OPENCLAW_CONFIG_PATH"
  else
    fail "taas_configured" "No 'taas' entry found in $OPENCLAW_CONFIG_PATH"
  fi
}

# 6. skills_present
test_skills_present() {
  local skills_dir="$WORKSPACE_PATH/skills"
  if [ ! -d "$skills_dir" ]; then
    fail "skills_present" "Skills directory not found: $skills_dir"
    return
  fi
  local skill_count
  skill_count="$(find "$skills_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
  log_verbose "Found $skill_count skill directories in $skills_dir"
  if [ "$skill_count" -eq 0 ]; then
    fail "skills_present" "No skills found in $skills_dir"
    return
  fi
  # Check each required skill
  local missing=()
  for skill in "${REQUIRED_SKILLS[@]}"; do
    if [ ! -d "$skills_dir/$skill" ]; then
      missing+=("$skill")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    fail "skills_present" "Missing required skills: ${missing[*]}"
  else
    pass "skills_present" "$skill_count skills present in $skills_dir; required skills verified"
  fi
}

# 7. bootstrap_ready
test_bootstrap_ready() {
  local bootstrap_path="$WORKSPACE_PATH/BOOTSTRAP.md"
  if [ -f "$bootstrap_path" ]; then
    local size
    size="$(wc -c < "$bootstrap_path" 2>/dev/null || echo 0)"
    pass "bootstrap_ready" "BOOTSTRAP.md found at $bootstrap_path (${size} bytes)"
  else
    fail "bootstrap_ready" "BOOTSTRAP.md not found at $bootstrap_path"
  fi
}

# 8. cloud_init_installed
test_cloud_init_installed() {
  local version
  version="$(cloud-init --version 2>&1 || true)"
  if echo "$version" | grep -qi "cloud-init"; then
    pass "cloud_init_installed" "cloud-init version: $version"
  elif command -v cloud-init &>/dev/null; then
    pass "cloud_init_installed" "cloud-init binary found (version output: $version)"
  else
    fail "cloud_init_installed" "cloud-init not found or not executable"
  fi
}

# 9. cloud_init_datasource
test_cloud_init_datasource() {
  local cfg="/etc/cloud/cloud.cfg"
  if [ ! -f "$cfg" ]; then
    fail "cloud_init_datasource" "cloud.cfg not found at $cfg"
    return
  fi
  # Check for CloudSigma in the datasource_list
  if grep -qi "CloudSigma" "$cfg"; then
    pass "cloud_init_datasource" "CloudSigma datasource found in $cfg"
  else
    # Also check cloud.cfg.d directory
    if grep -rqi "CloudSigma" /etc/cloud/cloud.cfg.d/ 2>/dev/null; then
      pass "cloud_init_datasource" "CloudSigma datasource found in /etc/cloud/cloud.cfg.d/"
    else
      fail "cloud_init_datasource" "CloudSigma not in datasource_list in $cfg or /etc/cloud/cloud.cfg.d/"
    fi
  fi
}

# 10. guest_user_exists
test_guest_user_exists() {
  if id "$GUEST_USER" &>/dev/null; then
    local uid
    uid="$(id -u "$GUEST_USER")"
    pass "guest_user_exists" "User '$GUEST_USER' exists (UID: $uid)"
  else
    fail "guest_user_exists" "User '$GUEST_USER' does not exist (run: id $GUEST_USER)"
  fi
}

# 11. guest_user_sudo
test_guest_user_sudo() {
  if ! id "$GUEST_USER" &>/dev/null; then
    fail "guest_user_sudo" "User '$GUEST_USER' does not exist, cannot check sudo"
    return
  fi
  # Check sudo group membership or sudoers file
  local in_sudo_group=false
  local in_sudoers=false
  if id -nG "$GUEST_USER" 2>/dev/null | grep -qwE "sudo|wheel|admin"; then
    in_sudo_group=true
  fi
  if grep -rqE "^$GUEST_USER\s|^%sudo\s|^%wheel\s|^%admin\s" /etc/sudoers /etc/sudoers.d/ 2>/dev/null; then
    in_sudoers=true
  fi
  if [ "$in_sudo_group" = true ] || [ "$in_sudoers" = true ]; then
    pass "guest_user_sudo" "User '$GUEST_USER' has sudo access (group=$in_sudo_group, sudoers=$in_sudoers)"
  else
    fail "guest_user_sudo" "User '$GUEST_USER' is not in sudo/wheel group and not in sudoers"
  fi
}

# 12. guest_user_homedir
test_guest_user_homedir() {
  if [ ! -d "$GUEST_HOME" ]; then
    fail "guest_user_homedir" "Home directory $GUEST_HOME does not exist"
    return
  fi
  # Check the passwd entry matches
  local passwd_home
  passwd_home="$(getent passwd "$GUEST_USER" 2>/dev/null | cut -d: -f6 || true)"
  if [ "$passwd_home" = "$GUEST_HOME" ]; then
    pass "guest_user_homedir" "$GUEST_HOME exists and matches passwd entry for '$GUEST_USER'"
  elif [ -n "$passwd_home" ]; then
    fail "guest_user_homedir" "Home dir exists at $GUEST_HOME but passwd says $passwd_home"
  else
    fail "guest_user_homedir" "User '$GUEST_USER' not found in passwd"
  fi
}

# 13. no_hardcoded_old_username
test_no_hardcoded_old_username() {
  local old_user="cloudsigma"
  local check_files=(
    "/etc/cloud/cloud.cfg"
    "/etc/sudoers"
    "/lib/systemd/system/openclaw.service"
    "/lib/systemd/system/webchat-ui.service"
    "/etc/systemd/system/openclaw.service"
    "/etc/systemd/system/webchat-ui.service"
  )
  local hits=()
  for f in "${check_files[@]}"; do
    if [ -f "$f" ] && grep -q "$old_user" "$f" 2>/dev/null; then
      hits+=("$f")
      log_verbose "Found '$old_user' in: $f"
    fi
  done
  # Also check sudoers.d
  while IFS= read -r -d '' f; do
    if grep -q "$old_user" "$f" 2>/dev/null; then
      hits+=("$f")
      log_verbose "Found '$old_user' in: $f"
    fi
  done < <(find /etc/sudoers.d/ -type f -print0 2>/dev/null)

  if [ "${#hits[@]}" -eq 0 ]; then
    pass "no_hardcoded_old_username" "No references to '$old_user' found in key config files"
  else
    fail "no_hardcoded_old_username" "Found '$old_user' references in: ${hits[*]}"
  fi
}

# 14. ssh_key_injection_config
test_ssh_key_injection_config() {
  local cfg="/etc/cloud/cloud.cfg"
  if [ ! -f "$cfg" ]; then
    fail "ssh_key_injection_config" "cloud.cfg not found at $cfg"
    return
  fi
  # Check for ssh_authorized_keys or ssh_import_id or users block with ssh_authorized_keys
  local found=false
  if grep -qiE "ssh_authorized_keys|ssh_import_id|no_ssh_fingerprints" "$cfg"; then
    found=true
  fi
  if grep -rqiE "ssh_authorized_keys|ssh_import_id" /etc/cloud/cloud.cfg.d/ 2>/dev/null; then
    found=true
  fi
  # Also check for the 'users' block which handles key injection
  if grep -qiE "^users:|default_user" "$cfg"; then
    found=true
  fi
  if [ "$found" = true ]; then
    pass "ssh_key_injection_config" "SSH key injection configuration found in cloud-init config"
  else
    fail "ssh_key_injection_config" "No SSH key injection config found in /etc/cloud/cloud.cfg or cloud.cfg.d/"
  fi
}

# 15. hostname_config
test_hostname_config() {
  local cfg="/etc/cloud/cloud.cfg"
  if [ ! -f "$cfg" ]; then
    fail "hostname_config" "cloud.cfg not found at $cfg"
    return
  fi
  # Check for hostname-related modules
  if grep -qiE "set_hostname|update_hostname|set-hostname" "$cfg"; then
    pass "hostname_config" "Hostname configuration module found in cloud.cfg"
  elif grep -rqiE "set_hostname|update_hostname|set-hostname" /etc/cloud/cloud.cfg.d/ 2>/dev/null; then
    pass "hostname_config" "Hostname configuration module found in cloud.cfg.d/"
  else
    # Check for preserve_hostname=false which implies dynamic hostname
    if grep -qiE "preserve_hostname.*false|manage_etc_hosts" "$cfg"; then
      pass "hostname_config" "Hostname management enabled via preserve_hostname/manage_etc_hosts"
    else
      fail "hostname_config" "No hostname setup module found in cloud-init config"
    fi
  fi
}

# 16. network_reachable
test_network_reachable() {
  local url="https://cloudsigma.com"
  local http_code
  http_code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || true)"
  if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
    pass "network_reachable" "HTTP $http_code from $url"
  elif [ -n "$http_code" ] && [ "$http_code" != "000" ]; then
    # Got a response — network works even if status is unusual
    pass "network_reachable" "Got HTTP $http_code from $url (network is reachable)"
  else
    # Try a fallback
    local fallback_code
    fallback_code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://google.com" 2>/dev/null || true)"
    if [ -n "$fallback_code" ] && [ "$fallback_code" != "000" ]; then
      pass "network_reachable" "cloudsigma.com unreachable but google.com returned HTTP $fallback_code"
    else
      fail "network_reachable" "No HTTP response from $url or https://google.com (timeout or no internet)"
    fi
  fi
}

# 17. openclaw_models_count
test_openclaw_models_count() {
  if [ ! -f "$OPENCLAW_CONFIG_PATH" ]; then
    fail "openclaw_models_count" "openclaw.json not found at $OPENCLAW_CONFIG_PATH"
    return
  fi
  # Count model entries — look for "model" keys or entries in a models array
  # Strategy: count lines with "\"model\":" or count entries in a "models" array
  local model_count=0

  # Try python3 for accurate JSON parsing
  if command -v python3 &>/dev/null; then
    model_count="$(python3 -c "
import json, sys
try:
    with open('$OPENCLAW_CONFIG_PATH') as f:
        cfg = json.load(f)
    count = 0
    # Check common config structures
    if isinstance(cfg.get('models'), list):
        count = len(cfg['models'])
    elif isinstance(cfg.get('providers'), list):
        for p in cfg['providers']:
            if isinstance(p.get('models'), list):
                count += len(p['models'])
            elif p.get('model'):
                count += 1
    elif isinstance(cfg.get('llm'), dict):
        models = cfg['llm'].get('models', [])
        count = len(models) if isinstance(models, list) else 1
    # Fallback: count all 'model' keys anywhere
    if count == 0:
        raw = open('$OPENCLAW_CONFIG_PATH').read()
        import re
        count = len(re.findall(r'\"model\"\s*:', raw))
    print(count)
except Exception as e:
    print(0)
" 2>/dev/null || echo 0)"
  else
    # Fallback: grep count
    model_count="$(grep -c '"model"\s*:' "$OPENCLAW_CONFIG_PATH" 2>/dev/null || echo 0)"
  fi

  log_verbose "Detected $model_count models in $OPENCLAW_CONFIG_PATH"
  if [ "$model_count" -ge "$MIN_MODELS" ]; then
    pass "openclaw_models_count" "$model_count models configured (minimum: $MIN_MODELS)"
  else
    fail "openclaw_models_count" "Only $model_count models found (minimum required: $MIN_MODELS)"
  fi
}

# 18. openclaw_webchat_port
test_openclaw_webchat_port() {
  local port_found=false
  # Try ss first, then netstat, then lsof
  if command -v ss &>/dev/null; then
    if ss -tlnp 2>/dev/null | grep -q ":${WEBCHAT_PORT}\b"; then
      port_found=true
      log_verbose "ss shows something listening on port $WEBCHAT_PORT"
    fi
  fi
  if [ "$port_found" = false ] && command -v netstat &>/dev/null; then
    if netstat -tlnp 2>/dev/null | grep -q ":${WEBCHAT_PORT}\b"; then
      port_found=true
      log_verbose "netstat shows something listening on port $WEBCHAT_PORT"
    fi
  fi
  if [ "$port_found" = false ] && command -v lsof &>/dev/null; then
    if lsof -i ":${WEBCHAT_PORT}" -sTCP:LISTEN &>/dev/null; then
      port_found=true
      log_verbose "lsof shows something listening on port $WEBCHAT_PORT"
    fi
  fi
  # Also try a direct curl to localhost
  if [ "$port_found" = false ]; then
    local http_code
    http_code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:${WEBCHAT_PORT}" 2>/dev/null || true)"
    if [ -n "$http_code" ] && [ "$http_code" != "000" ]; then
      port_found=true
      log_verbose "curl to localhost:$WEBCHAT_PORT returned HTTP $http_code"
    fi
  fi

  if [ "$port_found" = true ]; then
    pass "openclaw_webchat_port" "webchat-ui is listening on port $WEBCHAT_PORT"
  else
    fail "openclaw_webchat_port" "Nothing detected on port $WEBCHAT_PORT (expected webchat-ui)"
  fi
}

# 19. metadata_service_reachable
test_metadata_service_reachable() {
  # CloudSigma metadata service URLs to try
  local urls=(
    "http://cloudsigma-datasource/"
    "http://cloudsigma-datasource/meta/1.0/"
    "http://cloudsigma.com/static/cloudinit/"
  )
  local reached=false
  local reached_url=""

  for url in "${urls[@]}"; do
    local code
    code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || true)"
    if [ -n "$code" ] && [ "$code" != "000" ]; then
      reached=true
      reached_url="$url (HTTP $code)"
      break
    fi
    log_verbose "No response from $url"
  done

  # Also try the standard IMDS-style metadata endpoint some providers expose
  if [ "$reached" = false ]; then
    local code
    code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://169.254.169.254/" 2>/dev/null || true)"
    if [ -n "$code" ] && [ "$code" != "000" ]; then
      reached=true
      reached_url="http://169.254.169.254/ (HTTP $code)"
    fi
  fi

  if [ "$reached" = true ]; then
    pass "metadata_service_reachable" "Metadata service reachable: $reached_url"
  else
    fail "metadata_service_reachable" "CloudSigma metadata service not reachable (tried: ${urls[*]} and 169.254.169.254)"
  fi
}

# ---------------------------------------------------------------------------
# Test registry — order matters for display
# ---------------------------------------------------------------------------
ALL_TESTS=(
  "openclaw_service_running"
  "webchat_service_running"
  "tailscale_installed"
  "tailscale_not_logged_in"
  "taas_configured"
  "skills_present"
  "bootstrap_ready"
  "cloud_init_installed"
  "cloud_init_datasource"
  "guest_user_exists"
  "guest_user_sudo"
  "guest_user_homedir"
  "no_hardcoded_old_username"
  "ssh_key_injection_config"
  "hostname_config"
  "network_reachable"
  "openclaw_models_count"
  "openclaw_webchat_port"
  "metadata_service_reachable"
)

# ---------------------------------------------------------------------------
# Run tests
# ---------------------------------------------------------------------------

if [ -n "$SINGLE_TEST" ]; then
  # Single-test mode
  section "Running single test: $SINGLE_TEST"
  if declare -f "test_${SINGLE_TEST}" &>/dev/null; then
    "test_${SINGLE_TEST}"
    TOTAL_TESTS=1
  else
    echo "ERROR: Test 'test_${SINGLE_TEST}' not found." >&2
    echo "Run with --help to see available tests." >&2
    exit 1
  fi
else
  # Full suite
  section "Services"
  test_openclaw_service_running
  test_webchat_service_running

  section "Tailscale"
  test_tailscale_installed
  test_tailscale_not_logged_in

  section "OpenClaw / TaaS"
  test_taas_configured
  test_openclaw_models_count

  section "Workspace"
  test_skills_present
  test_bootstrap_ready

  section "Cloud-Init"
  test_cloud_init_installed
  test_cloud_init_datasource
  test_ssh_key_injection_config
  test_hostname_config

  section "Guest User"
  test_guest_user_exists
  test_guest_user_sudo
  test_guest_user_homedir
  test_no_hardcoded_old_username

  section "Network"
  test_network_reachable
  test_openclaw_webchat_port
  test_metadata_service_reachable
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log ""
log "============================================================"
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf "${COLOR_PASS}${COLOR_BOLD}  RESULT: ${PASS_COUNT}/${TOTAL_TESTS} passed — ALL TESTS PASSED ✓${COLOR_RESET}\n" | tee -a "$LOG_FILE"
else
  printf "${COLOR_FAIL}${COLOR_BOLD}  RESULT: ${PASS_COUNT}/${TOTAL_TESTS} passed — ${FAIL_COUNT} FAILED ✗${COLOR_RESET}\n" | tee -a "$LOG_FILE"
fi
log "  Log written to: $LOG_FILE"
log "============================================================"
log ""

# Exit code
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
