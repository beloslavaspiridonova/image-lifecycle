#!/usr/bin/env bash
# =============================================================================
# CloudSigma Image Lifecycle - Build Script
# =============================================================================
# Purpose:
#   Automates the full build pipeline for a CloudSigma pre-installed VM image:
#   1. Clone a source library drive to a new build drive
#   2. Create a temporary build VM using that drive
#   3. Start the VM and wait for SSH availability
#   4. Run apt update/upgrade, update OpenClaw, verify services
#   5. Place BOOTSTRAP.md and run the test suite
#   6. On success: take a named staging snapshot
#   7. On failure: log the failure and exit non-zero
#   8. Clean up: stop VM (drive + snapshot kept for review)
#   9. Emit a structured JSON summary to stdout
#
# Instruction: build-pipeline-v1 (Phase 2)
# Version: 1.0.0
# Status: draft
# Last-reviewed-by: Ellie (ai-proposed)
# Last-reviewed-date: 2026-04-16
#
# Usage:
#   ./scripts/build.sh --source-drive=<UUID> --version=22.04
#   ./scripts/build.sh --source-drive=<UUID> --version=22.04 --dry-run
#   ./scripts/build.sh --help
#
# Environment Variables (read from ~/.openclaw/.env or shell env):
#   CLOUDSIGMA_API_USER     - API username (default: qa.global.email+api2@cloudsigma.com)
#   CLOUDSIGMA_QA_PASSWORD  - API password
#   CLOUDSIGMA_API_BASE     - API base URL (default: https://next.cloudsigma.com/api/2.0)
#   BUILD_SSH_KEY           - Path to SSH private key for VM access
#   BUILD_SSH_USER          - SSH username on the VM (default: cloud)
#   BUILD_VM_CPU            - VM CPU count (default: 2000 MHz)
#   BUILD_VM_MEM            - VM memory in bytes (default: 2147483648 = 2GB)
#   BUILD_VM_VNC_PASSWORD   - Optional VNC password for the build VM
#
# Exit codes:
#   0 = success (snapshot taken, tests passed)
#   1 = failure (tests failed, API error, or timeout)
# =============================================================================

set -euo pipefail

# =============================================================================
# SCRIPT METADATA
# =============================================================================
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="$REPO_ROOT/logs"
TESTS_DIR="$REPO_ROOT/tests"
BUILD_TIMESTAMP="$(date -u '+%Y-%m-%d-%H%M%S')"
BUILD_DATE="$(date -u '+%Y-%m-%d')"
LOG_FILE="$LOGS_DIR/build-${BUILD_TIMESTAMP}.log"

# =============================================================================
# DEFAULTS
# =============================================================================
CLOUDSIGMA_API_BASE="${CLOUDSIGMA_API_BASE:-https://next.cloudsigma.com/api/2.0}"
CLOUDSIGMA_API_USER="${CLOUDSIGMA_API_USER:-qa.global.email+api2@cloudsigma.com}"
CLOUDSIGMA_QA_PASSWORD="${CLOUDSIGMA_QA_PASSWORD:-}"

BUILD_SSH_KEY="${BUILD_SSH_KEY:-$HOME/.ssh/id_rsa}"
BUILD_SSH_USER="${BUILD_SSH_USER:-cloud}"
BUILD_VM_CPU="${BUILD_VM_CPU:-2000}"      # MHz
BUILD_VM_MEM="${BUILD_VM_MEM:-2147483648}" # 2GB in bytes
BUILD_VM_VNC_PASSWORD="${BUILD_VM_VNC_PASSWORD:-BuildVNC$(date +%s)}"

# Timeouts (seconds)
SSH_WAIT_TIMEOUT="${SSH_WAIT_TIMEOUT:-300}"      # 5 min for SSH to come up
VM_START_TIMEOUT="${VM_START_TIMEOUT:-120}"       # 2 min for VM to reach 'running' state
DRIVE_CLONE_TIMEOUT="${DRIVE_CLONE_TIMEOUT:-180}" # 3 min for drive clone
SSH_RETRY_INTERVAL="${SSH_RETRY_INTERVAL:-10}"    # Seconds between SSH retries

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
SOURCE_DRIVE_UUID=""
IMAGE_VERSION=""
DRY_RUN=false

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --source-drive=UUID   UUID of the source library drive to clone (required)
  --version=VERSION     Ubuntu version string, e.g. 22.04 (required)
  --dry-run             Validate inputs and show what would happen without making API calls
  --help                Show this help

