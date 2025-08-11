# Cloud Workstation / Hetzner AX102 Provisioning

This repository contains two provisioning tracks:

1. Hetzner Cloud (hcloud) VM (Terraform) – simple single-instance creation (no RAID) via `main.tf`.
2. Hetzner Dedicated AX102 (Robot rescue mode) – manual scripts to build high‑performance storage (RAID10 + LVM) and optional variants (ZFS, UEFI).
3. One‑touch AX102 automation wrapper (`scripts/ax102_automate.sh`) – orchestrates rescue enable/reset (Robot API), provisioning script execution, reboot, verification, optional Ansible, minimal reporting & resume.

## Contents Overview

| Path | Purpose |
|------|---------|
| `cloud/main.tf`, `cloud/variables.tf` | Terraform config for Hetzner Cloud server (NOT the dedicated AX102). |
| `ansible/site.yml` | Main Ansible play including roles for base, gpu, remote_desktop, hardening, firewall. |
| `robot/robot_provision_simple.sh` | BIOS (legacy) provisioning: RAID1 /boot + RAID10 + LVM root(+swap)+data (ext4). |
| `robot/robot_provision_simple_uefi.sh` | UEFI variant with per‑disk ESPs + RAID10 + LVM root(+swap)+data. |
| `robot/robot_provision_zfs.sh` | BIOS variant with small ZFS pool LV (ZFS-on-LVM) plus ext4 root/data. |
| `robot/verify_post_boot.sh` | Verification script for post‑boot health checks. |
| `scripts/ax102_automate.sh` | One‑touch wrapper orchestrating full dedicated provisioning flow. |
| `inventory.dedicated.example.ini` | Example Ansible inventory for the dedicated server. |

## Choosing a Variant

| Variant | Use When | Notes |
|---------|----------|-------|
| Simple (BIOS) | Fast, stable workstation; no Secure Boot needed | Easiest, reliable; root/data/swap LVs. |
| UEFI | Want modern firmware features / Secure Boot path | ESP replicated to each disk (optional). |
| ZFS (LV) | Need snapshots/compression for small code volume quickly | Performance OK for modest workloads; consider native ZFS layout later. |

## Simple (BIOS) Flow
1. Boot AX102 into Rescue system (Linux) from Hetzner Robot.
2. Upload or curl the script: `robot_provision_simple.sh`.
3. (Optional) Adjust environment vars:
   ```bash
   export ROOT_LV_SIZE=120G
   export SWAP_LV_SIZE=16G
   ```
4. Run `chmod +x robot_provision_simple.sh && ./robot_provision_simple.sh`.
5. `chroot /mnt/target passwd` to set root password (if desired) and `reboot`.
6. After boot, run Ansible playbook.

## UEFI Flow Differences
- Use `robot_provision_simple_uefi.sh`.
- Adds per‑disk 512M ESP partitions; first disk mounted at `/boot/efi`.
- Optional duplication of ESP contents to other disks (`REPLICATE_ESPS=true`).

## ZFS Variant Flow
- Use `robot_provision_zfs.sh` in rescue.
- Creates md RAID10 -> LVM -> small LV for ZFS pool + root + data.
- ZFS pool `codepool` mounted at `/srv/code` with `compression=lz4`.

## One‑Touch Automation Wrapper (MVP)

The wrapper reduces the manual rescue workflow to a single command.

Minimal flow:
```bash
export ROBOT_USER=xxx ROBOT_PASSWORD=yyy ROBOT_SERVER_ID=123456
./scripts/ax102_automate.sh start --variant uefi --full-workstation
```

Key features (MVP):
- Robot API: enable rescue + hardware reset (if credentials provided)
- Auto IP discovery (Robot API) if `--host` omitted
- Provisioning script selection: `--variant uefi|bios`
- Resume: creates `/root/.ax102_provision_done` – re-run skips destructive phase unless `--force`
- Verification: uploads & runs `robot/verify_post_boot.sh` capturing PASS/FAIL
- Key propagation: `--pubkey` or inferred `--ssh-key.pub` ensured in `/root/.ssh/authorized_keys`
- Minimal JSON report + log in `runs/<timestamp>/`

Useful flags:
| Flag | Purpose |
|------|---------|
| `--host <ip>` | Skip IP discovery / use existing server IP |
| `--variant uefi|bios` | Choose provisioning script variant |
| `--force` | Force full re-provision even if marker exists |
| `--rerun-ansible` | Run Ansible even during a resume skip |
| `--pubkey <path>` | Explicit public key (default derives from `--ssh-key.pub`) |
| `--no-ansible` | Skip Ansible phase |
| `--dry-run` | Show plan only, no changes |

Outputs:
- Combined log: `runs/<ts>/provision.log` (stdout/stderr tee)
- Report JSON: `runs/<ts>/report.json` containing: status, timings, server id, IP, variant, verification status, versions (kernel, NVIDIA driver, DCV, Parsec state)

Return codes:
- 0 success (including resume skip)
- Non-zero fatal provisioning/connection failures

Planned (optional) enhancements tracked in issue #28.

## Post‑Install (All Dedicated Variants)
1. Update `inventory.ini` (see example).
2. Run Ansible: `ansible-playbook -i inventory.ini ansible/site.yml`.
3. (Optional) Review verification: `bash robot/verify_post_boot.sh` (run on the server itself).

## Terraform (Cloud VM Path)
Create or export variable `hcloud_token` via Terraform Cloud workspace variable or `TF_VAR_hcloud_token`. Apply normally:
```bash
terraform init
terraform plan
terraform apply
```
(AX102 provisioning is *not* handled by Terraform here; Robot API automation could be added later.)

## Example Inventory
See `inventory.dedicated.example.ini`:
```
[raid_server]
203.0.113.42 ansible_user=root
```
After hardening, switch to `ansible_user=admin`.

## Environment Variable Overrides (Selected)
| Script | Variable | Default | Description |
|--------|----------|---------|-------------|
| simple BIOS | `ROOT_LV_SIZE` | 100G | Root LV size |
| simple BIOS | `SWAP_LV_SIZE` | 8G | Swap LV size (0 to disable) |
| simple UEFI | `ESP_SIZE_MB` | 512 | ESP size (each disk) |
| UEFI | `REPLICATE_ESPS` | true | Copy ESP to all disks |
| all | `HOSTNAME` | ax102-host | System hostname |

## Verification Script Outputs
The verification script checks:
- RAID arrays active (mdstat)
- LVM volumes present
- Swap active (if configured)
- fstab entries
- (Optional) ZFS pool presence
Return code 0 = all critical checks passed; non-zero indicates issues.

## Future Enhancements
- Role/tag-based selective Ansible, richer Markdown reporting, health guardrails, metrics, encryption, Secure Boot path, CI simulation, destroy helper, extended docs. See issue #28 for full list.

## Disclaimer
Use at your own risk. All provisioning scripts are destructive to listed NVMe devices. Confirm you are on the intended server in rescue mode before running.
