# Implementation Plan (Derived From Committed Validation Choices)

This document translates the chosen validation items (those marked completed / selected) into concrete implementation and automation tasks. It also provides: 

1. Full Implementation Plan – structured backlog grouped by domain.
2. Quick Validation Plan (fast path you can execute immediately for rapid confidence).
3. Work Packages / Tickets suggestion (optional) for tracking.

> Scope focuses only on items you already marked as done/selected in `VALIDATION_PLAN.md`; unselected items are excluded except where a prerequisite is implicitly required.

---
## 1. Chosen Items Summary (Canonical Record)

| Section | Selected Items |
|---------|----------------|
| 1 Static Analysis | ansible-lint; syntax-check; list-tasks |
| 2 Dry Run & Safety | `--check` full dry run |
| 4 Molecule | Delegated driver (local VM); Testinfra verify |
| 5 Storage Simulation | QEMU/KVM VM with 4 extra virtio disks |
| 7 NICE DCV | Service status; session list & create virtual session |
| 8 Parsec | Service status; automated screenshot diff (headless X) |
| 9 Root Migration | VM snapshot test; post-migration LV + idempotent re-run |
| 10 Monitoring | Curl gpu metrics; ephemeral Prometheus; Grafana dashboard JSON |
| 12 CI/CD | GitHub Actions lint + syntax; Molecule idempotency; artifact upload |
| 13 Security | ansible-lint custom rules; Lynis baseline; Fail2ban & firewall validation |

---
## 2. Full Implementation Plan (Status Aug 9 2025)

Legend: [Done] fully implemented; [Partial] some elements in place; [Pending] not started yet.

### 2.1 Static + Lint Automation
Status: [Partial]
Tasks:
1. [Done] Ensure `requirements.txt` / version pinning (implemented).
2. [Pending] Add pre-commit hook (`.pre-commit-config.yaml`).
3. [Pending] Custom ansible-lint ruleset (`lint-rules/custom-security.yml`).

Deliverables Progress:
- `.pre-commit-config.yaml` – [Pending]
- `lint-rules/custom-security.yml` – [Pending]

### 2.2 Dry Run Integration
Status: [Done]
Tasks:
1. [Done] Make targets added.
2. [Done] Sample inventory added (`inventory.sample.ini`).

### 2.3 Molecule (Delegated + Testinfra)
Status: [Partial]
Tasks:
1. [Done] Delegated scenario scaffolded for `gpu_monitoring` role.
2. [Partial] Testinfra present for one role; common shared test module not yet centralized.
3. [Done] Idempotency sequence configured in scenario.
Next Steps: Add scenarios for additional roles; introduce `tests/common/` utilities.

### 2.4 Storage Simulation (QEMU/KVM VM)
Status: [Pending]
Tasks:
1. [Pending] Helper script `scripts/spawn-storage-vm.sh`.
2. [Pending] Bootstrap steps.
3. [Pending] Snapshot workflow docs.
Artifacts: [Pending]

### 2.5 NICE DCV Validation
Status: [Pending]
Tasks:
1. [Pending] Tag + validation tasks.
2. [Pending] Testinfra service check.

### 2.6 Parsec Validation + Screenshot Diff
Status: [Pending]
Tasks:
1. [Pending] Headless X/Xvfb play.
2. [Pending] Capture script.
3. [Pending] Baseline PNG.
4. [Pending] CI diff integration.

### 2.7 Root Migration VM Snapshot Test
Status: [Pending]
Tasks:
1. [Pending] Idempotent guard verification tasks.
2. [Pending] Snapshot provisioning wrapper.
3. [Pending] Verification data capture play.

### 2.8 Monitoring (Node Exporter + Ephemeral Prometheus + Grafana JSON)
Status: [Partial]
Tasks:
1. [Done] Textfile collector + GPU metrics script via role.
2. [Pending] Ephemeral Prometheus script.
3. [Pending] Grafana dashboard JSON.
4. [Pending] CI artifact upload integration.

### 2.9 CI/CD Enhancements
Status: [Partial]
Tasks:
1. [Done] `lint.yml` workflow implemented.
2. [Pending] Molecule workflow.
3. [Pending] Standard artifact log collection (.artifacts/).
4. [Pending] Conditional Parsec screenshot diff step.

### 2.10 Security / Hardening
Status: [Pending]
Tasks:
1. [Pending] Lynis integration.
2. [Pending] Fail2ban Testinfra check.
3. [Pending] Firewall rule validation.

### 2.11 Cross-Cutting: Logging & Artifacts
Status: [Pending]
Tasks:
1. [Pending] Log directory convention.
2. [Pending] `scripts/run_play.sh`.
3. [Pending] JSON callback plugin config.

### 2.12 Documentation Updates
Status: [Partial]
Tasks:
1. [Partial] New docs for Molecule delegated scenario (`MOLECULE_DELEGATED.md`); README updates pending.
2. [Pending] Troubleshooting appendix.

---
## 3. Quick Validation Plan (Run Now ~15–25 min)

Objective: Rapid confidence without waiting for full VM + screenshot diff stack.

Steps (ordered):
1. Lint & Syntax:
   - `ansible-lint` (existing) 
   - `ansible-playbook --syntax-check ubuntu-cinnamon/workstation.yml`
