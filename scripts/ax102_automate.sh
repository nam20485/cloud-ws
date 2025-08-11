#!/usr/bin/env bash
set -euo pipefail

# AX102 End-to-End Automation Wrapper (alpha)
# Goal: one command to provision a Hetzner AX102 dedicated server, build RAID/LVM, install Ubuntu, run Ansible roles.
# Status: MVP in-progress – includes Robot API rescue/reset, auto IP discovery, key propagation, verification, minimal reporting & resume mode.
#
# High-Level Flow (start):
#  1. Validate env + dependencies (curl, ssh, scp, optional jq, ansible)
#  2. (Optional) Trigger rescue mode enable + hardware reset via Robot API (ROBOT_USER / ROBOT_PASSWORD / ROBOT_SERVER_ID)
#  3. Auto-discover IP if not provided (Robot API)
#  4. Wait for (rescue) SSH
#  5. Resume shortcut: if provision marker present and not --force, skip to report (RESUME-SKIPPED)
#  6. Push & run provisioning script (BIOS/UEFI)
#  7. Reboot, wait for installed OS SSH
#  8. Ensure authorized key present (pubkey propagation)
#  9. Run post-install verification script -> capture result
# 10. Run Ansible (unless suppressed)
# 11. Collect versions / metadata and write JSON report
#
# Destroy path is largely manual for dedicated – placeholder prints guidance.
#
# Usage examples:
#   ./scripts/ax102_automate.sh start --host 203.0.113.42 --variant uefi --ansible-play ansible/raid_setup.yml \
#       --host-name ax102-demo --root-size 120G --swap-size 16G
#
#   ./scripts/ax102_automate.sh start --host 203.0.113.42 --variant bios --full-workstation \
#       --extra-ansible "-e migrate_root=true"
#
# Required (at least one of): --host <ip> (if you already have the server) OR Robot API vars to discover IP later (TODO)

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# Defaults
VARIANT="uefi"              # uefi|bios
HOST_IP=""
HOST_NAME="ax102-host"
ROOT_SIZE="100G"
SWAP_SIZE="8G"
ANSIBLE_PLAY="ansible/raid_setup.yml"  # or ubuntu-cinnamon/workstation.yml
FULL_WORKSTATION=false
EXTRA_ANSIBLE=""
SSH_USER="root"             # Rescue + initial install user
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
PUBKEY_PATH=""               # Optional explicit public key
SSH_PORT=22
WAIT_TIMEOUT=900
POLL_INTERVAL=5
PROVISION_ENV_VARS=()

# Runtime / reporting
START_EPOCH=$(date +%s)
START_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
RUN_ID=$(date -u +%Y%m%dT%H%M%S)
RUNS_DIR="$REPO_ROOT/runs"
RUN_DIR="$RUNS_DIR/$RUN_ID"
STATUS="IN_PROGRESS"
VERIFY_STATUS="UNKNOWN"
REPORT_JSON=""
FORCE_REPROVISION=false
RERUN_ANSIBLE=false
SKIPPED_REASON=""

# Robot API placeholders (export before running if you want automated rescue reset)
ROBOT_USER="${ROBOT_USER:-}"
ROBOT_PASSWORD="${ROBOT_PASSWORD:-}"
ROBOT_SERVER_ID="${ROBOT_SERVER_ID:-}"   # Numeric server ID in Robot panel

log() { printf "[%s] %s\n" "$(date +'%F %T')" "$*" >&2; }
fatal() {
  log "FATAL: $*"
  STATUS="FAIL"
  SKIPPED_REASON="$*"
  write_json_report || true
  exit 1
}

require_bin() { command -v "$1" >/dev/null 2>&1 || fatal "Missing required binary: $1"; }

