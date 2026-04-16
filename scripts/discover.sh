#!/usr/bin/env bash
# =============================================================================
# CloudSigma Image Lifecycle - Discovery Script
# Checks upstream vendors for new versions and creates version candidates.
#
# Usage:
#   bash scripts/discover.sh --check          # Dry run - report only
#   bash scripts/discover.sh --update         # Update current-versions.json
#   bash scripts/discover.sh --auto           # Auto-create candidates for patches
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
VENDORS_DIR="$REPO_DIR/vendors"
LOG_DIR="$REPO_DIR/logs"
TIMESTAMP="$(date -u +%Y-%m-%d-%H%M%S)"
LOG_FILE="$LOG_DIR/discover-$TIMESTAMP.log"

MODE="check"
for arg in "$@"; do
  case $arg in
    --check)  MODE="check" ;;
    --update) MODE="update" ;;
    --auto)   MODE="auto" ;;
  esac
done

mkdir -p "$LOG_DIR"
log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }

log "========================================"
log " CloudSigma Discovery - Mode: $MODE"
log "========================================"

# Load current versions
CURRENT_FILE="$VENDORS_DIR/current-versions.json"
CANDIDATES_FILE="$VENDORS_DIR/version-candidates.json"
REJECTED_FILE="$VENDORS_DIR/rejected-versions.json"

[ ! -f "$CURRENT_FILE" ]    && echo '{}' > "$CURRENT_FILE"
[ ! -f "$CANDIDATES_FILE" ] && echo '[]' > "$CANDIDATES_FILE"
[ ! -f "$REJECTED_FILE" ]   && echo '[]' > "$REJECTED_FILE"

# -------------------------------------------------------
# Ubuntu discovery
# -------------------------------------------------------
discover_ubuntu() {
  local family="$1"; local supported_versions="$2"
  log "Checking Ubuntu upstream..."

  for ver in $supported_versions; do
    local codename
    case $ver in
      22.04) codename="jammy" ;;
      24.04) codename="noble" ;;
      *)     codename="unknown" ;;
    esac

    log "  Checking Ubuntu $ver ($codename)..."

    # Fetch latest release info from Ubuntu cloud images
    local release_url="https://cloud-images.ubuntu.com/releases/$codename/release/"
    local latest_info
    latest_info=$(curl -s --max-time 10 "$release_url" 2>/dev/null | head -5 || echo "")

    if [ -z "$latest_info" ]; then
      log "  WARNING: Could not fetch release info for Ubuntu $ver"
      continue
    fi

    # Extract latest serial/version from release info
    local latest_serial
    latest_serial=$(echo "$latest_info" | grep -o '[0-9]\{8\}' | sort -u | tail -1 || echo "unknown")
    log "  Latest serial: $latest_serial"

    # Get current known serial
    local current_serial
    current_serial=$(python3 -c "
import json
d=json.load(open('$CURRENT_FILE'))
print(d.get('ubuntu', {}).get('$ver', {}).get('serial', 'none'))
" 2>/dev/null || echo "none")
    log "  Current serial: $current_serial"

    # Compare
    if [ "$latest_serial" = "$current_serial" ]; then
      log "  Ubuntu $ver: UP TO DATE (serial $current_serial)"
      continue
    fi

    log "  Ubuntu $ver: NEW VERSION AVAILABLE ($current_serial -> $latest_serial)"

    # Classify
    local classification="new_patch"
    local is_rejected
    is_rejected=$(python3 -c "
import json
rejected=json.load(open('$REJECTED_FILE'))
print('yes' if 'ubuntu-$ver-$latest_serial' in rejected else 'no')
" 2>/dev/null || echo "no")

    if [ "$is_rejected" = "yes" ]; then
      log "  Skipping - in rejected list"
      continue
    fi

    # Add candidate
    python3 - <<PY
import json, datetime

candidates = json.load(open('$CANDIDATES_FILE'))
new_candidate = {
    "id": "ubuntu-$ver-$latest_serial",
    "vendor": "ubuntu",
    "family": "ubuntu-lts",
    "version": "$ver",
    "serial": "$latest_serial",
    "classification": "$classification",
    "discovered_at": datetime.datetime.utcnow().isoformat() + "Z",
    "status": "proposed",
    "intake_mode": "automatic",
    "approved_by": None,
    "notes": "Auto-discovered by discover.sh"
}

# Don't add duplicates
ids = [c['id'] for c in candidates]
if new_candidate['id'] not in ids:
    candidates.append(new_candidate)
    json.dump(candidates, open('$CANDIDATES_FILE', 'w'), indent=2)
    print(f"  Added candidate: {new_candidate['id']}")
else:
    print(f"  Candidate already exists: {new_candidate['id']}")
PY

    # Update current-versions.json if --update or --auto
    if [ "$MODE" = "update" ] || [ "$MODE" = "auto" ]; then
      python3 - <<PY
import json, datetime
d = {}
try:
    d = json.load(open('$CURRENT_FILE'))
except: pass
d.setdefault('ubuntu', {}).setdefault('$ver', {})['serial'] = '$latest_serial'
d['ubuntu']['$ver']['checked_at'] = datetime.datetime.utcnow().isoformat() + 'Z'
json.dump(d, open('$CURRENT_FILE', 'w'), indent=2)
print("  Updated current-versions.json")
PY
    fi
  done
}

# Read vendors.json and run discovery per vendor
python3 - <<PY
import json, subprocess, sys

vendors = json.load(open('$VENDORS_DIR/vendors.json'))['vendors']
for v in vendors:
    name = v['name']
    versions = ' '.join(v.get('supported_versions', []))
    print(f"Processing vendor: {name}")
PY

# Run Ubuntu discovery
discover_ubuntu "ubuntu-lts" "22.04 24.04"

log ""
log "========================================"
log " Discovery complete"
log " Candidates file: $CANDIDATES_FILE"
log " Log: $LOG_FILE"
log "========================================"

# Print candidates summary
python3 -c "
import json
candidates = json.load(open('$CANDIDATES_FILE'))
proposed = [c for c in candidates if c['status'] == 'proposed']
print(f'Proposed candidates: {len(proposed)}')
for c in proposed:
    print(f'  - {c[\"id\"]} ({c[\"classification\"]})')
if not proposed:
    print('  No new candidates.')
"
