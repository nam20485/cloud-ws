# Provisioning Pre‑Run & Validation Checklist

Purpose: A structured, repeatable sequence to safely provision the Hetzner workstation via Terraform + Ansible (local `make provision` or the GitHub Actions `Provision RAID Workstation` workflow).

---
## Tiered Approaches Overview
Choose the minimal rigor that matches your goal. You can always escalate to a higher tier without redoing earlier steps (they nest).

| Tier | When to Use | Steps (Count) | Time Cost | Typical Use Cases |
|------|-------------|---------------|-----------|-------------------|
| Super‑Lite ("fast smoke") | You just changed a trivial role line & need a quick boot test | 4 | ~3–6 min plan + apply | Quick iteration, PR spike |
| Lite ("developer loop") | Need confidence infra + core roles succeed | 7 | ~8–15 min | Daily dev, non‑destructive changes |
| Full ("pre‑merge / prod") | Anything risky (root migration, new roles) or before sharing externally | 30+ (detailed) | 15–25+ min | Release readiness, audit trail |

### Super‑Lite Steps (4 Musts)
1. Token available (`HCLOUD_TOKEN` secret or export `TF_VAR_hcloud_token`).
2. Valid SSH key name in `main.tf`.
3. `terraform plan` succeeds (after `terraform init`).
4. Provision (workflow apply=true OR `make provision`) then SSH & run `nvidia-smi` (or `lsblk`).

### Lite Steps (Adds 3 Checks)
Super‑Lite plus:
5. `pip install -r requirements.txt` (or rely on CI) – watch for conflicts.
6. `make syntax` (fail fast on Ansible syntax).
7. Choose sensible Ansible flags (keep `migrate_root=false` unless testing).

### Full Steps (Comprehensive)
Lite plus all sections in this document (network reachability, post‑provision validation, artifacts, cost plan, troubleshooting pre‑checks, sign‑off section).

### Risk / Trade‑Off Matrix
| Risk Area | Super‑Lite | Lite | Full |
|-----------|------------|------|------|
| Immediate failure detection (syntax/config) | Medium (may fail mid‑run) | Low | Very Low |
| Hidden network/download issues | High | Medium | Low |
| Security misconfiguration (wrong key) | Low (still checked) | Low | Very Low |
| Cost leakage (forgotten host) | Medium | Medium | Low (explicit plan) |
| Reproducibility / audit trail | Low | Medium | High |
| Confidence in complex changes (root migration) | Unsafe | Not Recommended | Required |
| Time to first feedback | Fastest | Moderate | Slowest |