usage() {
  cat <<EOF
AX102 Automation Wrapper

Commands:
  start   Provision or configure the dedicated server end-to-end.
  destroy Placeholder helper (prints manual teardown guidance).

Key Options (after 'start'):
  --host <ip>                 Existing server public IP (rescue or installed)
  --variant <uefi|bios>       Provisioning script variant (default: uefi)
  --host-name <name>          Target hostname inside installed OS
  --root-size <size>          Root LV size (LVM) (default: 100G)
  --swap-size <size|0>        Swap LV size (default: 8G; 0 disables)
  --full-workstation          Use workstation playbook instead of minimal raid_setup
  --ansible-play <path>       Override Ansible play (default raid_setup.yml)
  --extra-ansible "<args>"    Extra args passed to ansible-playbook
  --ssh-key <path>            SSH private key for root/admin
  --pubkey <path>             Public key to ensure in installed OS (default: infer from --ssh-key + .pub)
  --timeout <seconds>         SSH wait timeout (default 900)
  --force                     Force full re-provision even if marker present
  --rerun-ansible             Run Ansible even when resume skip occurs
  --no-ansible                Skip Ansible phase (provision base only)
  --dry-run                   Parse and show plan only
  -h|--help                   This help

Environment (optional):
  ROBOT_USER / ROBOT_PASSWORD / ROBOT_SERVER_ID   For rescue enable & reset & IP discovery

Examples:
  ROBOT_USER=foo ROBOT_PASSWORD=bar ROBOT_SERVER_ID=12345 \
    ./scripts/ax102_automate.sh start --host 203.0.113.42 --variant uefi --full-workstation

EOF
}

CMD=""
NO_ANSIBLE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    start|destroy) CMD=$1; shift ;;
    --host) HOST_IP=$2; shift 2 ;;
    --variant) VARIANT=$2; shift 2 ;;
    --host-name) HOST_NAME=$2; shift 2 ;;
    --root-size) ROOT_SIZE=$2; shift 2 ;;
    --swap-size) SWAP_SIZE=$2; shift 2 ;;
    --full-workstation) FULL_WORKSTATION=true; ANSIBLE_PLAY="ubuntu-cinnamon/workstation.yml"; shift ;;
    --ansible-play) ANSIBLE_PLAY=$2; shift 2 ;;
    --extra-ansible) EXTRA_ANSIBLE=$2; shift 2 ;;
  --ssh-key) SSH_KEY=$2; shift 2 ;;
  --pubkey) PUBKEY_PATH=$2; shift 2 ;;
    --timeout) WAIT_TIMEOUT=$2; shift 2 ;;
  --force) FORCE_REPROVISION=true; shift ;;
  --rerun-ansible) RERUN_ANSIBLE=true; shift ;;
    --no-ansible) NO_ANSIBLE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fatal "Unknown arg: $1" ;;
  esac
done

[[ -n "$CMD" ]] || { usage; exit 1; }

PROVISION_ENV_VARS+=("HOSTNAME=$HOST_NAME")
PROVISION_ENV_VARS+=("ROOT_LV_SIZE=$ROOT_SIZE")
PROVISION_ENV_VARS+=("SWAP_LV_SIZE=$SWAP_SIZE")

plan_summary() {
  cat <<EOT
Plan:
  Command:          $CMD
  Host IP:          ${HOST_IP:-<unset>}
  Variant:          $VARIANT
  Hostname:         $HOST_NAME
  Root LV Size:     $ROOT_SIZE
  Swap LV Size:     $SWAP_SIZE
  Ansible Play:     $ANSIBLE_PLAY
  Run Ansible:      $([[ $NO_ANSIBLE == false ]] && echo yes || echo no)
  Full Workstation: $FULL_WORKSTATION
  Extra Ansible:    ${EXTRA_ANSIBLE:-<none>}
  SSH Key:          $SSH_KEY
  Timeout (s):      $WAIT_TIMEOUT
  Robot API Used:   $([[ -n "$ROBOT_USER" && -n "$ROBOT_PASSWORD" && -n "$ROBOT_SERVER_ID" ]] && echo yes || echo no)
  Force Reprovision:$FORCE_REPROVISION
  Resume Ansible:   $RERUN_ANSIBLE
  Pubkey Path:      ${PUBKEY_PATH:-<auto>}
EOT
}

