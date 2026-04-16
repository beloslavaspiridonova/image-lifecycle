#!/usr/bin/env bash
# =============================================================================
# CloudSigma Image Lifecycle - Publish Script
# =============================================================================
# Purpose:
#   Tracks the publish lifecycle around the mandatory manual MI step.
#   This script does NOT bypass MI/2FA. Instead it:
#   1. Creates a STAGING publish request from a validated build snapshot
#   2. Records review-queue state for human approval
#   3. Marks a request as promoted after Bela completes the MI step manually
#   4. Optionally records cleanup/retention actions for superseded artifacts
#
# Instruction: publish-lifecycle-v1
# Version: 1.0.0
# Status: draft
# Last-reviewed-by: Ellie (ai-proposed)
# Last-reviewed-date: 2026-04-16
#
# Usage:
#   bash scripts/publish.sh stage --snapshot-uuid=<UUID> --snapshot-name=<NAME>
#   bash scripts/publish.sh promote --request-id=<ID> --mi-ref=<ticket-or-note>
#   bash scripts/publish.sh cleanup --request-id=<ID> --notes="Retained 30 days"
#   bash scripts/publish.sh list
#
# Notes:
#   - Review queue: queue/review-items.json
#   - Audit log:    audit/approval-log.jsonl
#   - Manual MI publish remains required in v1.0 because of 2FA.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
QUEUE_DIR="$REPO_DIR/queue"
AUDIT_DIR="$REPO_DIR/audit"
LOG_DIR="$REPO_DIR/logs"
QUEUE_FILE="$QUEUE_DIR/review-items.json"
AUDIT_FILE="$AUDIT_DIR/approval-log.jsonl"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LOG_TS="$(date -u +%Y-%m-%d-%H%M%S)"
LOG_FILE="$LOG_DIR/publish-$LOG_TS.log"

mkdir -p "$QUEUE_DIR" "$AUDIT_DIR" "$LOG_DIR"
[ -f "$QUEUE_FILE" ] || printf '{\n  "schema_version": "1.0",\n  "updated_at": "%s",\n  "items": []\n}\n' "$TIMESTAMP" > "$QUEUE_FILE"
[ -f "$AUDIT_FILE" ] || : > "$AUDIT_FILE"

log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }
die() { log "ERROR: $*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_cmd python3

COMMAND="${1:-}"
[ -n "$COMMAND" ] || die "Usage: publish.sh <stage|promote|cleanup|list> [options]"
shift || true

SNAPSHOT_UUID=""
SNAPSHOT_NAME=""
BUILD_LOG=""
BUILD_DRIVE_UUID=""
REQUEST_ID=""
MI_REF=""
NOTES=""
APPROVER="${APPROVER:-beloslava.spiridonova@cloudsigma.com}"
ACTOR="${ACTOR:-ellie-ai}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

for arg in "$@"; do
  case "$arg" in
    --snapshot-uuid=*) SNAPSHOT_UUID="${arg#*=}" ;;
    --snapshot-name=*) SNAPSHOT_NAME="${arg#*=}" ;;
    --build-log=*) BUILD_LOG="${arg#*=}" ;;
    --build-drive-uuid=*) BUILD_DRIVE_UUID="${arg#*=}" ;;
    --request-id=*) REQUEST_ID="${arg#*=}" ;;
    --mi-ref=*) MI_REF="${arg#*=}" ;;
    --notes=*) NOTES="${arg#*=}" ;;
    --approver=*) APPROVER="${arg#*=}" ;;
    --actor=*) ACTOR="${arg#*=}" ;;
    --retention-days=*) RETENTION_DAYS="${arg#*=}" ;;
    --help|-h)
      cat <<EOF
