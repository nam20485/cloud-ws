# Workstation Provisioning Validation Plan

Structured, incremental validation paths for `ubuntu-cinnamon/workstation.yml` with selectable checkboxes.

## Legend / Tags

- [ ] Unselected item (tick as you adopt)
- (Rec) Recommended for most workflows
- (Opt) Optional / nice-to-have
- (Adv) Advanced / deeper assurance
- (Risk) Higher operational risk if done on production host
- (Cost$) May incur cloud or service charges (avoid unless approved)
- (MutEx) Member of a mutually exclusive choice group – pick ONE in that group

> Goal: Max confidence with minimal/no spend. Prioritize local + free steps first.

---
## 1. Static Analysis & Lint (Fast, No Cost)

- [x] (Rec) Run `ansible-lint` on the repo (catches style & common errors) — Benefit: early failure; Tradeoff: may require minor stylistic fixes.
- [x] (Rec) `ansible-playbook --syntax-check ubuntu-cinnamon/workstation.yml` — Benefit: ensures YAML + task syntax; Tradeoff: none.
- [x] (Rec) `ansible-playbook -i inventory.ini ubuntu-cinnamon/workstation.yml --list-tasks` — Benefit: scope preview; Tradeoff: none.

## 2. Dry Run & Safety Gates

- [x] (Rec) Use `--check` mode (dry run) (some tasks may report changed incorrectly) — Benefit: safe preview; Tradeoff: not all modules fully support check mode.
- [ ] (Opt) Tag filtering (`--tags raid_lvm,nvidia`) to validate critical subsets first — Benefit: quicker feedback; Tradeoff: partial coverage.

## 3. Idempotency Verification

- [ ] (Rec) Full run #1 capture log (`run1.log`) — Benefit: baseline.
- [ ] (Rec) Immediate run #2 compare output to ensure zero changes — Benefit: ensures repeatability; Tradeoff: time (double run).
- [ ] (Opt) Parse JSON callback output to machine‑detect unintended changes — Benefit: automated gate; Tradeoff: setup overhead.

## 4. Role-Level Unit Testing (Molecule)

Choose one containerized approach (MutEx):
- [ ] (MutEx)(Rec) Molecule + Docker driver with selective role converge (skip GPU / RAID tasks via vars) — Benefit: fast local; Tradeoff: cannot exercise real mdadm or GPU.
- [ ] (MutEx)(Opt) Molecule + Podman driver (rootless) — Benefit: no Docker dependency; Tradeoff: similar limitations.
- [x] (MutEx)(Adv) Molecule + Delegated (local VM) for closer system fidelity — Benefit: real systemd & kernel modules; Tradeoff: more setup.

Additional:
- [x] (Opt) Write Molecule verify step using Testinfra (check packages, services, rendered configs).

## 5. Storage Stack Simulation (No Real NVMe Yet)

Pick ONE primary simulation path (MutEx):
- [ ] (MutEx)(Rec) Loopback sparse files + losetup to mimic 4 devices — Benefit: zero cost, mdadm+lvm real; Tradeoff: lower performance.
- [x] (MutEx)(Opt) QEMU/KVM local VM with 4 extra virtio disks — Benefit: isolation; Tradeoff: more RAM/CPU.
- [ ] (MutEx)(Cost$)(Adv) Cloud ephemeral instance with 4 detachable volumes — Benefit: closer to prod cloud behavior; Tradeoff: spend.

Enhancements:
- [ ] (Opt) Stress test md array (`fio` read/write) — Benefit: performance baseline; Tradeoff: time.

## 6. GPU Feature Validation

Tiered (can combine except where noted):
- [ ] (Rec) `nvidia-smi` basic driver load after playbook (local GPU host) — Benefit: confirms driver + persistence; Tradeoff: requires physical GPU.
- [ ] (Opt) Run a CUDA sample or `glxgears` to produce utilization — Benefit: functional load test; Tradeoff: install extras.
- [ ] (Opt) Monitor metrics via node_exporter textfile to confirm updates — Benefit: validates monitoring role; Tradeoff: minor delay.
- [ ] (Cost$)(Adv) Cloud GPU instance test (e.g. AWS g5) — Benefit: parity with remote environment; Tradeoff: cost.

## 7. NICE DCV Validation

- [x] (Rec) Check service: `systemctl status dcvserver` — Benefit: immediate health.
- [x] (Opt) `dcv list-sessions` & create a virtual session — Benefit: session layer test; Tradeoff: modest time.
- [ ] (Opt) Client connect from LAN and observe frame rate & quality — Benefit: end-user QoE; Tradeoff: manual interaction.
- [ ] (Adv) Packet capture (QUIC enabled) to confirm transport — Benefit: verifies performance features; Tradeoff: complexity.