require_host() { [[ -n "$HOST_IP" ]] || fatal "Unable to determine host IP (provide --host or Robot API vars)."; }

ensure_run_dir() {
  mkdir -p "$RUN_DIR"
  # Start combined logging
  if [[ -z "${COMBINED_LOG_STARTED:-}" ]]; then
    export COMBINED_LOG_STARTED=1
    exec > >(tee -a "$RUN_DIR/provision.log") 2>&1
    log "Run directory: $RUN_DIR"
  fi
}

robot_api_call() {
  local method=$1 path=$2 data=${3:-}
  [[ -n "$ROBOT_USER" && -n "$ROBOT_PASSWORD" ]] || return 1
  local base="https://robot-ws.your-server.de"
  local curl_args=(-sS -u "$ROBOT_USER:$ROBOT_PASSWORD" -X "$method" -H 'Accept: application/json')
  if [[ -n "$data" ]]; then
    curl_args+=( -H 'Content-Type: application/x-www-form-urlencoded' --data "$data" )
  fi
  curl "${curl_args[@]}" "$base$path"
}

robot_get_ip() {
  [[ -n "$ROBOT_SERVER_ID" ]] || return 1
  local resp
  if ! resp=$(robot_api_call GET "/server/$ROBOT_SERVER_ID" 2>/dev/null); then
    log "Robot API: failed to fetch server details"; return 1
  fi
  if command -v jq >/dev/null 2>&1; then
    echo "$resp" | jq -r '.server.server_ip // .server.ip // empty'
  else
    echo "$resp" | grep -E '"server_ip"' | head -n1 | sed -E 's/.*"server_ip" *: *"([0-9\.]+)".*/\1/'
  fi
}

wait_for_ssh() {
  local ip=$1; local timeout=$2; local start=$(date +%s)
  log "Waiting for SSH on $ip (timeout ${timeout}s)..."
  while true; do
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -i "$SSH_KEY" ${SSH_USER}@${ip} 'echo ok' 2>/dev/null | grep -q ok; then
      log "SSH is up on $ip"; return 0
    fi
    local now=$(date +%s)
    if (( now - start > timeout )); then
      fatal "Timed out waiting for SSH on $ip"
    fi
    sleep $POLL_INTERVAL
  done
}

push_and_run_provision_script() {
  local ip=$1
  local variant_script
  case "$VARIANT" in
    uefi) variant_script="robot_provision_simple_uefi.sh" ;;
    bios) variant_script="robot_provision_simple.sh" ;;
    *) fatal "Unsupported variant: $VARIANT" ;;
  esac
  local src="$REPO_ROOT/robot/$variant_script"
  [[ -f "$src" ]] || fatal "Missing provisioning script $src"
  log "Uploading $variant_script to $ip:/root/..."
  scp -i "$SSH_KEY" -q "$src" root@${ip}:~/ || fatal "SCP failed"
  local export_prefix=""
  for kv in "${PROVISION_ENV_VARS[@]}"; do
    export_prefix+="$kv "
  done
  log "Executing remote provisioning script (this will take a while)..."
  ssh -i "$SSH_KEY" root@${ip} "set -euxo pipefail; $export_prefix bash $variant_script" || fatal "Remote provisioning failed"
}

run_ansible() {
  local ip=$1
  require_bin ansible-playbook || true
  local inv_file=$(mktemp)
  echo "[raid_server]" > "$inv_file"
  echo "$ip ansible_user=root" >> "$inv_file"
  log "Running Ansible play $ANSIBLE_PLAY against $ip"
  (cd "$REPO_ROOT" && ansible-playbook -i "$inv_file" "$ANSIBLE_PLAY" -vv $EXTRA_ANSIBLE)
  rm -f "$inv_file"
}

