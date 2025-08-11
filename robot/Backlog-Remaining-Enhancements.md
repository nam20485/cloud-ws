# Backlog / Remaining Enhancements

1. (B) Encryption variant: LUKS on md0 before LVM with separate /boot RAID1.
2. (C) Secure Boot workflow (keys, signed NVIDIA modules).
3. (D) CI linting: Add shellcheck & ansible-lint GitHub Actions.
4. (E) Native all-ZFS mirrored vdev variant (root-on-ZFS).
5. Quick Win 2: shellcheck GitHub Action.
6. Quick Win 4: Encryption-ready script skeleton (ties to item 1).
7. Add Parsec headless auto-login systemd service.
8. Add automated RAID health alerting (mdadm --monitor + mail / webhook).
9. Add Prometheus alert rules & example scrape configs.
10. Add Terraform module split (network, compute) for cloud/.
11. Documentation: architecture diagram (PNG + source).
Open new issues referencing these lines as needed.