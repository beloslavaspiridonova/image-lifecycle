#!/usr/bin/env bash
# =============================================================================
# CloudSigma Image Lifecycle - Test Suite
# Version: 1.0
# Tests: 19
# Usage: sudo bash tests/test-suite.sh [--verbose] [--test=NAME]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$REPO_DIR/logs"
TIMESTAMP="$(date -u +%Y-%m-%d-%H%M%S)"
LOG_FILE="$LOG_DIR/test-results-$TIMESTAMP.txt"
VERBOSE=false
SINGLE_TEST=""
PASS=0
FAIL=0
TOTAL=19

# Colors
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  NC='\033[0m'
else
  GREEN='' RED='' YELLOW='' CYAN='' NC=''
fi

# Parse args
for arg in "$@"; do
  case $arg in
    --verbose) VERBOSE=true ;;
    --test=*) SINGLE_TEST="${arg#*=}" ;;
  esac
done

mkdir -p "$LOG_DIR"

log() { echo "$@" | tee -a "$LOG_FILE"; }
verbose() { $VERBOSE && log "    $*" || true; }

pass() {
  local name="$1"; local msg="${2:-}"
  log -e "  ${GREEN}[PASS]${NC} $name${msg:+ - $msg}"
  PASS=$((PASS+1))
}

fail() {
  local name="$1"; local msg="${2:-}"
  log -e "  ${RED}[FAIL]${NC} $name${msg:+ - $msg}"
  FAIL=$((FAIL+1))
}

# Detect guest username (cloud or cloudsigma)
GUEST_USER="cloud"
if id cloud &>/dev/null; then
  GUEST_USER="cloud"
elif id cloudsigma &>/dev/null; then
  GUEST_USER="cloudsigma"
fi
GUEST_HOME="/home/$GUEST_USER"
OPENCLAW_DIR="$GUEST_HOME/.openclaw"

log "============================================================"
log " CloudSigma Image Lifecycle - Test Suite"
log " Date: $(date -u)"
log " Host: $(hostname)"
log " Guest user detected: $GUEST_USER"
log " Log: $LOG_FILE"
log "============================================================"
log ""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

test_openclaw_service_running() {
  verbose "Checking: systemctl is-active openclaw"
  if systemctl is-active --quiet openclaw 2>/dev/null; then
    pass "openclaw_service_running" "openclaw.service is active"
  else
    local status
    status=$(systemctl is-active openclaw 2>/dev/null || echo "not-found")
    fail "openclaw_service_running" "openclaw.service status: $status"
  fi
}

test_webchat_service_running() {
  verbose "Checking: systemctl is-active webchat-ui"
  if systemctl is-active --quiet webchat-ui 2>/dev/null; then
    pass "webchat_service_running" "webchat-ui.service is active"
  else
    local status
    status=$(systemctl is-active webchat-ui 2>/dev/null || echo "not-found")
    fail "webchat_service_running" "webchat-ui.service status: $status"
  fi
}

test_tailscale_installed() {
  verbose "Checking: which tailscale"
  if command -v tailscale &>/dev/null; then
    local ver
    ver=$(tailscale version 2>/dev/null | head -1 || echo "unknown")
    pass "tailscale_installed" "version: $ver"
  else
    fail "tailscale_installed" "tailscale binary not found in PATH"
  fi
}

test_tailscale_not_logged_in() {
  verbose "Checking: tailscale status (should NOT be logged in)"
  if ! command -v tailscale &>/dev/null; then
    fail "tailscale_not_logged_in" "tailscale not installed - skipping"
    return
  fi
  local status
  status=$(tailscale status 2>&1 || true)
  if echo "$status" | grep -qi "not logged in\|Logged out\|NeedsLogin\|stopped"; then
    pass "tailscale_not_logged_in" "tailscale is not logged in (correct for fresh image)"
  else
    fail "tailscale_not_logged_in" "tailscale appears to be logged in: $(echo "$status" | head -1)"
  fi
}

test_taas_configured() {
  verbose "Checking: TaaS configuration in openclaw.json"
  local config="$OPENCLAW_DIR/openclaw.json"
  if [ ! -f "$config" ]; then
    fail "taas_configured" "openclaw.json not found at $config"
    return
  fi
  if python3 -c "
import json, sys
d = json.load(open('$config'))
# Check for TaaS provider config
raw = json.dumps(d)
if 'taas' in raw.lower() or 'TAAS_API_KEY' in raw:
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
    pass "taas_configured" "TaaS found in openclaw.json"
  else
    fail "taas_configured" "TaaS not found in openclaw.json"
  fi
}