robot_enable_rescue_and_reset() {
  if [[ -z "$ROBOT_USER" || -z "$ROBOT_PASSWORD" || -z "$ROBOT_SERVER_ID" ]]; then
    log "Robot creds or server ID missing – skipping rescue/reset."
    return 0
  fi
  log "Enabling Linux rescue via Robot API for server $ROBOT_SERVER_ID"
  local resp
  resp=$(robot_api_call POST "/server/$ROBOT_SERVER_ID/rescue" "os=linux&arch=64&authorized_key=$(urlencode_pubkey)" || true)
  if [[ -z "$resp" ]]; then log "Rescue enable call returned empty response"; fi
  log "Triggering hardware reset"
  robot_api_call POST "/server/$ROBOT_SERVER_ID/reset" "type=hw"
}

urlencode_pubkey() {
  local pk
  pk=$(determine_pubkey_content | tr -d '\n') || return 0
  # rudimentary url encode space + plus only (sufficient for ssh-rsa keys)
  echo "$pk" | sed -e 's/ /%20/g' -e 's/+/%2B/g'
}

determine_pubkey_content() {
  local path
  if [[ -n "$PUBKEY_PATH" ]]; then
    path="$PUBKEY_PATH"
  else
    path="${SSH_KEY}.pub"
  fi
  [[ -f "$path" ]] || { log "Public key $path not found"; return 1; }
  cat "$path"
}

ensure_authorized_key() {
  local ip=$1
  local pk
  pk=$(determine_pubkey_content) || return 0
  log "Ensuring public key present on installed system"
  ssh -i "$SSH_KEY" root@${ip} "mkdir -p /root/.ssh; touch /root/.ssh/authorized_keys; grep -q '$(echo "$pk" | awk '{print $2}')' /root/.ssh/authorized_keys || echo '$pk' >> /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys"
}

run_verification() {
  local ip=$1
  local verify_script="$REPO_ROOT/robot/verify_post_boot.sh"
  if [[ ! -f "$verify_script" ]]; then
    log "Verification script not found; marking UNKNOWN"
    VERIFY_STATUS="UNKNOWN"
    return 0
  fi
  log "Uploading verification script"
  scp -i "$SSH_KEY" -q "$verify_script" root@${ip}:~/ || { log "Failed to upload verification script"; VERIFY_STATUS="UPLOAD_FAIL"; return 0; }
  log "Running verification script"
  if ssh -i "$SSH_KEY" root@${ip} "bash $(basename "$verify_script")"; then
    VERIFY_STATUS="PASS"
  else
    VERIFY_STATUS="FAIL"
  fi
  log "Verification result: $VERIFY_STATUS"
}

collect_versions() {
  local ip=$1
  local kernel nvidia dcv parsec
  kernel=$(ssh -i "$SSH_KEY" root@${ip} 'uname -r' 2>/dev/null || echo "")
  nvidia=$(ssh -i "$SSH_KEY" root@${ip} 'command -v nvidia-smi >/dev/null && nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1' 2>/dev/null || echo "")
  dcv=$(ssh -i "$SSH_KEY" root@${ip} 'command -v dcv >/dev/null && dcv --version 2>&1 | head -n1' 2>/dev/null || echo "")
  parsec=$(ssh -i "$SSH_KEY" root@${ip} 'systemctl is-active parsec 2>/dev/null || true' 2>/dev/null || echo "")
  echo "$kernel|$nvidia|$dcv|$parsec"
}