Usage:
  bash scripts/publish.sh stage --snapshot-uuid=<UUID> --snapshot-name=<NAME> [--build-log=PATH] [--build-drive-uuid=<UUID>]
  bash scripts/publish.sh promote --request-id=<ID> --mi-ref=<ticket-or-note> [--notes=TEXT]
  bash scripts/publish.sh cleanup --request-id=<ID> [--notes=TEXT] [--retention-days=30]
  bash scripts/publish.sh list

Commands:
  stage    Create a publish request in publish-pending state for human review
  promote  Mark a request as published after Bela completes MI manually
  cleanup  Mark superseded artifacts for retention/cleanup tracking
  list     Show queue items related to publish requests
EOF
      exit 0
      ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

random_id() {
  python3 - <<'PY'
import uuid
print(str(uuid.uuid4()))
PY
}

append_audit() {
  local event_type="$1"
  local object_id="$2"
  local extra_json="$3"
  python3 - <<PY >> "$AUDIT_FILE"
import json
base = {
  "timestamp": "$TIMESTAMP",
  "actor": "$ACTOR",
  "event_type": "$event_type",
  "object_type": "publish-request",
  "object_id": "$object_id"
}
extra = json.loads('''$extra_json''')
base.update(extra)
print(json.dumps(base, ensure_ascii=False))
PY
}

queue_update() {
  local mode="$1"
  local payload_json="$2"
  python3 - <<PY
import json
from pathlib import Path

queue_path = Path("$QUEUE_FILE")
data = json.loads(queue_path.read_text())
items = data.setdefault("items", [])
payload = json.loads('''$payload_json''')
mode = "$mode"

if mode == "append":
    items.append(payload)
elif mode == "replace":
    rid = payload["id"]
    replaced = False
    for i, item in enumerate(items):
        if item.get("id") == rid:
            items[i] = payload
            replaced = True
            break
    if not replaced:
        raise SystemExit(f"request id not found: {rid}")
else:
    raise SystemExit(f"unknown mode: {mode}")

data["updated_at"] = "$TIMESTAMP"
queue_path.write_text(json.dumps(data, indent=2) + "\n")
PY
}

queue_get() {
  local rid="$1"
  python3 - <<PY
import json, sys
with open("$QUEUE_FILE") as f:
    data = json.load(f)
for item in data.get("items", []):
    if item.get("id") == "$rid":
        print(json.dumps(item))
        sys.exit(0)
sys.exit(1)
PY
}

case "$COMMAND" in
  stage)
    [ -n "$SNAPSHOT_UUID" ] || die "stage requires --snapshot-uuid"
    [ -n "$SNAPSHOT_NAME" ] || die "stage requires --snapshot-name"

    REQUEST_ID="publish-$(random_id)"
    log "Creating publish request: $REQUEST_ID"
    log "Snapshot: $SNAPSHOT_NAME ($SNAPSHOT_UUID)"

    ITEM_JSON=$(python3 - <<PY
import json
item = {
  "id": "$REQUEST_ID",
  "type": "publish-request",
  "title": "Promote validated staging snapshot to production",
  "status": "publish-pending",
  "priority": "high",
  "risk_level": "high",
  "created_at": "$TIMESTAMP",
  "updated_at": "$TIMESTAMP",
  "proposed_by": "$ACTOR",
  "reviewer": "$APPROVER",
  "requires_manual_mi": True,
  "mi_state": "pending",
  "target_stage": "STAGING",
  "next_stage": "PRODUCTION",
  "snapshot": {
    "uuid": "$SNAPSHOT_UUID",
    "name": "$SNAPSHOT_NAME"
  },
  "build_artifacts": {
    "build_log": "$BUILD_LOG",
    "build_drive_uuid": "$BUILD_DRIVE_UUID"
  },
  "validation_required": [
    "human-review",
    "mi-manual-publish",
    "post-publish-region-distribution"
  ],
  "approval": {
    "approved_by": None,
    "approved_at": None,
    "reason": None
  },
  "notes": "$NOTES"
}
print(json.dumps(item))
PY
)

    queue_update append "$ITEM_JSON"
    append_audit "publish-request-created" "$REQUEST_ID" "{\"status\": \"publish-pending\", \"snapshot_uuid\": \"$SNAPSHOT_UUID\", \"snapshot_name\": \"$SNAPSHOT_NAME\"}"

    log "Publish request created and queued for review"
    echo
    python3 - <<PY
