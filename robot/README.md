# Hetzner Robot AX102 Provisioning

This directory contains tooling to provision a dedicated AX102 server (with 4x NVMe) via the Hetzner Robot API, then prepare RAID10 + LVM before OS handoff (Ubuntu 24.04) and subsequent Ansible customization.

## Flow Overview
1. Order server via Robot API (if not already rented) – manual or future automation.
2. Use rescue system (Linux) to run `robot_provision.sh`:
   - Partitions /dev/nvme[0-3]n1 (whole disk) or wipes any prior md/LVM signatures.
   - Creates mdadm RAID10 /dev/md0 across the four disks.
   - Creates PV/VG/LV layout (vg0/root, vg0/var, vg0/home optional) on /dev/md0.
   - Formats filesystems (ext4 default) and mounts under /mnt/target.
   - Downloads and installs Ubuntu debootstrap OR triggers `installimage` templating (future option).
3. Installs basic packages + writes fstab + mdadm.conf.
4. Reboots into installed system.
5. Ansible playbook (`ansible/raid_setup.yml`) finalizes GPU drivers, DCV, Parsec, hardening.

### Variant: ZFS + Separate /boot
If you need a small ZFS pool for source code plus conventional ext4 for the OS and data, use `robot_provision_zfs.sh` instead:
1. Creates 1G RAID1 `/boot` across all 4 disks (`/dev/md_boot`).
2. Creates RAID10 (`/dev/md0`) from the remaining space.
3. LVM on `/dev/md0` with three LVs: `root`, `zfs_lv` (small), `data` (rest).
4. Bootstraps Ubuntu on `root`, formats `data` ext4, and (inside chroot) installs ZFS and builds a pool `codepool` on `zfs_lv`.
5. Mounts ZFS dataset at `/srv/code` by default.

NOTE: ZFS-on-LVM is supported for light use/test scenarios but not generally recommended for high-performance or production pools. For best performance you'd dedicate raw RAID members or a partition directly to ZFS (future enhancement would split the md RAID10 into multiple md devices or use multiple RAID10 vdevs). Proceed with awareness of the trade‑offs.

### Variant: Simple EXT4 (Recommended for Most Dev Workstations)
Use `robot_provision_simple.sh` when you only need a fast, reliable layout without ZFS complexity:
1. Creates 1G RAID1 `/boot` across all 4 disks (`/dev/md_boot`).
2. Creates RAID10 (`/dev/md0`) for the remaining space.
3. LVM on `/dev/md0` with `root` (configurable size, default 100G) and `data` (rest of space).
4. Formats both as ext4, bootstraps Ubuntu, installs GRUB to all disks.
5. Leaves `/data` for large source trees, build artifacts, containers, etc.

Benefits: Simplicity, predictable performance, easy recovery, minimal tooling. Add ZFS later by carving a new LV if truly needed.

### Variant: UEFI EXT4 (ESP + RAID10 + LVM Root/Data/Swap)
Use `robot_provision_simple_uefi.sh` for modern UEFI boot with redundant copies of the EFI System Partition (ESP) across disks.

Layout:
1. Each NVMe disk: 512M EFI partition (FAT32, type EF00) + remainder for data.
2. RAID10 md array `/dev/md0` built from all second partitions.
3. LVM on `/dev/md0` with LVs: `root` (default 100G), optional `swap` (default 8G), `data` (remainder).
4. Only the first disk's ESP is mounted at `/boot/efi`; GRUB is installed for EFI. Script can optionally duplicate ESP contents to remaining disks for resilience.

Pros:
- UEFI firmware boot entries, easy Secure Boot enable later.
- Multi-disk redundancy (if you copy ESP to others).
- Same operational simplicity for root/data as BIOS variant.

Cons:
- Slightly more provisioning steps (ESP duplication logic).
- If first disk fails and ESPs not replicated, manual recovery needed.

To replicate ESPs the script can create and sync to others (controlled by an env var). If you disable replication, plan a manual copy after kernel updates occasionally.

## Current Status
- Script skeleton created (needs Robot credentials exported as env vars if extended to API ordering).
- Adjust variables in the header of the script as needed (filesystem sizes, etc.).

## Next Steps / TODO
- Integrate actual order / cancellation via Robot API endpoints (JSON over HTTPS with basic auth).
- Optional: Use cloud-init + custom ISO approach.
- Add automated test (containerized mdadm simulation) – low priority.
 - Provide alternative layout with native ZFS (no LVM) for the code volume.

## Safety
This script performs destructive wipe on /dev/nvme[0-3]n1. Ensure you are in RESCUE mode and targeting the correct server.