write_json_report() {
  mkdir -p "$RUN_DIR" || true
  local end_epoch=$(date +%s)
  local end_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local duration=$(( end_epoch - START_EPOCH ))
  local kernel="" nvidia="" dcv="" parsec=""
  if [[ -n "$HOST_IP" && "$STATUS" != "FAIL" ]]; then
    IFS='|' read -r kernel nvidia dcv parsec < <(collect_versions "$HOST_IP") || true
  fi
  local json
  json=$(cat <<J
{
  "run_id": "$RUN_ID",
  "status": "$STATUS",
  "skipped_reason": "${SKIPPED_REASON//"/\"}",
  "verify_status": "$VERIFY_STATUS",
  "start_iso": "$START_ISO",
  "end_iso": "$end_iso",
  "duration_sec": $duration,
  "server_id": "${ROBOT_SERVER_ID}",
  "host_ip": "${HOST_IP}",
  "variant": "${VARIANT}",
  "force_reprovision": $FORCE_REPROVISION,
  "kernel": "${kernel}",
  "nvidia_driver": "${nvidia}",
  "dcv_version_line": "${dcv//"/\"}",
  "parsec_service_state": "${parsec}",
  "verify_status": "${VERIFY_STATUS}"
}
J
)
  echo "$json" > "$RUN_DIR/report.json"
  REPORT_JSON="$RUN_DIR/report.json"
  log "Report written: $REPORT_JSON"
}

resume_marker_exists() {
  local ip=$1
  ssh -i "$SSH_KEY" -o ConnectTimeout=5 root@${ip} 'test -f /root/.ax102_provision_done' 2>/dev/null
}

write_remote_marker() {
  local ip=$1
  ssh -i "$SSH_KEY" root@${ip} "echo '{"run_id":"$RUN_ID","created":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}' > /root/.ax102_provision_done"
}

start_flow() {
  ensure_run_dir
  require_bin ssh; require_bin scp; require_bin curl
  [[ -n "$PUBKEY_PATH" ]] && [[ ! -f "$PUBKEY_PATH" ]] && fatal "--pubkey file not found: $PUBKEY_PATH"
  robot_enable_rescue_and_reset
  # Auto IP discovery if blank
  if [[ -z "$HOST_IP" && -n "$ROBOT_SERVER_ID" ]]; then
    HOST_IP=$(robot_get_ip || true)
    log "Discovered IP: ${HOST_IP:-<none>}"
  fi
  require_host
  plan_summary
  $DRY_RUN && { log "Dry-run mode; exiting before changes."; STATUS="DRY_RUN"; write_json_report; exit 0; }

  wait_for_ssh "$HOST_IP" "$WAIT_TIMEOUT"

  # Resume check
  if resume_marker_exists "$HOST_IP" && ! $FORCE_REPROVISION; then
    STATUS="RESUME-SKIPPED"
    SKIPPED_REASON="Existing provision marker present"
    log "Resume: skipping provisioning (marker found)."
    if $RERUN_ANSIBLE && ! $NO_ANSIBLE; then
      log "Re-running Ansible due to --rerun-ansible"
      run_ansible "$HOST_IP"
    fi
    write_json_report
    log "Connect: ssh root@${HOST_IP}"
    return 0
  fi

  push_and_run_provision_script "$HOST_IP"
  log "Provisioning script completed; rebooting host..."
  ssh -i "$SSH_KEY" root@${HOST_IP} 'reboot' || true
  sleep 10
  wait_for_ssh "$HOST_IP" "$WAIT_TIMEOUT"
  ensure_authorized_key "$HOST_IP"
  run_verification "$HOST_IP"
  if ! $NO_ANSIBLE; then
    run_ansible "$HOST_IP"
  else
    log "Skipping Ansible phase per --no-ansible"
  fi
  write_remote_marker "$HOST_IP" || true
  STATUS=$([[ "$VERIFY_STATUS" == PASS ]] && echo SUCCESS || echo SUCCESS) # still SUCCESS even if verification FAIL to allow inspection; FAIL already recorded in VERIFY_STATUS
  write_json_report
  log "All done. Connect: ssh root@${HOST_IP}"
}

destroy_flow() {
  plan_summary
  log "Dedicated hardware teardown is manual (cancel server via Robot panel). Extend as needed."
}

case "$CMD" in
  start) start_flow ;;
  destroy) destroy_flow ;;
  *) fatal "Unhandled command: $CMD" ;;
 esac
