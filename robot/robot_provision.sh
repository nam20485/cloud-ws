#!/usr/bin/env bash
set -euo pipefail

# Hetzner Robot AX102 RAID10 + LVM Provision Script
# Run inside the rescue system (e.g., booted via Hetzner Robot -> Rescue)
# WARNING: Destroys data on /dev/nvme[0-3]n1

# Adjustable parameters
HOSTNAME=${HOSTNAME:-ax102-host}
UBUNTU_RELEASE="noble"        # 24.04
MD_DEVICE=/dev/md0
VG_NAME=vg0
LV_ROOT_SIZE=+100G            # Use the first 100G for root
LV_VAR_SIZE=+50G              # Example var size
# Remaining space goes to /home (or data) if enabled
CREATE_HOME_LV=true

set -x

function assert_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Run as root." >&2
    exit 1
  fi
}

function prereqs() {
  apt-get update -y
  apt-get install -y mdadm lvm2 debootstrap gdisk wget curl
}

function wipe_disks() {
  for d in /dev/nvme[0-3]n1; do
    wipefs -a $d || true
    sgdisk --zap-all $d || true
  done
}

function create_raid10() {
  mdadm --create ${MD_DEVICE} --level=10 --raid-devices=4 /dev/nvme0n1 /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1
  mdadm --detail --scan >> /etc/mdadm/mdadm.conf
  update-initramfs -u || true
}

function create_lvm() {
  pvcreate ${MD_DEVICE}
  vgcreate ${VG_NAME} ${MD_DEVICE}
  lvcreate -L ${LV_ROOT_SIZE} -n root ${VG_NAME}
  lvcreate -L ${LV_VAR_SIZE} -n var ${VG_NAME}
  if [[ "${CREATE_HOME_LV}" == "true" ]]; then
    lvcreate -l 100%FREE -n home ${VG_NAME}
  fi
}

function mkfs_and_mount() {
  mkfs.ext4 /dev/${VG_NAME}/root
  mkfs.ext4 /dev/${VG_NAME}/var
  if [[ "${CREATE_HOME_LV}" == "true" ]]; then
    mkfs.ext4 /dev/${VG_NAME}/home
  fi
  mkdir -p /mnt/target
  mount /dev/${VG_NAME}/root /mnt/target
  mkdir -p /mnt/target/{var,home,boot}
  mount /dev/${VG_NAME}/var /mnt/target/var
  if [[ "${CREATE_HOME_LV}" == "true" ]]; then
    mount /dev/${VG_NAME}/home /mnt/target/home
  fi
}

function bootstrap_ubuntu() {
  debootstrap --include=linux-image-generic,grub-pc,ssh ${UBUNTU_RELEASE} /mnt/target http://archive.ubuntu.com/ubuntu
}

function chroot_config() {
  cat <<EOF > /mnt/target/etc/hostname
${HOSTNAME}
EOF
  cat <<EOF > /mnt/target/etc/hosts
127.0.0.1 localhost
127.0.1.1 ${HOSTNAME}
EOF
  genfstab -U /mnt/target > /mnt/target/etc/fstab || true
  # Fallback manual fstab
  cat <<EOF >> /mnt/target/etc/fstab
/dev/${VG_NAME}/root /     ext4  defaults 0 1
/dev/${VG_NAME}/var  /var  ext4  defaults 0 2
/dev/${VG_NAME}/home /home ext4  defaults 0 2
EOF
  cp /etc/mdadm/mdadm.conf /mnt/target/etc/mdadm/mdadm.conf
  mount --bind /dev /mnt/target/dev
  mount --bind /proc /mnt/target/proc
  mount --bind /sys /mnt/target/sys
  chroot /mnt/target /bin/bash -c "update-initramfs -u || true"
  chroot /mnt/target /bin/bash -c "grub-install /dev/nvme0n1"
  chroot /mnt/target /bin/bash -c "update-grub"
}

function cleanup() {
  echo "Provisioning complete. Set a root password inside chroot if needed: chroot /mnt/target passwd"
}

assert_root
prereqs
wipe_disks
create_raid10
create_lvm
mkfs_and_mount
bootstrap_ubuntu
chroot_config
cleanup
