#!/usr/bin/env bash
# =============================================================================
# CloudSigma Image Lifecycle - First Boot Validation Script
# =============================================================================
# Purpose:
#   Validates that a fresh VM created from a candidate image snapshot is actually
#   usable on first boot.
#
#   This script is intentionally focused on the highest-risk migration area:
#   cloud-init + CloudSigma cschpw first-boot scripts + SSH access.
#
#   Flow:
#   1. Create validation VM from snapshot/drive
#   2. Boot VM and wait for reachability
#   3. Verify expected guest user and SSH path
#   4. SSH in using validation key
#   5. Verify sudo access and basic first-boot conditions
#   6. Emit JSON summary and retain artifacts
#
# Instruction: first-boot-validation-v1
# Version: 0.1.0
# Status: draft
# Last-reviewed-by: Ellie (ai-proposed)
# Last-reviewed-date: 2026-04-16
#
# IMPORTANT:
#   This is scaffolding for the real first-boot validation path. It is designed
#   to be completed once Bela provides the exact production image flow and the
#   precise metadata / key-injection details available through CloudSigma.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$REPO_DIR/logs"
TIMESTAMP="$(date -u +%Y-%m-%d-%H%M%S)"
ISO_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LOG_FILE="$LOG_DIR/first-boot-validate-$TIMESTAMP.log"
SUMMARY_FILE="$LOG_DIR/first-boot-summary-$TIMESTAMP.json"
ARTIFACT_DIR="$LOG_DIR/first-boot-$TIMESTAMP"

mkdir -p "$LOG_DIR" "$ARTIFACT_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo "[$(date -u +%H:%M:%S)] $*"; }
err() { echo "[$(date -u +%H:%M:%S)] ERROR: $*" >&2; }
die() { err "$*"; emit_summary "FAILED"; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command missing: $1"; }

# -----------------------------------------------------------------------------
# Defaults / environment
# -----------------------------------------------------------------------------
CLOUDSIGMA_API_BASE="${CLOUDSIGMA_API_BASE:-https://next.cloudsigma.com/api/2.0}"
CLOUDSIGMA_API_USER="${CLOUDSIGMA_API_USER:-qa.global.email+api2@cloudsigma.com}"
CLOUDSIGMA_QA_PASSWORD="${CLOUDSIGMA_QA_PASSWORD:-}"

VALIDATION_SSH_KEY="${VALIDATION_SSH_KEY:-$HOME/.ssh/id_rsa}"
EXPECTED_USER="${EXPECTED_USER:-cloud}"
VALIDATION_VM_CPU="${VALIDATION_VM_CPU:-2000}"
VALIDATION_VM_MEM="${VALIDATION_VM_MEM:-2147483648}"
VM_START_TIMEOUT="${VM_START_TIMEOUT:-300}"
SSH_WAIT_TIMEOUT="${SSH_WAIT_TIMEOUT:-300}"
CLOUD_INIT_WAIT_TIMEOUT="${CLOUD_INIT_WAIT_TIMEOUT:-300}"
SSH_RETRY_INTERVAL="${SSH_RETRY_INTERVAL:-10}"

SNAPSHOT_UUID=""
SNAPSHOT_NAME=""
PLATFORM_VARIANT="${PLATFORM_VARIANT:-unknown}"
DRY_RUN=false

# State
VALIDATION_VM_UUID=""
VALIDATION_VM_IP=""
BOOT_OK=false
CLOUD_INIT_OK=false
DATASOURCE_OK=false
GUEST_USER_OK=false
SSH_KEY_INJECTION_OK=false
SSH_LOGIN_OK=false
SUDO_OK=false
HOSTNAME_OK=false
LEGACY_PATH_LEAK_DETECTED=false
RESULT_STATUS="STARTING"

# -----------------------------------------------------------------------------
# Usage
# -----------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage:
  bash scripts/first-boot-validate.sh --snapshot-uuid=<UUID> --snapshot-name=<NAME>
  bash scripts/first-boot-validate.sh --snapshot-uuid=<UUID> --expected-user=cloud --dry-run

Options:
  --snapshot-uuid=UUID     Snapshot/drive UUID to validate (required)
  --snapshot-name=NAME     Friendly snapshot name (optional)
  --expected-user=USER     Expected login user (default: cloud)
  --platform=NAME          Platform variant label (optional)
  --dry-run                Validate inputs and show intended flow only
  --help                   Show help

Environment:
  CLOUDSIGMA_QA_PASSWORD   Required
  VALIDATION_SSH_KEY       Private key for validation login
  EXPECTED_USER            Expected guest username
EOF
}