2. Task Listing Preview:
   - `ansible-playbook -i inventory.ini ubuntu-cinnamon/workstation.yml --list-tasks`
3. Dry Run:
   - `ansible-playbook -i inventory.ini ubuntu-cinnamon/workstation.yml --check -vv` (capture to `quick_run_dry.log`).
4. Targeted Real Run Subset (Non-destructive tags):
   - Run with tags `dcv,parsec,gpu_monitoring` (omit RAID/root migration for speed):
     `ansible-playbook -i inventory.ini ubuntu-cinnamon/workstation.yml --tags dcv,parsec,gpu_monitoring -vv | tee quick_subset.log`
5. Verify Services:
   - `systemctl status dcvserver | head -n 20`
   - `systemctl status parsecd | head -n 20`
   - `dcv list-sessions || true`
6. GPU Metrics (if GPU present):
   - `nvidia-smi -L`
   - `curl -s localhost:9100/metrics | grep -E 'gpu_' || echo 'gpu metrics not found yet'`
7. Idempotency Quick Check (subset):
   - Re-run step 4; confirm zero changes reported (expect 0 changed). Save as `quick_subset_rerun.log`.

Success Criteria:
- No lint errors.
- Dry run has 0 fatal errors.
- Subset real run changes only on first execution; second execution 0 changes.
- Services active (dcvserver, parsecd).
- GPU metrics accessible OR gracefully skipped if no GPU.

Optional (if spare 5–10 min):
- Launch ephemeral Prometheus: `scripts/ephemeral_prometheus.sh up` and curl a sample metric.

---
## 4. Backlog Prioritization (Suggested Order + Current State)
1. Quick Plan (above) ✅ (execute as needed)
2. Make targets + scripts scaffolding – [Partial] (Makefile done; scripts pending)
3. Artifact/log structure + CI lint workflow – [Partial] (lint CI done; artifact/log framework pending)
4. Delegated Molecule + common Testinfra – [Partial] (gpu_monitoring only)
5. Storage QEMU script – [Pending]
6. Monitoring stack (Prometheus + Grafana JSON) – [Pending]
7. Parsec screenshot diff pipeline – [Pending]
8. Root migration snapshot harness – [Pending]
9. Security (Lynis integration, firewall validation) – [Pending]

---
## 5. Work Package Suggestions

| ID | Title | Deliverables | Est |
|----|-------|--------------|-----|
| WP1 | Tooling & Make Targets | Makefile, scripts/run_play.sh | 0.5d |
| WP2 | CI Lint & Syntax | `.github/workflows/lint.yml` | 0.5d |
| WP3 | Molecule Delegated Base | molecule config + 1 role converge | 1d |
| WP4 | QEMU Storage Lab | spawn-storage-vm.sh + docs | 0.5d |
| WP5 | Monitoring Stack | prometheus script + dashboard json | 0.75d |
| WP6 | Parsec Visual Diff | capture script + baseline + CI step | 1d |
| WP7 | Root Migration Harness | snapshot + verification tasks | 0.75d |
| WP8 | Security Integration | Lynis, firewall checks, lint rule | 0.5d |

---
## 6. Risk & Mitigation Snapshot
| Area | Risk | Mitigation |
|------|------|------------|
| Delegated Molecule | VM accessibility flakiness | Pre-flight SSH probe + retry logic |
| Screenshot Diff | False positives due to render timing | Add delay + perceptual threshold |
| Root Migration | Accidental rerun altering root | Idempotent guard with fact file & LV existence check |
| Monitoring | Port conflicts | Use dynamic high port for ephemeral Prometheus |
| CI Runtime | Long Molecule runs | Tag gating + parallel matrix only for lint |

---
## 7. Metrics / Definition of Done
| Dimension | Metric | Target |
|----------|--------|--------|
| Idempotency | Changed count on second run (subset) | 0 |
| Lint | ansible-lint errors | 0 blocking |
| CI Duration | Lint workflow elapsed | < 5 min |
| Monitoring | gpu metrics lines exported | ≥ 1 (if GPU) |
| Visual Diff | MSE / perceptual diff score | Below threshold (configured) |

---
## 8. Next Immediate Step
Implement logging/artifact scaffolding (2.11) and add Molecule CI workflow; then proceed with storage simulation script (2.4) to unblock root migration harness later.

---
## 9. Appendix: Command Snippets (Reference)

These are informational. Adjust inventory & paths accordingly.

```
# Lint & syntax
ansible-lint
ansible-playbook --syntax-check ubuntu-cinnamon/workstation.yml

# Dry run
ansible-playbook -i inventory.ini ubuntu-cinnamon/workstation.yml --check -vv | tee quick_run_dry.log

# Subset real run
ansible-playbook -i inventory.ini ubuntu-cinnamon/workstation.yml --tags dcv,parsec,gpu_monitoring -vv | tee quick_subset.log

# Re-run for idempotency
ansible-playbook -i inventory.ini ubuntu-cinnamon/workstation.yml --tags dcv,parsec,gpu_monitoring -vv | tee quick_subset_rerun.log
```

---
Document owner: (update with maintainer name). Keep in sync with future changes in `VALIDATION_PLAN.md`.
