#!/usr/bin/env bash
set -euo pipefail

# Post-boot verification for AX102 provisioning
# Run ON the provisioned host (not in rescue)

FAILED=0

section() { echo -e "\n== $1 =="; }
fail() { echo "[FAIL] $1"; FAILED=1; }
pass() { echo "[ OK ] $1"; }

section "Kernel & OS"
uname -a || fail "uname failed" || true
lsb_release -ds 2>/dev/null || cat /etc/os-release | head -n1

section "RAID Status"
if grep -q md /proc/mdstat; then
  cat /proc/mdstat
  awk '/^md/{if($4!="active")exit 1}' /proc/mdstat && pass "md arrays active" || fail "RAID array not active"
else
  fail "No md arrays detected"
fi

section "LVM"
if command -v lvs >/dev/null; then
  lvs || fail "lvs command failed" || true
  vgs || true
  pvs || true
else
  fail "LVM tools missing"
fi

section "Filesystems"
mount | egrep '(/boot|/data|/srv/code)' || true
df -h | egrep 'Filesystem|/boot|/data|/srv/code'

section "Swap"
if swapon --show | grep -q '^'; then
  swapon --show && pass "Swap active" || fail "Swap show failed"
else
  echo "No active swap (ok if intentionally disabled)"
fi

section "fstab Consistency"
MISSING=0
for p in /boot / /data; do
  grep -q "[[:space:]]$p[[:space:]]" /etc/fstab || { echo "Missing $p in fstab"; MISSING=1; }
done
if [ -d /srv/code ]; then
  grep -q "/srv/code" /etc/fstab || echo "(Note) /srv/code not in fstab (ZFS auto-mount)"
fi
[ $MISSING -eq 0 ] && pass "fstab entries present" || fail "fstab missing entries"

section "ZFS (optional)"
if command -v zpool >/dev/null; then
  zpool list || fail "zpool list failed" || true
  zfs list || true
fi

section "NVIDIA"
if command -v nvidia-smi >/dev/null; then
  nvidia-smi || fail "nvidia-smi failed" || pass "nvidia-smi OK"
else
  echo "NVIDIA tools not installed yet (ok pre-Ansible)"
fi

section "Summary"
if [ $FAILED -eq 0 ]; then
  echo "All critical checks passed."; exit 0
else
  echo "One or more checks failed."; exit 1
fi