for arg in "$@"; do
  case "$arg" in
    --snapshot-uuid=*) SNAPSHOT_UUID="${arg#*=}" ;;
    --snapshot-name=*) SNAPSHOT_NAME="${arg#*=}" ;;
    --expected-user=*) EXPECTED_USER="${arg#*=}" ;;
    --platform=*) PLATFORM_VARIANT="${arg#*=}" ;;
    --dry-run) DRY_RUN=true ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

# -----------------------------------------------------------------------------
# Load .env if present
# -----------------------------------------------------------------------------
if [ -f "$HOME/.openclaw/.env" ]; then
  while IFS= read -r _env_line; do
    [[ "$_env_line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$_env_line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$_env_line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
      _env_key="${BASH_REMATCH[1]}"
      _env_val="${BASH_REMATCH[2]}"
      if [ -z "${!_env_key:-}" ]; then
        export "$_env_key=$_env_val"
      fi
    fi
  done < "$HOME/.openclaw/.env"
fi

CLOUDSIGMA_QA_PASSWORD="${CLOUDSIGMA_QA_PASSWORD:-}"

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------
require_cmd curl
require_cmd jq
require_cmd ssh
require_cmd scp
require_cmd python3

[ -n "$SNAPSHOT_UUID" ] || die "Missing required --snapshot-uuid"
[ -n "$CLOUDSIGMA_QA_PASSWORD" ] || die "Missing CLOUDSIGMA_QA_PASSWORD"
[ -f "$VALIDATION_SSH_KEY" ] || die "Validation SSH key not found: $VALIDATION_SSH_KEY"

emit_summary() {
  local status="${1:-$RESULT_STATUS}"
  jq -n \
    --arg status "$status" \
    --arg timestamp "$ISO_TS" \
    --arg snapshot_uuid "$SNAPSHOT_UUID" \
    --arg snapshot_name "$SNAPSHOT_NAME" \
    --arg platform_variant "$PLATFORM_VARIANT" \
    --arg expected_user "$EXPECTED_USER" \
    --arg validation_vm_uuid "$VALIDATION_VM_UUID" \
    --arg validation_vm_ip "$VALIDATION_VM_IP" \
    --arg log_file "$LOG_FILE" \
    --arg artifact_dir "$ARTIFACT_DIR" \
    --argjson boot_ok "$BOOT_OK" \
    --argjson cloud_init_ok "$CLOUD_INIT_OK" \
    --argjson datasource_ok "$DATASOURCE_OK" \
    --argjson guest_user_ok "$GUEST_USER_OK" \
    --argjson ssh_key_injection_ok "$SSH_KEY_INJECTION_OK" \
    --argjson ssh_login_ok "$SSH_LOGIN_OK" \
    --argjson sudo_ok "$SUDO_OK" \
    --argjson hostname_ok "$HOSTNAME_OK" \
    --argjson legacy_path_leak_detected "$LEGACY_PATH_LEAK_DETECTED" \
    '{
      status: $status,
      timestamp: $timestamp,
      snapshot_uuid: $snapshot_uuid,
      snapshot_name: $snapshot_name,
      platform_variant: $platform_variant,
      expected_user: $expected_user,
      validation_vm_uuid: $validation_vm_uuid,
      validation_vm_ip: $validation_vm_ip,
      checks: {
        boot_ok: $boot_ok,
        cloud_init_ok: $cloud_init_ok,
        datasource_ok: $datasource_ok,
        guest_user_ok: $guest_user_ok,
        ssh_key_injection_ok: $ssh_key_injection_ok,
        ssh_login_ok: $ssh_login_ok,
        sudo_ok: $sudo_ok,
        hostname_ok: $hostname_ok,
        legacy_path_leak_detected: $legacy_path_leak_detected
      },
      artifacts: {
        log_file: $log_file,
        artifact_dir: $artifact_dir
      }
    }' | tee "$SUMMARY_FILE"
}

api_curl() {
  local method="$1"; shift
  local endpoint="$1"; shift
  local data="${1:-}"
  local args=(
    --silent
    --fail-with-body
    --max-time 60
    -u "${CLOUDSIGMA_API_USER}:${CLOUDSIGMA_QA_PASSWORD}"
    -H "Content-Type: application/json"
    -X "$method"
    "${CLOUDSIGMA_API_BASE}${endpoint}"
  )
  [ -n "$data" ] && args+=(-d "$data")
  curl "${args[@]}"
}

api_get() { api_curl GET "$1"; }
api_post() { api_curl POST "$1" "${2:-{}}"; }

SSH_OPTS="-i ${VALIDATION_SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
remote_exec() {
  local cmd="$1"
  ssh $SSH_OPTS "${EXPECTED_USER}@${VALIDATION_VM_IP}" "$cmd"
}
remote_copy_back() {
  local remote_path="$1"
  local local_path="$2"
  scp -i "$VALIDATION_SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=15 \
    "${EXPECTED_USER}@${VALIDATION_VM_IP}:${remote_path}" "$local_path" >/dev/null 2>&1 || true
}

cleanup() {
  local exit_code=$?
  if [ -n "$VALIDATION_VM_UUID" ]; then
    log "Cleanup: stopping validation VM $VALIDATION_VM_UUID"
    api_post "/servers/${VALIDATION_VM_UUID}/action/" '{"action":"stop"}' >/dev/null 2>&1 || true
  fi
  [ -f "$SUMMARY_FILE" ] || emit_summary "$RESULT_STATUS" >/dev/null 2>&1 || true
  return $exit_code
}
trap cleanup EXIT

if [ "$DRY_RUN" = true ]; then
  RESULT_STATUS="DRY_RUN_OK"
  log "DRY RUN"
  log "Would validate snapshot $SNAPSHOT_UUID as expected user '$EXPECTED_USER'"
  log "Would create a fresh validation VM, wait for boot/cloud-init, SSH in, and verify sudo"
  emit_summary "$RESULT_STATUS"
  exit 0
fi

log "Starting first-boot validation"
log "Snapshot UUID: $SNAPSHOT_UUID"
log "Expected user: $EXPECTED_USER"
log "Platform variant: $PLATFORM_VARIANT"

# -----------------------------------------------------------------------------
# NOTE: The exact CloudSigma flow for creating a VM from a published snapshot/
# drive and injecting a test key may require adjustment once Bela provides the
# final production process details.
# -----------------------------------------------------------------------------

SERVER_PAYLOAD=$(cat <<EOF
{
  "name": "firstboot-validate-${TIMESTAMP}",
  "cpu": ${VALIDATION_VM_CPU},
  "mem": ${VALIDATION_VM_MEM},
  "drives": [
    {
      "device": "virtio",
      "dev_channel": "0:0",
      "action": "attach",
      "drive": {
        "uuid": "${SNAPSHOT_UUID}"
      }
    }
  ],
  "nics": [
    {
      "ip_v4_conf": { "conf": "dhcp" },
      "model": "virtio"
    }
  ]
}
EOF
)

log "Creating validation VM"
CREATE_RESPONSE=$(api_post "/servers/" "$SERVER_PAYLOAD")
VALIDATION_VM_UUID=$(echo "$CREATE_RESPONSE" | jq -r '.uuid // empty')
[ -n "$VALIDATION_VM_UUID" ] || die "Failed to create validation VM"

log "Validation VM UUID: $VALIDATION_VM_UUID"
log "Starting validation VM"
api_post "/servers/${VALIDATION_VM_UUID}/action/" '{"action":"start"}' >/dev/null

VM_START_AT=$(date +%s)
while true; do
  SERVER_INFO=$(api_get "/servers/${VALIDATION_VM_UUID}/")
  SERVER_STATUS=$(echo "$SERVER_INFO" | jq -r '.status // empty')
  log "VM status: $SERVER_STATUS"
  if [ "$SERVER_STATUS" = "running" ]; then
    BOOT_OK=true
    break
  fi
  if [ $(( $(date +%s) - VM_START_AT )) -ge $VM_START_TIMEOUT ]; then
    die "Validation VM failed to reach running state"
  fi
  sleep 10
done

VALIDATION_VM_IP=$(echo "$SERVER_INFO" | jq -r '.runtime.nics[0].ip_v4 // .nics[0].runtime.ip_v4 // empty')
[ -n "$VALIDATION_VM_IP" ] || die "Could not determine validation VM IP"
log "Validation VM IP: $VALIDATION_VM_IP"

log "Waiting for SSH"
SSH_START_AT=$(date +%s)
while true; do
  if ssh $SSH_OPTS "${EXPECTED_USER}@${VALIDATION_VM_IP}" "echo ready" >/dev/null 2>&1; then
    SSH_LOGIN_OK=true
    break
  fi
  if [ $(( $(date +%s) - SSH_START_AT )) -ge $SSH_WAIT_TIMEOUT ]; then
    err "SSH did not become available for expected user '$EXPECTED_USER'"
    SSH_LOGIN_OK=false
    break
  fi
  sleep $SSH_RETRY_INTERVAL
done

if [ "$SSH_LOGIN_OK" = true ]; then
  log "SSH login succeeded"

  log "Checking cloud-init status"
  if remote_exec "sudo cloud-init status --wait" >/dev/null 2>&1; then
    CLOUD_INIT_OK=true
  fi

  log "Checking CloudSigma datasource"
  if remote_exec "grep -R \"CloudSigma\" /etc/cloud /etc/cloud/cloud.cfg.d >/dev/null 2>&1"; then
    DATASOURCE_OK=true
  fi

  log "Checking guest user"
  if remote_exec "id ${EXPECTED_USER} >/dev/null 2>&1"; then
    GUEST_USER_OK=true
  fi

  log "Checking SSH key injection path"
  if remote_exec "test -f /home/${EXPECTED_USER}/.ssh/authorized_keys"; then
    SSH_KEY_INJECTION_OK=true
  fi

  log "Checking sudo access"
  if remote_exec "sudo -n true" >/dev/null 2>&1; then
    SUDO_OK=true
  fi

  log "Checking hostname"
  if remote_exec "hostnamectl status >/dev/null 2>&1 || hostname >/dev/null 2>&1"; then
    HOSTNAME_OK=true
  fi

  log "Checking for legacy cloudsigma path leakage in cschpw"
  if remote_exec "grep -R '/home/cloudsigma\| cloudsigma\b' /usr/bin/cschpw >/dev/null 2>&1"; then
    LEGACY_PATH_LEAK_DETECTED=true
  fi

  log "Collecting artifacts"
  remote_exec "sudo cp /var/log/cloud-init.log /tmp/cloud-init.log 2>/dev/null || true"
  remote_exec "sudo cp /var/log/cloud-init-output.log /tmp/cloud-init-output.log 2>/dev/null || true"
  remote_exec "sudo cp /etc/cloud/cloud.cfg /tmp/cloud.cfg 2>/dev/null || true"
  remote_exec "sudo tar -czf /tmp/cschpw.tar.gz /usr/bin/cschpw 2>/dev/null || true"
  remote_exec "id ${EXPECTED_USER} > /tmp/id.txt 2>/dev/null || true"
  remote_exec "ls -la /home/${EXPECTED_USER}/.ssh > /tmp/ssh-dir.txt 2>/dev/null || true"

  remote_copy_back "/tmp/cloud-init.log" "$ARTIFACT_DIR/cloud-init.log"
  remote_copy_back "/tmp/cloud-init-output.log" "$ARTIFACT_DIR/cloud-init-output.log"
  remote_copy_back "/tmp/cloud.cfg" "$ARTIFACT_DIR/cloud.cfg"
  remote_copy_back "/tmp/cschpw.tar.gz" "$ARTIFACT_DIR/cschpw.tar.gz"
  remote_copy_back "/tmp/id.txt" "$ARTIFACT_DIR/id.txt"
  remote_copy_back "/tmp/ssh-dir.txt" "$ARTIFACT_DIR/ssh-dir.txt"
else
  log "SSH login did not succeed; skipping remote checks"
fi

if [ "$BOOT_OK" = true ] && [ "$SSH_LOGIN_OK" = true ] && [ "$SUDO_OK" = true ] && [ "$GUEST_USER_OK" = true ]; then
  RESULT_STATUS="SUCCESS"
else
  RESULT_STATUS="FAILED"
fi

emit_summary "$RESULT_STATUS"
log "First-boot validation complete: $RESULT_STATUS"
exit 0