Environment Variables:
  CLOUDSIGMA_QA_PASSWORD  API password (required)
  CLOUDSIGMA_API_USER     API username (default: qa.global.email+api2@cloudsigma.com)
  CLOUDSIGMA_API_BASE     API base URL (default: https://next.cloudsigma.com/api/2.0)
  BUILD_SSH_KEY           SSH private key path (default: ~/.ssh/id_rsa)
  BUILD_SSH_USER          SSH username on VM (default: cloud)
  BUILD_VM_CPU            CPU in MHz (default: 2000)
  BUILD_VM_MEM            Memory in bytes (default: 2147483648)

Examples:
  $0 --source-drive=12345678-1234-1234-1234-123456789abc --version=22.04
  $0 --source-drive=12345678-1234-1234-1234-123456789abc --version=22.04 --dry-run

Exit codes:
  0  All tests passed, staging snapshot created
  1  Tests failed, API error, or timeout

EOF
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    --source-drive=*)
      SOURCE_DRIVE_UUID="${arg#--source-drive=}"
      ;;
    --version=*)
      IMAGE_VERSION="${arg#--version=}"
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "ERROR: Unknown argument: $arg" >&2
      echo "Run with --help for usage." >&2
      exit 1
      ;;
  esac
done

# =============================================================================
# LOAD .ENV FILE (if present)
# =============================================================================
# We use a subprocess approach to safely parse KEY=VALUE pairs that may contain
# special characters (!, &, *, spaces, etc.) without eval-related issues.
if [ -f "$HOME/.openclaw/.env" ]; then
  while IFS= read -r _env_line; do
    # Skip blank lines and comments
    [[ "$_env_line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$_env_line" =~ ^[[:space:]]*# ]] && continue
    # Match KEY=VALUE pattern (KEY must be uppercase/underscore)
    if [[ "$_env_line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
      _env_key="${BASH_REMATCH[1]}"
      _env_val="${BASH_REMATCH[2]}"
      # Only set if not already set in environment
      if [ -z "${!_env_key:-}" ]; then
        export "$_env_key"="$_env_val"
      fi
    fi
  done < "$HOME/.openclaw/.env"
fi

# Refresh password from env (may have been loaded from .env)
CLOUDSIGMA_QA_PASSWORD="${CLOUDSIGMA_QA_PASSWORD:-}"

# =============================================================================
# LOGGING SETUP
# =============================================================================
mkdir -p "$LOGS_DIR"

# Tee all output to log file
exec > >(tee -a "$LOG_FILE") 2>&1

log() {
  echo "[$(date -u '+%H:%M:%S')] $*"
}

log_section() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $*"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

log_ok()   { echo "[$(date -u '+%H:%M:%S')] ✓  $*"; }
log_warn() { echo "[$(date -u '+%H:%M:%S')] ⚠  $*"; }
log_err()  { echo "[$(date -u '+%H:%M:%S')] ✗  $*" >&2; }

# =============================================================================
# INPUT VALIDATION
# =============================================================================
log_section "CloudSigma Image Build Pipeline v${SCRIPT_VERSION}"
log "Build timestamp: $BUILD_TIMESTAMP"
log "Log file: $LOG_FILE"
log "Dry-run: $DRY_RUN"

VALIDATION_ERRORS=0

if [ -z "$SOURCE_DRIVE_UUID" ]; then
  log_err "Missing required argument: --source-drive=UUID"
  VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

if [ -z "$IMAGE_VERSION" ]; then
  log_err "Missing required argument: --version=VERSION"
  VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

if [ -z "$CLOUDSIGMA_QA_PASSWORD" ]; then
  log_err "Missing required env variable: CLOUDSIGMA_QA_PASSWORD"
  VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

if [ ! -f "$BUILD_SSH_KEY" ]; then
  log_err "SSH key not found at: $BUILD_SSH_KEY (set BUILD_SSH_KEY env var)"
  VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

if ! command -v curl &>/dev/null; then
  log_err "curl is required but not found in PATH"
  VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

if ! command -v jq &>/dev/null; then
  log_err "jq is required but not found in PATH (apt install jq)"
  VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

if ! command -v ssh &>/dev/null; then
  log_err "ssh is required but not found in PATH"
  VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

if [ $VALIDATION_ERRORS -gt 0 ]; then
  log_err "Validation failed with $VALIDATION_ERRORS error(s). Aborting."
  exit 1
fi

# Derived values
SNAPSHOT_NAME="openclaw-ubuntu-${IMAGE_VERSION}-${BUILD_DATE}-staging"
BUILD_VM_NAME="build-openclaw-${IMAGE_VERSION}-${BUILD_TIMESTAMP}"
BUILD_DRIVE_NAME="build-drive-${IMAGE_VERSION}-${BUILD_TIMESTAMP}"

log "Source drive UUID:  $SOURCE_DRIVE_UUID"
log "Image version:      $IMAGE_VERSION"
log "Snapshot name:      $SNAPSHOT_NAME"
log "Build VM name:      $BUILD_VM_NAME"
log "API base:           $CLOUDSIGMA_API_BASE"
log "SSH key:            $BUILD_SSH_KEY"
log "SSH user:           $BUILD_SSH_USER"

# =============================================================================
# STATE TRACKING (for cleanup on failure)
# =============================================================================
BUILD_DRIVE_UUID=""
BUILD_SERVER_UUID=""
BUILD_SERVER_IP=""
BUILD_STATUS="STARTING"
SNAPSHOT_UUID=""

# Cleanup function — called on EXIT (success or failure)
cleanup() {
  local exit_code=$?

  log_section "Cleanup"

  # Stop the build VM if it's still running
  if [ -n "$BUILD_SERVER_UUID" ]; then
    log "Stopping build VM: $BUILD_SERVER_UUID"
    if [ "$DRY_RUN" = false ]; then
      api_post "/servers/${BUILD_SERVER_UUID}/action/" '{"action": "stop"}' || \
        log_warn "Could not stop VM (may already be stopped)"
      # Wait briefly for it to stop
      sleep 5
    else
      log "[dry-run] Would stop VM $BUILD_SERVER_UUID"
    fi
  fi

  # Note: We intentionally do NOT delete the drive or snapshot here.
  # They are kept for human review, even on failure.
  if [ -n "$BUILD_DRIVE_UUID" ]; then
    log "Build drive $BUILD_DRIVE_UUID retained for review (NOT deleted)"
  fi
  if [ -n "$SNAPSHOT_UUID" ]; then
    log "Staging snapshot $SNAPSHOT_UUID retained"
  fi

  if [ $exit_code -ne 0 ]; then
    log_err "Build FAILED (exit code: $exit_code). See log: $LOG_FILE"
    emit_json_summary "FAILED" "$exit_code"
  fi
}
trap cleanup EXIT

# =============================================================================
# API HELPER FUNCTIONS
# =============================================================================

# Base curl call to CloudSigma API
api_curl() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"

  local curl_args=(
    --silent
    --fail-with-body
    --max-time 60
    -u "${CLOUDSIGMA_API_USER}:${CLOUDSIGMA_QA_PASSWORD}"
    -H "Content-Type: application/json"
    -X "$method"
    "${CLOUDSIGMA_API_BASE}${endpoint}"
  )

  if [ -n "$data" ]; then
    curl_args+=(-d "$data")
  fi

  curl "${curl_args[@]}"
}

api_get() {
  local endpoint="$1"
  api_curl "GET" "$endpoint"
}

api_post() {
  local endpoint="$1"
  local data="${2:-{}}"
  api_curl "POST" "$endpoint" "$data"
}

api_delete() {
  local endpoint="$1"
  api_curl "DELETE" "$endpoint"
}

# =============================================================================
# DRY RUN MODE
# =============================================================================
if [ "$DRY_RUN" = true ]; then
  log_section "DRY RUN - Validation Only"
  log "All inputs valid. The following would happen:"
  echo ""
  echo "  1. Clone drive $SOURCE_DRIVE_UUID"
  echo "     → POST ${CLOUDSIGMA_API_BASE}/drives/${SOURCE_DRIVE_UUID}/action/"
  echo "       {\"action\": \"clone\", \"name\": \"${BUILD_DRIVE_NAME}\"}"
  echo ""
  echo "  2. Create VM '${BUILD_VM_NAME}'"
  echo "     → POST ${CLOUDSIGMA_API_BASE}/servers/"
  echo "       {cpu: ${BUILD_VM_CPU}, mem: ${BUILD_VM_MEM}, drives: [{drive: {uuid: <cloned>}}]}"
  echo ""
  echo "  3. Start VM and wait for SSH (${SSH_WAIT_TIMEOUT}s timeout)"
  echo ""
  echo "  4. SSH in as ${BUILD_SSH_USER} and run:"
  echo "     - apt update && apt upgrade -y"
  echo "     - npm install -g openclaw@latest"
  echo "     - systemctl restart openclaw webchat-ui"
  echo "     - Place BOOTSTRAP.md"
  echo "     - Run tests/test-suite.sh"
  echo ""
  echo "  5. On test success: POST /drives/<cloned>/action/ {action: clone, name: ${SNAPSHOT_NAME}}"
  echo ""
  echo "  6. Stop VM (drive + snapshot retained)"
  echo ""
  log_ok "Dry run complete. No API calls were made."
  BUILD_STATUS="DRY_RUN_OK"
  emit_json_summary() {
    echo ""
    echo '{"status": "DRY_RUN_OK", "snapshot_name": "'"$SNAPSHOT_NAME"'", "dry_run": true}'
  }
  emit_json_summary
  exit 0
fi

# =============================================================================
# STEP 1: CLONE THE SOURCE DRIVE
# =============================================================================
log_section "Step 1: Clone Source Drive"
log "Cloning source drive $SOURCE_DRIVE_UUID → $BUILD_DRIVE_NAME"

CLONE_RESPONSE=$(api_post "/drives/${SOURCE_DRIVE_UUID}/action/" \
  "{\"action\": \"clone\", \"name\": \"${BUILD_DRIVE_NAME}\"}")

log "Clone API response received"

# Extract the UUID of the new drive from the response
# CloudSigma clone returns {"action": "clone", "objects": [{"uuid": "..."}], ...}
BUILD_DRIVE_UUID=$(echo "$CLONE_RESPONSE" | jq -r '.objects[0].uuid // .uuid // empty')

if [ -z "$BUILD_DRIVE_UUID" ]; then
  log_err "Failed to extract cloned drive UUID from response:"
  echo "$CLONE_RESPONSE" | jq . || echo "$CLONE_RESPONSE"
  exit 1
fi

log_ok "Cloned drive UUID: $BUILD_DRIVE_UUID"

# Wait for the clone to finish (drive status must reach 'unmounted' or 'available')
log "Waiting for drive clone to complete (timeout: ${DRIVE_CLONE_TIMEOUT}s)..."
DRIVE_WAIT_START=$(date +%s)
while true; do
  DRIVE_STATUS=$(api_get "/drives/${BUILD_DRIVE_UUID}/" | jq -r '.status // empty')
  log "Drive status: $DRIVE_STATUS"

  if [ "$DRIVE_STATUS" = "unmounted" ] || [ "$DRIVE_STATUS" = "available" ]; then
    log_ok "Drive clone complete (status: $DRIVE_STATUS)"
    break
  fi

  DRIVE_ELAPSED=$(( $(date +%s) - DRIVE_WAIT_START ))
  if [ $DRIVE_ELAPSED -ge $DRIVE_CLONE_TIMEOUT ]; then
    log_err "Timeout waiting for drive clone after ${DRIVE_CLONE_TIMEOUT}s (status: $DRIVE_STATUS)"
    exit 1
  fi

  sleep 10
done

# =============================================================================
# STEP 2: CREATE BUILD VM
# =============================================================================
log_section "Step 2: Create Build VM"
log "Creating VM: $BUILD_VM_NAME"

# Build the server creation payload
# - 1 drive (our cloned drive) as boot device
# - 1 NIC with DHCP for public connectivity
# - VNC enabled for debugging access
SERVER_PAYLOAD=$(cat <<EOF
{
  "name": "${BUILD_VM_NAME}",
  "cpu": ${BUILD_VM_CPU},
  "mem": ${BUILD_VM_MEM},
  "vnc_password": "${BUILD_VM_VNC_PASSWORD}",
  "drives": [
    {
      "device": "virtio",
      "dev_channel": "0:0",
      "action": "attach",
      "drive": {
        "uuid": "${BUILD_DRIVE_UUID}"
      }
    }
  ],
  "nics": [
    {
      "ip_v4_conf": {
        "conf": "dhcp"
      },
      "model": "virtio"
    }
  ]
}
EOF
)

CREATE_RESPONSE=$(api_post "/servers/" "$SERVER_PAYLOAD")
BUILD_SERVER_UUID=$(echo "$CREATE_RESPONSE" | jq -r '.uuid // empty')

if [ -z "$BUILD_SERVER_UUID" ]; then
  log_err "Failed to create build VM. Response:"
  echo "$CREATE_RESPONSE" | jq . || echo "$CREATE_RESPONSE"
  exit 1
fi

log_ok "Build VM created: $BUILD_SERVER_UUID"

# =============================================================================
# STEP 3: START VM AND WAIT FOR SSH
# =============================================================================
log_section "Step 3: Start VM and Wait for SSH"
log "Starting VM $BUILD_SERVER_UUID..."

START_RESPONSE=$(api_post "/servers/${BUILD_SERVER_UUID}/action/" '{"action": "start"}')
log "Start command sent"

# Wait for VM to reach 'running' state
log "Waiting for VM to reach 'running' state (timeout: ${VM_START_TIMEOUT}s)..."
VM_START_WAIT=$(date +%s)
while true; do
  SERVER_INFO=$(api_get "/servers/${BUILD_SERVER_UUID}/")
  SERVER_STATUS=$(echo "$SERVER_INFO" | jq -r '.status // empty')
  log "VM status: $SERVER_STATUS"

  if [ "$SERVER_STATUS" = "running" ]; then
    log_ok "VM is running"
    break
  fi

  VM_ELAPSED=$(( $(date +%s) - VM_START_WAIT ))
  if [ $VM_ELAPSED -ge $VM_START_TIMEOUT ]; then
    log_err "Timeout waiting for VM to start after ${VM_START_TIMEOUT}s (status: $SERVER_STATUS)"
    exit 1
  fi

  sleep 10
done

# Extract the VM's public IP address
# CloudSigma server object has nics[].ip_v4_conf.ip.uuid — we need the actual IP
BUILD_SERVER_IP=$(echo "$SERVER_INFO" | \
  jq -r '.nics[0].ip_v4_conf.ip.uuid // .nics[0].runtime.ip_v4 // empty' 2>/dev/null || true)

# Fallback: try runtime data
if [ -z "$BUILD_SERVER_IP" ] || echo "$BUILD_SERVER_IP" | grep -q "^[0-9a-f-]\{36\}$"; then
  # Got a UUID instead of IP — fetch the IP resource
  IP_UUID="$BUILD_SERVER_IP"
  if [ -n "$IP_UUID" ] && [ "$IP_UUID" != "null" ]; then
    BUILD_SERVER_IP=$(api_get "/ips/${IP_UUID}/" | jq -r '.uuid // .address // empty' 2>/dev/null || true)
  fi
fi

# Another fallback: parse from runtime nics
if [ -z "$BUILD_SERVER_IP" ] || [ "$BUILD_SERVER_IP" = "null" ]; then
  BUILD_SERVER_IP=$(echo "$SERVER_INFO" | \
    jq -r '.runtime.nics[0].ip_v4 // .nics[0].runtime.ip_v4 // empty' 2>/dev/null || true)
fi

if [ -z "$BUILD_SERVER_IP" ] || [ "$BUILD_SERVER_IP" = "null" ]; then
  log_err "Could not determine build VM IP address. Server info:"
  echo "$SERVER_INFO" | jq '{uuid, status, nics}' || echo "$SERVER_INFO"
  exit 1
fi

log_ok "Build VM IP: $BUILD_SERVER_IP"

# Wait for SSH to become available
log "Waiting for SSH on ${BUILD_SERVER_IP}:22 (timeout: ${SSH_WAIT_TIMEOUT}s)..."
SSH_WAIT_START=$(date +%s)
SSH_OPTS="-i ${BUILD_SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
SSH_READY=false

while true; do
  if ssh $SSH_OPTS "${BUILD_SSH_USER}@${BUILD_SERVER_IP}" "echo ssh-ready" &>/dev/null 2>&1; then
    SSH_READY=true
    log_ok "SSH is available on ${BUILD_SERVER_IP}"
    break
  fi

  SSH_ELAPSED=$(( $(date +%s) - SSH_WAIT_START ))
  if [ $SSH_ELAPSED -ge $SSH_WAIT_TIMEOUT ]; then
    log_err "SSH timeout after ${SSH_WAIT_TIMEOUT}s. VM may still be booting or SSH key not set up."
    exit 1
  fi

  log "SSH not ready yet (${SSH_ELAPSED}s elapsed). Retrying in ${SSH_RETRY_INTERVAL}s..."
  sleep $SSH_RETRY_INTERVAL
done

# =============================================================================
# STEP 4: PROVISION THE VM
# =============================================================================
log_section "Step 4: Provision VM"

# Helper: run command on the VM via SSH
remote_exec() {
  local cmd="$1"
  local desc="${2:-$cmd}"
  log "Remote: $desc"
  # shellcheck disable=SC2086
  ssh $SSH_OPTS "${BUILD_SSH_USER}@${BUILD_SERVER_IP}" "$cmd"
}

# Helper: copy file to the VM
remote_copy() {
  local local_path="$1"
  local remote_path="$2"
  log "SCP: $local_path → ${BUILD_SERVER_IP}:${remote_path}"
  # shellcheck disable=SC2086
  scp -i "${BUILD_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    "$local_path" \
    "${BUILD_SSH_USER}@${BUILD_SERVER_IP}:${remote_path}"
}

# --- 4a. System update ---
log "Running apt update && apt upgrade..."
remote_exec "sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq" "apt update"
remote_exec "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq \
  -o Dpkg::Options::='--force-confdef' \
  -o Dpkg::Options::='--force-confold'" "apt upgrade"
log_ok "System packages updated"

# --- 4b. Update OpenClaw ---
log "Updating OpenClaw to latest..."
# Ensure npm/node are present first
if remote_exec "which npm" "check npm" &>/dev/null; then
  remote_exec "sudo npm install -g openclaw@latest 2>&1" "npm install -g openclaw@latest"
  log_ok "OpenClaw updated via npm"
else
  log_warn "npm not found; attempting to update OpenClaw via apt or existing install script..."
  # Try the bundled update mechanism if it exists
  remote_exec "sudo openclaw update 2>&1 || true" "openclaw update fallback" || true
fi

# Reload systemd after potential service file changes
remote_exec "sudo systemctl daemon-reload" "systemctl daemon-reload"

# --- 4c. Verify openclaw service ---
log "Verifying openclaw service..."
if remote_exec "sudo systemctl enable --now openclaw 2>&1 && systemctl is-active openclaw" \
    "enable+start openclaw"; then
  log_ok "openclaw service is active"
else
  log_err "openclaw service failed to start"
  BUILD_STATUS="OPENCLAW_SERVICE_FAILED"
  exit 1
fi

# --- 4d. Verify webchat-ui service ---
log "Verifying webchat-ui service..."
if remote_exec "sudo systemctl enable --now webchat-ui 2>&1 && systemctl is-active webchat-ui" \
    "enable+start webchat-ui"; then
  log_ok "webchat-ui service is active"
else
  log_err "webchat-ui service failed to start"
  BUILD_STATUS="WEBCHAT_SERVICE_FAILED"
  exit 1
fi

# --- 4e. Place BOOTSTRAP.md ---
log "Placing BOOTSTRAP.md..."
BOOTSTRAP_TEMPLATE="$SCRIPT_DIR/BOOTSTRAP.md.template"
BOOTSTRAP_DEST_DIR="/home/${BUILD_SSH_USER}/.openclaw/workspace"

if [ -f "$BOOTSTRAP_TEMPLATE" ]; then
  log "Copying BOOTSTRAP.md from template: $BOOTSTRAP_TEMPLATE"
  remote_copy "$BOOTSTRAP_TEMPLATE" "/tmp/BOOTSTRAP.md"
  remote_exec "sudo install -o ${BUILD_SSH_USER} -g ${BUILD_SSH_USER} -m 644 \
    /tmp/BOOTSTRAP.md ${BOOTSTRAP_DEST_DIR}/BOOTSTRAP.md" \
    "install BOOTSTRAP.md"
  log_ok "BOOTSTRAP.md placed from template"
else
  log_warn "No BOOTSTRAP.md.template found at $BOOTSTRAP_TEMPLATE"
  log "Creating a default BOOTSTRAP.md..."
  remote_exec "sudo tee ${BOOTSTRAP_DEST_DIR}/BOOTSTRAP.md > /dev/null <<'BSEOF'
# Welcome to OpenClaw

This is a fresh CloudSigma pre-installed image.

## First Boot

You are the AI assistant on this VM. Read this file, understand your environment,
then delete this file — you won't need it again.

## Your Environment

- CloudSigma VM (auto-provisioned)
- OpenClaw is installed and running as a systemd service
- Webchat UI is available on port 3000
- Tailscale is installed but NOT logged in — await operator configuration

## Next Steps

1. Wait for the operator to configure Tailscale (\`tailscale up --authkey=...\`)
2. Wait for the operator to configure \`~/.openclaw/.env\` with API keys
3. Begin assisting the operator

BSEOF" "write default BOOTSTRAP.md"
  remote_exec "sudo chown ${BUILD_SSH_USER}:${BUILD_SSH_USER} ${BOOTSTRAP_DEST_DIR}/BOOTSTRAP.md" \
    "chown BOOTSTRAP.md"
  log_ok "Default BOOTSTRAP.md placed"
fi

# =============================================================================
# STEP 5: RUN TEST SUITE
# =============================================================================
log_section "Step 5: Run Test Suite"

TEST_SUITE_LOCAL="$TESTS_DIR/test-suite.sh"
if [ ! -f "$TEST_SUITE_LOCAL" ]; then
  log_err "Test suite not found at: $TEST_SUITE_LOCAL"
  exit 1
fi

# Copy test suite to VM
remote_copy "$TEST_SUITE_LOCAL" "/tmp/test-suite.sh"
remote_exec "chmod +x /tmp/test-suite.sh" "chmod test-suite.sh"

# Run the test suite — capture exit code without aborting the build script
log "Executing test suite on VM..."
TESTS_REMOTE_LOG="/tmp/test-results-${BUILD_TIMESTAMP}.txt"
TESTS_PASSED=false

# Run tests; capture output; don't let pipefail kill us here
if remote_exec "sudo bash /tmp/test-suite.sh --verbose 2>&1 | tee ${TESTS_REMOTE_LOG}; \
    exit \${PIPESTATUS[0]}" "test-suite.sh"; then
  TESTS_PASSED=true
  log_ok "All tests PASSED"
else
  TEST_EXIT_CODE=$?
  log_err "Tests FAILED (exit code: $TEST_EXIT_CODE)"
fi

# Fetch the test results log back for local archival
TESTS_LOCAL_LOG="$LOGS_DIR/test-results-vm-${BUILD_TIMESTAMP}.txt"
# shellcheck disable=SC2086
scp -i "${BUILD_SSH_KEY}" \
  -o StrictHostKeyChecking=no \
  -o ConnectTimeout=15 \
  "${BUILD_SSH_USER}@${BUILD_SERVER_IP}:${TESTS_REMOTE_LOG}" \
  "$TESTS_LOCAL_LOG" 2>/dev/null || log_warn "Could not retrieve remote test log"
log "Test results saved to: $TESTS_LOCAL_LOG"

# =============================================================================
# STEP 6: SNAPSHOT (on success) OR FAIL (on failure)
# =============================================================================
log_section "Step 6: Snapshot / Result"

if [ "$TESTS_PASSED" = false ]; then
  BUILD_STATUS="TESTS_FAILED"
  log_err "Test suite failed. Skipping snapshot."
  log_err "Build VM will be stopped. Drive retained for debugging."
  log_err "Check test results at: $TESTS_LOCAL_LOG"
  exit 1
fi

log "Taking staging snapshot: $SNAPSHOT_NAME"
SNAPSHOT_RESPONSE=$(api_post "/drives/${BUILD_DRIVE_UUID}/action/" \
  "{\"action\": \"clone\", \"name\": \"${SNAPSHOT_NAME}\"}")

SNAPSHOT_UUID=$(echo "$SNAPSHOT_RESPONSE" | jq -r '.objects[0].uuid // .uuid // empty')

if [ -z "$SNAPSHOT_UUID" ] || [ "$SNAPSHOT_UUID" = "null" ]; then
  log_err "Failed to create snapshot. Response:"
  echo "$SNAPSHOT_RESPONSE" | jq . || echo "$SNAPSHOT_RESPONSE"
  BUILD_STATUS="SNAPSHOT_FAILED"
  exit 1
fi

log_ok "Staging snapshot created!"
log_ok "  Name: $SNAPSHOT_NAME"
log_ok "  UUID: $SNAPSHOT_UUID"
BUILD_STATUS="SUCCESS"

# =============================================================================
# STEP 7: STOP VM (cleanup is handled by trap, but we stop explicitly here)
# =============================================================================
log_section "Step 7: Stop Build VM"
log "Stopping build VM $BUILD_SERVER_UUID..."
api_post "/servers/${BUILD_SERVER_UUID}/action/" '{"action": "stop"}' || \
  log_warn "Stop command returned non-zero (VM may already be stopping)"
log_ok "Stop command sent. VM will be cleaned up."
log "NOTE: Build drive $BUILD_DRIVE_UUID and snapshot $SNAPSHOT_UUID are retained for review."

# =============================================================================
# STEP 8: JSON SUMMARY OUTPUT
# =============================================================================
emit_json_summary() {
  local status="$1"
  local exit_code="${2:-0}"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  BUILD SUMMARY (JSON)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  jq -n \
    --arg status "$status" \
    --arg build_timestamp "$BUILD_TIMESTAMP" \
    --arg image_version "$IMAGE_VERSION" \
    --arg source_drive "$SOURCE_DRIVE_UUID" \
    --arg build_drive "$BUILD_DRIVE_UUID" \
    --arg build_server "$BUILD_SERVER_UUID" \
    --arg build_server_ip "${BUILD_SERVER_IP:-}" \
    --arg snapshot_name "$SNAPSHOT_NAME" \
    --arg snapshot_uuid "${SNAPSHOT_UUID:-}" \
    --arg log_file "$LOG_FILE" \
    --argjson exit_code "$exit_code" \
    '{
      status: $status,
      build_timestamp: $build_timestamp,
      image_version: $image_version,
      source_drive_uuid: $source_drive,
      build_drive_uuid: $build_drive,
      build_server_uuid: $build_server,
      build_server_ip: $build_server_ip,
      snapshot_name: $snapshot_name,
      snapshot_uuid: $snapshot_uuid,
      log_file: $log_file,
      exit_code: $exit_code
    }'
}

emit_json_summary "$BUILD_STATUS" 0

log ""
log_ok "Build pipeline complete!"
log "Staging snapshot '$SNAPSHOT_NAME' is ready for human review."
log "Next step: Bela to review and promote from STAGING → PRODUCTION via MI."
log ""

exit 0
