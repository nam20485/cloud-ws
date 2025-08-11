#!/usr/bin/env bash
set -euo pipefail

# Simple Hetzner AX102 provisioning:
# - RAID1 /boot (1G)
# - RAID10 main array
# - LVM: root + optional swap + data (ext4)
# - Ubuntu 24.04 (noble) via debootstrap
# WARNING: Destroys data on /dev/nvme[0-3]n1

HOSTNAME=${HOSTNAME:-ax102-host}
UBUNTU_RELEASE="noble"
BOOT_SIZE_GB=${BOOT_SIZE_GB:-1}
ROOT_LV_SIZE=${ROOT_LV_SIZE:-100G}
SWAP_LV_SIZE=${SWAP_LV_SIZE:-8G}   # Set to 0 or empty to disable swap LV
SWAP_LV_NAME=${SWAP_LV_NAME:-swap}
VG_NAME=${VG_NAME:-vg0}
ROOT_LV_NAME=${ROOT_LV_NAME:-root}
DATA_LV_NAME=${DATA_LV_NAME:-data}
MD_BOOT=/dev/md_boot
MD_MAIN=/dev/md0

set -x

assert_root() { [[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }; }

prereqs() {
  apt-get update -y
  apt-get install -y mdadm lvm2 debootstrap gdisk wget curl
}

partition_disks() {
  for d in /dev/nvme{0..3}n1; do
    sgdisk --zap-all $d || true
    sgdisk -n1:1M:+1M -t1:ef02 -c1:"bios_grub" $d
    sgdisk -n2:0:+${BOOT_SIZE_GB}G -t2:8300 -c2:"boot" $d
    sgdisk -n3:0:0 -t3:8300 -c3:"main" $d
  done
  partprobe
}

create_md_arrays() {
  mdadm --create ${MD_BOOT} --level=1 --raid-devices=4 /dev/nvme0n1p2 /dev/nvme1n1p2 /dev/nvme2n1p2 /dev/nvme3n1p2 --metadata=1.0
  mdadm --create ${MD_MAIN} --level=10 --raid-devices=4 /dev/nvme0n1p3 /dev/nvme1n1p3 /dev/nvme2n1p3 /dev/nvme3n1p3
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
  mkfs.ext4 ${MD_BOOT}
  mkfs.ext4 /dev/${VG_NAME}/${ROOT_LV_NAME}
  mkfs.ext4 /dev/${VG_NAME}/${DATA_LV_NAME}
  if lvdisplay /dev/${VG_NAME}/${SWAP_LV_NAME} &>/dev/null; then
    mkswap /dev/${VG_NAME}/${SWAP_LV_NAME}
  fi
  mkdir -p /mnt/target
  mount /dev/${VG_NAME}/${ROOT_LV_NAME} /mnt/target
  mkdir -p /mnt/target/{boot,data}
  mount ${MD_BOOT} /mnt/target/boot
  mount /dev/${VG_NAME}/${DATA_LV_NAME} /mnt/target/data
}

bootstrap_ubuntu() {
  debootstrap --include=linux-image-generic,grub-pc,ssh ${UBUNTU_RELEASE} /mnt/target http://archive.ubuntu.com/ubuntu
}

configure_chroot() {
  echo ${HOSTNAME} > /mnt/target/etc/hostname
  cat <<EOF > /mnt/target/etc/hosts
127.0.0.1 localhost
127.0.1.1 ${HOSTNAME}
EOF
  cat <<EOF >> /mnt/target/etc/fstab
${MD_BOOT} /boot ext4 defaults 0 2
/dev/${VG_NAME}/${ROOT_LV_NAME} /     ext4 defaults 0 1
/dev/${VG_NAME}/${DATA_LV_NAME} /data ext4 defaults 0 2
EOF
  if lvdisplay /dev/${VG_NAME}/${SWAP_LV_NAME} &>/dev/null; then
    echo "/dev/${VG_NAME}/${SWAP_LV_NAME} none swap sw 0 0" >> /mnt/target/etc/fstab
  fi
  cp /etc/mdadm/mdadm.conf /mnt/target/etc/mdadm/mdadm.conf
  mount --bind /dev /mnt/target/dev
  mount --bind /proc /mnt/target/proc
  mount --bind /sys /mnt/target/sys
  chroot /mnt/target /bin/bash -c "update-initramfs -u || true"
  for disk in /dev/nvme{0..3}n1; do
    chroot /mnt/target grub-install $disk || true
  done
  chroot /mnt/target update-grub
  if lvdisplay /dev/${VG_NAME}/${SWAP_LV_NAME} &>/dev/null; then
    chroot /mnt/target /sbin/swapon -a || true
    mkdir -p /mnt/target/etc/sysctl.d
    cat <<EOT > /mnt/target/etc/sysctl.d/99-swap-tuning.conf
# Lower swappiness to reduce aggressive swapping; keep some capability
vm.swappiness=10
# Preserve cache metadata moderately
vm.vfs_cache_pressure=50
EOT
  fi
}

final_notes() {
  echo "Done. Set root password: chroot /mnt/target passwd"
  echo "Root LV: /dev/${VG_NAME}/${ROOT_LV_NAME}, Data LV: /dev/${VG_NAME}/${DATA_LV_NAME}" 
  if lvdisplay /dev/${VG_NAME}/${SWAP_LV_NAME} &>/dev/null; then
    echo "Swap LV: /dev/${VG_NAME}/${SWAP_LV_NAME} (activated)"
  fi
}

assert_root
prereqs
partition_disks
create_md_arrays
create_lvm
mkfs_and_mount
bootstrap_ubuntu
configure_chroot
final_notes