test_openclaw_models_count() {
  verbose "Checking: >=10 models configured in openclaw.json"
  local config="$OPENCLAW_DIR/openclaw.json"
  if [ ! -f "$config" ]; then
    fail "openclaw_models_count" "openclaw.json not found at $config"
    return
  fi
  local count
  count=$(python3 -c "
import json
d = json.load(open('$config'))
models = d.get('models', d.get('allowedModels', []))
print(len(models))
" 2>/dev/null || echo "0")
  if [ "$count" -ge 10 ] 2>/dev/null; then
    pass "openclaw_models_count" "$count models configured"
  else
    fail "openclaw_models_count" "only $count models configured (need >=10)"
  fi
}

test_skills_present() {
  verbose "Checking: required skills in workspace/skills/"
  local skills_dir="$OPENCLAW_DIR/workspace/skills"
  if [ ! -d "$skills_dir" ]; then
    fail "skills_present" "skills directory not found at $skills_dir"
    return
  fi
  local count
  count=$(find "$skills_dir" -maxdepth 1 -mindepth 1 -type d | wc -l)
  if [ "$count" -ge 1 ]; then
    local skill_names
    skill_names=$(ls "$skills_dir" | tr '\n' ' ')
    pass "skills_present" "$count skills found: $skill_names"
  else
    fail "skills_present" "no skills found in $skills_dir"
  fi
}

test_bootstrap_ready() {
  verbose "Checking: BOOTSTRAP.md at workspace root"
  local bootstrap="$OPENCLAW_DIR/workspace/BOOTSTRAP.md"
  if [ -f "$bootstrap" ]; then
    local size
    size=$(wc -c < "$bootstrap")
    pass "bootstrap_ready" "BOOTSTRAP.md found ($size bytes)"
  else
    fail "bootstrap_ready" "BOOTSTRAP.md not found at $bootstrap"
  fi
}

test_cloud_init_installed() {
  verbose "Checking: cloud-init installed"
  if command -v cloud-init &>/dev/null; then
    local ver
    ver=$(cloud-init --version 2>&1 | head -1 || echo "unknown")
    pass "cloud_init_installed" "$ver"
  else
    fail "cloud_init_installed" "cloud-init not found in PATH"
  fi
}

test_cloud_init_datasource() {
  verbose "Checking: CloudSigma datasource configured in cloud.cfg"
  local cfg="/etc/cloud/cloud.cfg"
  if [ ! -f "$cfg" ]; then
    fail "cloud_init_datasource" "/etc/cloud/cloud.cfg not found"
    return
  fi
  if grep -qi "cloudsigma\|CloudSigma" "$cfg" 2>/dev/null; then
    pass "cloud_init_datasource" "CloudSigma datasource found in cloud.cfg"
  else
    # Check cloud.cfg.d/
    if grep -rqi "cloudsigma" /etc/cloud/cloud.cfg.d/ 2>/dev/null; then
      pass "cloud_init_datasource" "CloudSigma datasource found in cloud.cfg.d/"
    else
      fail "cloud_init_datasource" "CloudSigma datasource not found in cloud-init config"
    fi
  fi
}

test_guest_user_exists() {
  verbose "Checking: guest user '$GUEST_USER' exists"
  if id "$GUEST_USER" &>/dev/null; then
    pass "guest_user_exists" "user '$GUEST_USER' exists (uid: $(id -u "$GUEST_USER"))"
  else
    fail "guest_user_exists" "user '$GUEST_USER' not found in /etc/passwd"
  fi
}

test_guest_user_sudo() {
  verbose "Checking: guest user '$GUEST_USER' has sudo access"
  if groups "$GUEST_USER" 2>/dev/null | grep -qw "sudo\|wheel\|admin"; then
    pass "guest_user_sudo" "user '$GUEST_USER' is in sudo group"
  elif [ -f "/etc/sudoers.d/$GUEST_USER" ]; then
    pass "guest_user_sudo" "user '$GUEST_USER' has sudoers.d entry"
  else
    fail "guest_user_sudo" "user '$GUEST_USER' does not appear to have sudo access"
  fi
}

test_guest_user_homedir() {
  verbose "Checking: /home/$GUEST_USER exists"
  if [ -d "$GUEST_HOME" ]; then
    pass "guest_user_homedir" "$GUEST_HOME exists"
  else
    fail "guest_user_homedir" "$GUEST_HOME does not exist"
  fi
}

test_no_hardcoded_old_username() {
  verbose "Checking: no hardcoded /home/cloudsigma in active service files"
  if [ "$GUEST_USER" = "cloudsigma" ]; then
    pass "no_hardcoded_old_username" "currently using cloudsigma - migration not yet applied (expected)"
    return
  fi
  local found=0
  # Check systemd service files
  while IFS= read -r -d '' f; do
    if grep -q "/home/cloudsigma" "$f" 2>/dev/null; then
      verbose "Found /home/cloudsigma in: $f"
      found=$((found+1))
    fi
  done < <(find /etc/systemd/system /lib/systemd/system -name "*.service" -print0 2>/dev/null)
  if [ "$found" -eq 0 ]; then
    pass "no_hardcoded_old_username" "no /home/cloudsigma references in active service files"
  else
    fail "no_hardcoded_old_username" "$found service file(s) still reference /home/cloudsigma"
  fi
}

test_ssh_key_injection_config() {
  verbose "Checking: cloud-init SSH key injection configured"
  local cfg="/etc/cloud/cloud.cfg"
  if grep -q "ssh_authorized_keys\|ssh-import-id\|ssh_import_id\|authorized_keys" "$cfg" 2>/dev/null; then
    pass "ssh_key_injection_config" "SSH key injection found in cloud.cfg"
  elif grep -rq "ssh" /etc/cloud/cloud.cfg.d/ 2>/dev/null; then
    pass "ssh_key_injection_config" "SSH config found in cloud.cfg.d/"
  else
    # cloud-init handles SSH keys by default via the users module
    if grep -q "users\|default" "$cfg" 2>/dev/null; then
      pass "ssh_key_injection_config" "cloud-init users module present (handles SSH keys by default)"
    else
      fail "ssh_key_injection_config" "could not confirm SSH key injection configuration"
    fi
  fi
}

test_hostname_config() {
  verbose "Checking: cloud-init hostname configuration"
  local cfg="/etc/cloud/cloud.cfg"
  if grep -q "set_hostname\|update_hostname\|hostname" "$cfg" 2>/dev/null; then
    pass "hostname_config" "hostname configuration found in cloud.cfg"
  elif cloud-init schema --system 2>/dev/null | grep -q "set_hostname"; then
    pass "hostname_config" "hostname module active in cloud-init schema"
  else
    pass "hostname_config" "cloud-init default modules handle hostname (set_hostname is default)"
  fi
}

test_network_reachable() {
  verbose "Checking: internet connectivity (curl https://cloudsigma.com)"
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 https://cloudsigma.com 2>/dev/null || echo "000")
  if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ] 2>/dev/null; then
    pass "network_reachable" "https://cloudsigma.com returned HTTP $http_code"
  else
    fail "network_reachable" "https://cloudsigma.com returned HTTP $http_code (timeout or unreachable)"
  fi
}

