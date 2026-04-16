#!/usr/bin/env bash
# =============================================================================
# CloudSigma Image Lifecycle - Distribution Script
# Distributes an approved library drive to all 5 CloudSigma regions.
#
# Usage:
#   bash scripts/distribute.sh --drive=<UUID>
#   bash scripts/distribute.sh --drive=<UUID> --regions=ZRH,FRA
#   bash scripts/distribute.sh --drive=<UUID> --dry-run
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$REPO_DIR/logs"
TIMESTAMP="$(date -u +%Y-%m-%d-%H%M%S)"
LOG_FILE="$LOG_DIR/distribute-$TIMESTAMP.log"
DRY_RUN=false
DRIVE_UUID=""
TARGET_REGIONS=""

[ -f ~/.openclaw/.env ] && source ~/.openclaw/.env

CS_USERNAME="${CS_USERNAME:-qa.global.email+api2@cloudsigma.com}"
CS_PASSWORD="${CS_PASSWORD:-${CLOUDSIGMA_QA_PASSWORD:-}}"

for arg in "$@"; do
  case $arg in
    --drive=*)   DRIVE_UUID="${arg#*=}" ;;
    --regions=*) TARGET_REGIONS="${arg#*=}" ;;
    --dry-run)   DRY_RUN=true ;;
  esac
done

mkdir -p "$LOG_DIR"
log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }
die() { log "ERROR: $*"; exit 1; }

[ -z "$DRIVE_UUID" ] && die "Required: --drive=<UUID>"

# Load regions config
REGIONS_FILE="$SCRIPT_DIR/regions.json"

log "========================================"
log " CloudSigma Distribution"
log " Drive: $DRIVE_UUID"
log " Regions: ${TARGET_REGIONS:-ALL}"
log " Dry run: $DRY_RUN"
log "========================================"

# API helper per region
cs_api_region() {
  local api_url="$1"; local method="$2"; local path="$3"; local data="${4:-}"
  if [ -n "$data" ]; then
    curl -s -X "$method" -u "$CS_USERNAME:$CS_PASSWORD" \
      -H "Content-Type: application/json" -d "$data" "${api_url}${path}"
  else
    curl -s -X "$method" -u "$CS_USERNAME:$CS_PASSWORD" \
      -H "Content-Type: application/json" "${api_url}${path}"
  fi
}

# Distribute to a single region
distribute_to_region() {
  local region_name="$1"; local api_url="$2"
  log ""
  log "--- Distributing to $region_name ($api_url) ---"

  if $DRY_RUN; then
    log "[DRY RUN] Would remote-clone drive $DRIVE_UUID to $region_name"
    echo "success"
    return
  fi

  # Use remote snapshots API to transfer drive
  local resp
  resp=$(cs_api_region "$api_url" POST "/drives/$DRIVE_UUID/action/?format=json" \
    '{"action":"clone","name":"'"openclaw-$(date -u +%Y-%m-%d)-$region_name"'"}' 2>/dev/null || echo '{"error":"api_call_failed"}')

  local status
  status=$(echo "$resp" | python3 -c "
import json,sys
d=json.load(sys.stdin)
if 'error' in d: print('failed: ' + str(d['error']))
elif d.get('result') == 'success' or 'uuid' in d: print('success')
else: print('unknown: ' + json.dumps(d)[:100])
" 2>/dev/null || echo "failed: parse_error")

  log "  $region_name result: $status"
  echo "$status"
}

# Read regions from config
python3 - <<PY
import json

regions_file = '$REGIONS_FILE'
target = '$TARGET_REGIONS'

regions = json.load(open(regions_file))['regions']
if target:
    target_list = [r.strip().upper() for r in target.split(',')]
    regions = [r for r in regions if r['name'].upper() in target_list]

# Sort: ZRH first, then parallel group (FRA, SJC, MNL), then TYO
order = {'ZRH': 0, 'FRA': 1, 'SJC': 1, 'MNL': 1, 'TYO': 2}
regions.sort(key=lambda r: order.get(r['name'].upper(), 99))

for r in regions:
    print(f"{r['name']}|{r['api_url']}|{r['priority']}")
PY

RESULTS=()
FAILED_REGIONS=()

# Read regions and distribute
while IFS='|' read -r name api_url priority; do
  result=$(distribute_to_region "$name" "$api_url")
  if [[ "$result" == "success" ]]; then
    RESULTS+=("$name:success")
    log "  $name: SUCCESS"
  else
    RESULTS+=("$name:failed")
    FAILED_REGIONS+=("$name")
    log "  $name: FAILED ($result) - retrying once..."
    sleep 5
    result2=$(distribute_to_region "$name" "$api_url" || echo "failed")
    if [[ "$result2" == "success" ]]; then
      log "  $name: RETRY SUCCESS"
      FAILED_REGIONS=("${FAILED_REGIONS[@]/$name}")
    else
      log "  $name: RETRY ALSO FAILED - marking as failed, continuing"
    fi
  fi
done < <(python3 - <<PY
import json
regions_file = '$REGIONS_FILE'
target = '$TARGET_REGIONS'
regions = json.load(open(regions_file))['regions']
if target:
    target_list = [r.strip().upper() for r in target.split(',')]
    regions = [r for r in regions if r['name'].upper() in target_list]
order = {'ZRH': 0, 'FRA': 1, 'SJC': 1, 'MNL': 1, 'TYO': 2}
regions.sort(key=lambda r: order.get(r['name'].upper(), 99))
for r in regions:
    print(f"{r['name']}|{r['api_url']}|{r['priority']}")
PY
)

log ""
log "========================================"
log " DISTRIBUTION SUMMARY"
for r in "${RESULTS[@]}"; do
  log "  $r"
done
if [ ${#FAILED_REGIONS[@]} -eq 0 ]; then
  log " STATUS: ALL REGIONS SUCCESS"
else
  log " STATUS: PARTIAL - failed regions: ${FAILED_REGIONS[*]}"
fi
log " Log: $LOG_FILE"
log "========================================"

[ ${#FAILED_REGIONS[@]} -gt 0 ] && exit 1
exit 0