## 8. Parsec Validation

- [x] (Rec) Service status: `systemctl status parsecd` — Benefit: baseline.
- [ ] (Opt) Client connection & stats overlay to validate bitrate and latency — Benefit: functional QoE; Tradeoff: manual.
- [x] (Adv) Automated screenshot diff (headless X) to detect rendering differences — Benefit: regression detection; Tradeoff: scripting overhead.

## 9. Root Migration Testing

Pick ONE initial approach (MutEx):
- [x] (MutEx)(Rec) VM snapshot test: enable `migrate_root: true` → verify new root device after reboot — Benefit: safe & reversible; Tradeoff: requires snapshot tooling.
- [ ] (MutEx)(Opt) Loopback device environment root migration — Benefit: local; Tradeoff: more manual mapping.
- [ ] (MutEx)(Risk)(Adv) Direct on target hardware (after backups) — Benefit: final confidence; Tradeoff: risk of unbootable system.

Post-migration checks:
- [x] (Rec) Confirm new `/` is LV via `lsblk` & `mount` — Benefit: correctness.
- [x] (Rec) Re-run playbook (idempotent path) — Benefit: ensures no re-migration.

## 10. Monitoring & Metrics

- [x] (Rec) Curl node exporter metrics: `curl localhost:9100/metrics | grep gpu_` — Benefit: quick validation.
- [x] (Opt) Spin up ephemeral Prometheus via docker-compose to scrape metrics — Benefit: trending visibility; Tradeoff: container setup.
- [x] (Adv) Add Grafana dashboard JSON (local container) — Benefit: visualization; Tradeoff: more components.
- [ ] (Cost$)(Opt) Hosted Prometheus/Grafana SaaS — Benefit: zero infra management; Tradeoff: recurring cost.

## 11. Performance / Load Scenarios

- [ ] (Opt) Parsec high bitrate soak (30+ min) to watch thermals — Benefit: stability check.
- [ ] (Opt) Concurrent DCV + Parsec sessions (if supported) — Benefit: contention handling; Tradeoff: complexity.
- [ ] (Adv) Stress-ng CPU + simultaneous GPU load — Benefit: worst-case thermal/perf profile; Tradeoff: peak power & noise.

## 12. CI/CD Integration

- [x] (Rec) GitHub Actions: lint + syntax job (matrix of ansible versions) — Benefit: consistent gate.
- [x] (Rec) GitHub Actions: Molecule (container) idempotency check — Benefit: automated regression detection.
- [x] (Opt) Artifact upload of logs (`/proc/mdstat`, `lvs`, `nvidia-smi`) — Benefit: audit trail.
- [ ] (Adv) Self-hosted GPU runner for full path — Benefit: near-prod validation; Tradeoff: hardware mgmt.
- [ ] (Cost$)(Opt) Packer template build (cloud builder) — Benefit: ready-made image artifact; Tradeoff: cloud spend.

## 13. Security / Hardening (Future Optional)

- [x] (Opt) ansible-lint ruleset extension for security
- [x] (Opt) Lynis baseline scan inside VM
- [x] (Opt) Fail2ban & firewall rule validation

## 14. Decision Summary Template

Fill once selections are made:

| Category | Chosen Option(s) | Rationale | Date |
|----------|------------------|-----------|------|
| Storage Simulation | | | |
| GPU Validation | | | |
| Root Migration | | | |
| Monitoring | | | |
| CI/CD | | | |

## 15. Recommended Minimal Path (Cost-Free)

1. Static Analysis (Section 1)
2. Dry Run + Idempotency (Sections 2–3)
3. Loopback RAID/LVM simulation (Section 5 first option)
4. NVIDIA + Monitoring on local GPU host (Sections 6 + 10 first items)
5. DCV & Parsec service status checks (Sections 7–8 first items)
6. VM snapshot root migration test (Section 9 first option)
7. GitHub Actions lint + Molecule (Section 12 first two items)

> Estimated Time: ~2–4 hours initial, <10 min per incremental change afterwards.

## 16. Tradeoff Highlights

| Choice | Benefit | Tradeoff |
|--------|---------|----------|
| Loopback vs Cloud Storage Test | Free, quick | Not real NVMe latency |
| Local GPU vs Cloud GPU | Zero cost (if hardware exists) | May differ from target cloud drivers |
| Root Migration in VM first | Safe rehearsal | Slightly less hardware realism |
| Node exporter only vs Full Prometheus Stack | Simplicity | No historical trends |
| Actions container test vs GPU runner | Cheap & scalable | Cannot validate GPU & DCV/Parsec fully |

---
### Next Steps
Select checkboxes, commit this file, then implement chosen pipeline pieces incrementally.
