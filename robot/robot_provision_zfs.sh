#!/usr/bin/env bash
set -euo pipefail

# Hetzner AX102 provisioning with:
# - RAID1 /boot (1G) across 4 NVMe disks (metadata=1.0)
# - RAID10 for the rest
# - LVM on RAID10 with root + data + ZFS LV
# - Small ZFS pool (codepool) on dedicated LV (ZFS-on-LVM caveat)
# - Ubuntu 24.04 (noble) via debootstrap
# WARNING: Destroys data on /dev/nvme[0-3]n1

HOSTNAME=${HOSTNAME:-ax102-host}
UBUNTU_RELEASE="noble"
BOOT_SIZE_GB=1
ZFS_LV_SIZE=20G          # Adjust size for source code pool
ROOT_LV_SIZE=100G        # OS root
DATA_LV_PERCENT=100      # Remainder (after root + zfs)
MD_BOOT=/dev/md_boot
MD_MAIN=/dev/md0
VG_NAME=vg0
ZFS_LV_NAME=zfs_lv
ROOT_LV_NAME=root
DATA_LV_NAME=data
ZFS_POOL_NAME=codepool
ZFS_MOUNTPOINT=/srv/code

set -x

assert_root() { [[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }; }

prereqs() {
  apt-get update -y
  apt-get install -y mdadm lvm2 debootstrap gdisk wget curl zfs-initramfs || true
}

partition_disks() {
  for d in /dev/nvme{0..3}n1; do
    sgdisk --zap-all $d || true
    # Create BIOS grub gap + boot partition + main partition
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
  lvcreate -L ${ZFS_LV_SIZE} -n ${ZFS_LV_NAME} ${VG_NAME}
  lvcreate -l 100%FREE -n ${DATA_LV_NAME} ${VG_NAME}
}

mkfs_and_mount() {
  mkfs.ext4 ${MD_BOOT}
  mkfs.ext4 /dev/${VG_NAME}/${ROOT_LV_NAME}
  mkfs.ext4 /dev/${VG_NAME}/${DATA_LV_NAME}
  mkdir -p /mnt/target
  mount /dev/${VG_NAME}/${ROOT_LV_NAME} /mnt/target
  mkdir -p /mnt/target/{boot,data,$(dirname ${ZFS_MOUNTPOINT#\/})}
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
  cp /etc/mdadm/mdadm.conf /mnt/target/etc/mdadm/mdadm.conf
  mount --bind /dev /mnt/target/dev
  mount --bind /proc /mnt/target/proc
  mount --bind /sys /mnt/target/sys
  chroot /mnt/target /bin/bash -c "apt-get update -y && apt-get install -y zfs-initramfs"
  # Prepare ZFS LV inside chroot
  chroot /mnt/target /bin/bash -c "modprobe zfs || true"
  chroot /mnt/target /bin/bash -c "zpool create -f -m ${ZFS_MOUNTPOINT} ${ZFS_POOL_NAME} /dev/${VG_NAME}/${ZFS_LV_NAME}"
  chroot /mnt/target /bin/bash -c "zfs set compression=lz4 ${ZFS_POOL_NAME}"
  # Persist ZFS import (zpool cache auto handled); ensure mountpoint dir exists
  mkdir -p /mnt/target${ZFS_MOUNTPOINT}
  # Install bootloader
  for disk in /dev/nvme{0..3}n1; do
    chroot /mnt/target /bin/bash -c "grub-install $disk" || true
  done
  chroot /mnt/target update-initramfs -u || true
  chroot /mnt/target update-grub
}

final_notes() {
  echo "Done. Set root password: chroot /mnt/target passwd"
  echo "ZFS pool: ${ZFS_POOL_NAME} mounted at ${ZFS_MOUNTPOINT}"
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