import json
print(json.dumps({
  "status": "publish-pending",
  "request_id": "$REQUEST_ID",
  "snapshot_uuid": "$SNAPSHOT_UUID",
  "snapshot_name": "$SNAPSHOT_NAME",
  "reviewer": "$APPROVER",
  "mi_state": "pending",
  "log_file": "$LOG_FILE"
}, indent=2))
PY
    ;;

  promote)
    [ -n "$REQUEST_ID" ] || die "promote requires --request-id"
    [ -n "$MI_REF" ] || die "promote requires --mi-ref"

    ITEM_JSON="$(queue_get "$REQUEST_ID")" || die "Request not found: $REQUEST_ID"

    UPDATED_JSON=$(python3 - <<PY
import json
item = json.loads('''$ITEM_JSON''')
item["status"] = "published"
item["updated_at"] = "$TIMESTAMP"
item["mi_state"] = "completed"
item["mi_ref"] = "$MI_REF"
item["approval"] = {
  "approved_by": "$APPROVER",
  "approved_at": "$TIMESTAMP",
  "reason": "Manual MI publish completed"
}
existing_notes = item.get("notes", "")
extra = "$NOTES"
if extra:
    item["notes"] = (existing_notes + "\n" + extra).strip()
print(json.dumps(item))
PY
)

    queue_update replace "$UPDATED_JSON"
    append_audit "publish-request-promoted" "$REQUEST_ID" "{\"status\": \"published\", \"mi_ref\": \"$MI_REF\", \"approved_by\": \"$APPROVER\"}"

    log "Publish request marked as published"
    echo
    python3 - <<PY
import json
print(json.dumps({
  "status": "published",
  "request_id": "$REQUEST_ID",
  "mi_ref": "$MI_REF",
  "approved_by": "$APPROVER",
  "log_file": "$LOG_FILE"
}, indent=2))
PY
    ;;

  cleanup)
    [ -n "$REQUEST_ID" ] || die "cleanup requires --request-id"

    ITEM_JSON="$(queue_get "$REQUEST_ID")" || die "Request not found: $REQUEST_ID"

    UPDATED_JSON=$(python3 - <<PY
import json
item = json.loads('''$ITEM_JSON''')
item["updated_at"] = "$TIMESTAMP"
cleanup = item.get("cleanup", {})
cleanup.update({
  "status": "planned",
  "retention_days": int("$RETENTION_DAYS"),
  "notes": "$NOTES",
  "recorded_at": "$TIMESTAMP"
})
item["cleanup"] = cleanup
print(json.dumps(item))
PY
)

    queue_update replace "$UPDATED_JSON"
    append_audit "publish-request-cleanup-recorded" "$REQUEST_ID" "{\"retention_days\": $RETENTION_DAYS, \"notes\": $(python3 - <<PY
import json
print(json.dumps("$NOTES"))
PY
)}"

    log "Cleanup/retention record added"
    echo
    python3 - <<PY
import json
print(json.dumps({
  "status": "cleanup-recorded",
  "request_id": "$REQUEST_ID",
  "retention_days": int("$RETENTION_DAYS"),
  "log_file": "$LOG_FILE"
}, indent=2))
PY
    ;;

  list)
    python3 - <<PY
import json
with open("$QUEUE_FILE") as f:
    data = json.load(f)
items = [i for i in data.get("items", []) if i.get("type") == "publish-request"]
print(json.dumps(items, indent=2))
PY
    ;;

  *)
    die "Unknown command: $COMMAND"
    ;;
esac
