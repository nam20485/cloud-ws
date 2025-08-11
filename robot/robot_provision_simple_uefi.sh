#!/usr/bin/env bash
set -euo pipefail

# UEFI Hetzner AX102 provisioning:
# - Per-disk GPT: 512M EFI System Partition (ESP) + remainder
# - RAID10 over second partitions
# - LVM: root + optional swap + data (ext4)
# - Ubuntu 24.04 (noble) via debootstrap
# - Installs GRUB in UEFI mode; optionally replicates ESP to all disks
# WARNING: Destroys data on /dev/nvme[0-3]n1

HOSTNAME=${HOSTNAME:-ax102-host}
UBUNTU_RELEASE="noble"
ESP_SIZE_MB=${ESP_SIZE_MB:-512}
ROOT_LV_SIZE=${ROOT_LV_SIZE:-100G}
SWAP_LV_SIZE=${SWAP_LV_SIZE:-8G}
VG_NAME=${VG_NAME:-vg0}
ROOT_LV_NAME=${ROOT_LV_NAME:-root}
DATA_LV_NAME=${DATA_LV_NAME:-data}
SWAP_LV_NAME=${SWAP_LV_NAME:-swap}
REPLICATE_ESPS=${REPLICATE_ESPS:-true}  # If true, copies ESP contents to all disks
EFI_DIR=/boot/efi
MD_MAIN=/dev/md0

set -x

assert_root() { [[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }; }

prereqs() {
  apt-get update -y
  apt-get install -y mdadm lvm2 debootstrap gdisk wget curl grub-efi-amd64-bin grub-efi-amd64-signed shim-signed efibootmgr
}

partition_disks() {
  for d in /dev/nvme{0..3}n1; do
    sgdisk --zap-all $d || true
    sgdisk -n1:1M:+${ESP_SIZE_MB}M -t1:ef00 -c1:"esp" $d
    sgdisk -n2:0:0 -t2:8300 -c2:"main" $d
  done
  partprobe
}

create_md() {
  mdadm --create ${MD_MAIN} --level=10 --raid-devices=4 /dev/nvme0n1p2 /dev/nvme1n1p2 /dev/nvme2n1p2 /dev/nvme3n1p2
  mdadm --detail --scan >> /etc/mdadm/mdadm.conf
  update-initramfs -u || true
}

create_lvm() {
  pvcreate ${MD_MAIN}
  vgcreate ${VG_NAME} ${MD_MAIN}
  lvcreate -L ${ROOT_LV_SIZE} -n ${ROOT_LV_NAME} ${VG_NAME}
  if [[ -n "${SWAP_LV_SIZE}" && "${SWAP_LV_SIZE}" != "0" ]]; then
    lvcreate -L ${SWAP_LV_SIZE} -n ${SWAP_LV_NAME} ${VG_NAME}
  fi
  lvcreate -l 100%FREE -n ${DATA_LV_NAME} ${VG_NAME}
}

mkfs_and_mount() {
  # Format only first ESP now; others will be formatted if replication is enabled
  mkfs.vfat -F32 /dev/nvme0n1p1
  mkfs.ext4 /dev/${VG_NAME}/${ROOT_LV_NAME}
  mkfs.ext4 /dev/${VG_NAME}/${DATA_LV_NAME}
  if lvdisplay /dev/${VG_NAME}/${SWAP_LV_NAME} &>/dev/null; then
    mkswap /dev/${VG_NAME}/${SWAP_LV_NAME}
  fi
  mkdir -p /mnt/target
  mount /dev/${VG_NAME}/${ROOT_LV_NAME} /mnt/target
  mkdir -p /mnt/target/{${EFI_DIR#/},data}
  mount /dev/${VG_NAME}/${DATA_LV_NAME} /mnt/target/data
  mkdir -p /mnt/target${EFI_DIR}
  mount /dev/nvme0n1p1 /mnt/target${EFI_DIR}
}

bootstrap_ubuntu() {
  debootstrap --include=linux-image-generic,ssh ${UBUNTU_RELEASE} /mnt/target http://archive.ubuntu.com/ubuntu
}

configure_system() {
  echo ${HOSTNAME} > /mnt/target/etc/hostname
  cat <<EOF > /mnt/target/etc/hosts
127.0.0.1 localhost
127.0.1.1 ${HOSTNAME}
EOF
  cat <<EOF >> /mnt/target/etc/fstab
/dev/${VG_NAME}/${ROOT_LV_NAME} /     ext4 defaults 0 1
/dev/${VG_NAME}/${DATA_LV_NAME} /data ext4 defaults 0 2
/dev/nvme0n1p1 ${EFI_DIR} vfat umask=0077 0 1
EOF
  if lvdisplay /dev/${VG_NAME}/${SWAP_LV_NAME} &>/dev/null; then
    echo "/dev/${VG_NAME}/${SWAP_LV_NAME} none swap sw 0 0" >> /mnt/target/etc/fstab
  fi
  cp /etc/mdadm/mdadm.conf /mnt/target/etc/mdadm/mdadm.conf
  mount --bind /dev /mnt/target/dev
  mount --bind /proc /mnt/target/proc
  mount --bind /sys /mnt/target/sys
  chroot /mnt/target /bin/bash -c "apt-get update -y && apt-get install -y grub-efi-amd64 shim-signed efibootmgr mdadm lvm2"
  chroot /mnt/target update-initramfs -u || true
  chroot /mnt/target grub-install --target=x86_64-efi --efi-directory=${EFI_DIR} --bootloader-id=GRUB --recheck
  chroot /mnt/target update-grub
  if lvdisplay /dev/${VG_NAME}/${SWAP_LV_NAME} &>/dev/null; then
    chroot /mnt/target /sbin/swapon -a || true
    mkdir -p /mnt/target/etc/sysctl.d
    cat <<EOT > /mnt/target/etc/sysctl.d/99-swap-tuning.conf
vm.swappiness=10
vm.vfs_cache_pressure=50
EOT
  fi
}

replicate_esps() {
  [[ "${REPLICATE_ESPS}" == "true" ]] || return 0
  for disk in /dev/nvme{1..3}n1; do
    part=${disk}p1
    mkfs.vfat -F32 ${part}
    tmpdir=$(mktemp -d)
    mount ${part} ${tmpdir}
    cp -a /mnt/target${EFI_DIR}/* ${tmpdir}/
    umount ${tmpdir}
    rmdir ${tmpdir}
  done
  echo "ESP contents replicated to remaining disks. Consider setting firmware boot order accordingly."
}

final_notes() {
  echo "UEFI provisioning complete. Root: /dev/${VG_NAME}/${ROOT_LV_NAME}, Data: /dev/${VG_NAME}/${DATA_LV_NAME}" 
  if lvdisplay /dev/${VG_NAME}/${SWAP_LV_NAME} &>/dev/null; then
    echo "Swap: /dev/${VG_NAME}/${SWAP_LV_NAME}" 
  fi
  echo "Primary ESP: /dev/nvme0n1p1 (others replicated=${REPLICATE_ESPS})"
  echo "Set root password: chroot /mnt/target passwd"
}

assert_root
prereqs
partition_disks
create_md
create_lvm
mkfs_and_mount
bootstrap_ubuntu
configure_system
replicate_esps
final_notes