### Escalation Guidance
| Situation | Minimum Tier | Notes |
|-----------|--------------|-------|
| Quick PR sanity | Super‑Lite | Use preview env (#15) later. |
| New role logic test | Lite | Add idempotency check if role is stateful. |
| Root filesystem migration | Full | Collect snapshots & artifacts. |
| Introducing monitoring exporters | Lite → Full | Finish with Full once stable. |
| Preparing release / README update | Full | Ensures docs reflect reality. |

---

---
## 0. Quick Summary (TL;DR)
1. Create / verify Hetzner Cloud API token → set secret `HCLOUD_TOKEN` (CI) or export `TF_VAR_hcloud_token` (local).
2. Ensure a valid SSH public key is registered in Hetzner Cloud and referenced in `main.tf` (or implement Issue #6 first).
3. (Optional) Adjust variables (`server_image`, Ansible extra vars).
4. Run plan (workflow with apply=false OR `make terraform-plan`).
5. Apply + provision (apply=true OR `make provision`).
6. SSH validate, review Ansible recap, decide on destroy schedule.

---
## 1. Secrets & Credentials
| Item | Requirement | How to Verify | Notes |
|------|-------------|---------------|-------|
| Hetzner Cloud Token | Present | In GitHub: Settings → Secrets → Actions → `HCLOUD_TOKEN` | Export locally: `echo $Env:TF_VAR_hcloud_token` (PowerShell) |
| SSH Private Key (local) | Exists & permissions 600-ish | `ls -l ~/.ssh/id_rsa` | Never commit private key. |
| SSH Public Key in Hetzner | Added & named | Hetzner Cloud Console → Security → SSH Keys | Must match `ssh_keys` value in `main.tf` until Issue #6 done. |

### Optional / Future
- Vault / Ansible sensitive vars (root migration toggles) – currently simple booleans.
- Separate token for Robot API (if later used).

---
## 2. Repository State
| Check | Command / Action | Pass Criteria |
|-------|------------------|---------------|
| Branch clean | `git status` | No uncommitted critical changes prior to run (state file changes will occur after). |
| Terraform files valid | `terraform validate` | No errors. |
| Ansible play syntax | `make syntax` | No fatal errors. |
| Requirements installed (local) | `pip install -r requirements.txt` | Installs without version conflict warnings. |

---
## 3. Terraform Configuration
| Element | Default / Current | Action Needed? | Notes |
|---------|-------------------|----------------|-------|
| Server name | `raid10-server` | Usually OK | Change if parallel environments needed. |
| Server type | `cpx31` | Validate capacity | Must meet disk / GPU needs (update as required). |
| Image | `ubuntu-24.04` | Adjust if needed | Controlled by `var.server_image`. |
| Location | `nbg1` | Optional change | Choose closest region. |
| SSH keys | `"your_ssh_key_name"` | MUST replace | Name must exist in Hetzner Cloud. |
| Output `server_ip` | Provided | Used by dynamic inventory | Do not remove (workflow depends on it). |

Optional future (Issue #10 & #6): labels & managed keys.

---
## 4. Ansible Configuration
| Aspect | Default | How to Override | Notes |
|--------|---------|-----------------|-------|
| Hosts group | All (dynamic single host) | N/A | Inventory generated: `inventory.generated.ini`. |
| Roles executed | raid_lvm, desktop, nvidia, dcv, parsec, tuning, gpu_monitoring (conditional), root_migration (conditional) | `EXTRA` env or `-e` flags | Example: `EXTRA='-e migrate_root=true enable_gpu_monitoring=false'`. |
| Root migration | `migrate_root=false` | `-e migrate_root=true` | Potentially disruptive – ensure validation. |
| GPU monitoring | `enable_gpu_monitoring=true` | `-e enable_gpu_monitoring=false` | Disables monitoring stack pieces. |

---
## 5. Network & Download Reachability
| Component | URL / Port | Verify | Failure Impact |
|-----------|-----------|--------|----------------|
| NICE DCV tarball | `https://d1uj6qtbmh3dt5.cloudfront.net/...` | `curl -I <url>` | DCV role fails. |
| Parsec .deb | `https://builds.parsec.app/package/parsec-linux.deb` | `curl -I` | Parsec role fails. |
| APT repos | 80/443 outbound | Run sample `apt update` | General provisioning fails. |
| SSH inbound | Port 22 | Workflow waits via TCP check | Provision cannot continue if blocked. |

---
## 6. Local Execution Path (Manual Provision)
```powershell
# PowerShell (Windows)
$Env:TF_VAR_hcloud_token = '<YOUR_HCLOUD_TOKEN>'
# (Edit main.tf ssh_keys beforehand)
make terraform-plan
make provision EXTRA='-e migrate_root=false enable_gpu_monitoring=true'
```
Outputs:
- `inventory.generated.ini` created
- Ansible verbose log streamed to console

---
## 7. GitHub Actions Workflow Path
Workflow: `Provision RAID Workstation` → Run workflow.
| Input | Suggested First Run | Production Run |
|-------|---------------------|----------------|
| apply | false (plan only) | true |
| migrate_root | false | false/true (explicit decision) |
| enable_gpu_monitoring | true | As needed |

Validation Steps in UI:
1. Confirm Terraform Init & Plan success.
2. If applying: Ensure Apply finishes without error.
3. `Capture server IP` step exposes `server_ip`.
4. Dynamic inventory step shows IP in log.
5. Ansible tasks all reach `ok/changed` without `failed`.
6. Artifact (if added later) or logs accessible.

---
## 8. Post‑Provision Validation
| Check | Command | Expected |
|-------|---------|----------|
| SSH connectivity | `ssh root@<server_ip>` | Login prompt / success. |
| RAID device | `lsblk` or `cat /proc/mdstat` | md device present (`raid10`). |
| LVM volumes | `lvs` | `lv_os`, `lv_data` exist. |
| NVIDIA driver | `nvidia-smi` | Driver + GPU listed. |
| DCV status | `systemctl status dcvserver` | Active (if role ran). |
| Parsec service | `systemctl status parsecd` | Active (if role ran). |
| Monitoring exporter | `systemctl status node_exporter` (future) | Active when enabled. |

---
## 9. Troubleshooting Quick Table
| Symptom | Likely Cause | Resolution |
|---------|--------------|-----------|
| Terraform plan fails: SSH key not found | Placeholder name unchanged | Replace with real key name or implement Issue #6. |
| Workflow no `server_ip` | Apply skipped or failed | Set apply=true OR review apply error logs. |
| Ansible SSH unreachable early | Server not ready / firewall | Retry manually after a minute; verify server creation. |
| DCV download failure | CDN blocked / URL change | Update variables (dcv_version / URL) or retry. |
| Parsec install fails (hash mismatch) | Upstream package update | Fetch current .deb and adjust role checksum (if enforced). |
| RAID tasks fail | NVMe device names mismatch | Adjust `nvme_devices` list in play vars. |

---
## 10. Cost & Lifecycle Considerations
| Action | Recommendation |
|--------|---------------|
| After tests | Manually run `terraform destroy` locally OR remove via future destroy workflow (Issue #8). |
| Parallel envs | Rename server & (future) apply labels (Issue #10). |
| Idle host cleanup | Track creation timestamp; schedule destroy within 24h if ephemeral. |

---
## 11. Suggested Next Enhancements (Cross‑Referenced)
| Area | Issue | Benefit |
|------|-------|---------|
| Managed SSH Keys | #6 | Removes manual key prerequisite. |
| Provisioning Recap JSON | #7 | Structured reporting / metrics. |
| Auto Destroy | #8 | Cost control. |
| Delegated Molecule | #9 | Real-host test safety. |
| Resource Labels | #10 | Lifecycle mgmt. |
| Observability Dashboard | #11 | Visual health. |
| Remote Control | #12 | Operational convenience. |
| Pinned Dependencies | #13 | Reproducibility. |
| README Quickstart | #14 | Onboarding clarity. |
| Preview Environments | #15 | PR validation. |

---
## 12. Sign‑Off Checklist (Mark All Before Production Use)
- [ ] Token configured (secret + local env if needed)
- [ ] SSH key name valid in `main.tf`
- [ ] Terraform plan succeeded
- [ ] Ansible syntax check passes
- [ ] External downloads reachable
- [ ] Decide on root migration flag
- [ ] Run plan-only workflow (apply=false)
- [ ] Run apply workflow or local provision
- [ ] Post-provision validation items pass
- [ ] Destroy schedule or policy defined

---
## 13. Document Maintenance
Keep this checklist updated when:
- Variables change
- New roles added / removed
- Issues (#6–#15) implemented altering prerequisites

Add a CHANGELOG line referencing modifications to this file for traceability.

---
*Version: 2025-08-09 initial draft*
*Tiered model added: 2025-08-09*