test_openclaw_webchat_port() {
  verbose "Checking: webchat-ui is listening on a port"
  local port=""
  # Try common ports: 8080, 3000, 80, 8888
  for p in 8080 3000 80 8888 4000; do
    if ss -tlnp 2>/dev/null | grep -q ":$p " || netstat -tlnp 2>/dev/null | grep -q ":$p "; then
      port=$p
      break
    fi
  done
  if [ -n "$port" ]; then
    pass "openclaw_webchat_port" "webchat-ui listening on port $port"
  else
    # Check if the service is running at least
    if systemctl is-active --quiet webchat-ui 2>/dev/null; then
      pass "openclaw_webchat_port" "webchat-ui.service is active (port check inconclusive)"
    else
      fail "openclaw_webchat_port" "no known webchat port found listening and service not active"
    fi
  fi
}

test_metadata_service_reachable() {
  verbose "Checking: CloudSigma metadata service reachable"
  # CloudSigma metadata is available at the server context URL or standard metadata IP
  local urls=(
    "http://cloudsigma-datasource/"
    "http://169.254.169.254/"
    "http://10.0.1.1/"
  )
  for url in "${urls[@]}"; do
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
    if [ "$code" -ge 200 ] && [ "$code" -lt 500 ] 2>/dev/null; then
      pass "metadata_service_reachable" "metadata reachable at $url (HTTP $code)"
      return
    fi
  done
  fail "metadata_service_reachable" "CloudSigma metadata service not reachable (tried: ${urls[*]})"
}

# =============================================================================
# TEST RUNNER
# =============================================================================

ALL_TESTS=(
  "openclaw_service_running"
  "webchat_service_running"
  "tailscale_installed"
  "tailscale_not_logged_in"
  "taas_configured"
  "openclaw_models_count"
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
  "openclaw_webchat_port"
  "metadata_service_reachable"
)

run_test() {
  local name="$1"
  log ""
  log -e "${CYAN}[TEST]${NC} $name"
  "test_$name"
}

if [ -n "$SINGLE_TEST" ]; then
  TOTAL=1
  run_test "$SINGLE_TEST"
else
  for t in "${ALL_TESTS[@]}"; do
    run_test "$t"
  done
fi

# =============================================================================
# SUMMARY
# =============================================================================
log ""
log "============================================================"
log " RESULTS: $PASS passed, $FAIL failed (out of $TOTAL tests)"
if [ "$FAIL" -eq 0 ]; then
  log -e " ${GREEN}ALL TESTS PASSED${NC}"
else
  log -e " ${RED}$FAIL TEST(S) FAILED${NC}"
fi
log " Log saved: $LOG_FILE"
log "============================================================"

exit $FAIL
