# Observability, Telemetry & Tracing Plan

Date: 2025-08-09
Status: Draft (foundation work starting)

## 1. Objectives
Provide fast, low-friction diagnostics for workstation provisioning & runtime services (NVIDIA stack, DCV, Parsec, monitoring) with minimal added cost. Priorities: reproducibility, idempotency evidence, service health signals, and actionable artifacts for remote debugging.

## 2. Current Baseline (As-Is)
| Layer | Current | Gaps |
|-------|--------|------|
| Ansible Output | Human-readable stdout | Not persisted, unstructured, no timing breakdown |
| Role Metrics | gpu_monitoring emits GPU metrics to textfile | Not scraped centrally; no success heartbeat metric |
| System Services | Journald (dcvserver, parsecd, node_exporter) | Not captured/exported; no retention in artifacts |
| CI | Lint/syntax only | No runtime execution, metrics, or idempotency evidence |
| Security | None captured | No Lynis, firewall, fail2ban status artifacts |
| Visualization | None | No Grafana dashboards or Prometheus scrape config |
| Tracing | None | No task-level open telemetry; no script instrumentation |
| Visual Validation | None | No DCV/Parsec screenshot diffs |

## 3. Phased Roadmap

### Phase 1 – Foundation (Fast Wins)
Deliver in small PRs; enable remote reproducibility.
1. Structured Ansible Output
   - Add `ansible.cfg` with `stdout_callback = json` (or community.yaml) & `profile_tasks` plugin.
2. Artifact Layout
   - `.artifacts/<ts>/` with: `ansible.json`, `commit.txt`, `inventory.hash`, `facts.json`, `changes.json`.
3. System Snapshot Task Block
   - Collect: `uname -a`, `lsblk -f`, `df -h`, `lvs/vgs/pvs`, `nvidia-smi`, `systemctl --failed`, `journalctl -u dcvserver -n 200`, `journalctl -u parsecd -n 200`.
4. Metrics & Health Quick Checks
   - Single snapshot of node exporter metrics saved as `metrics.prom`.
   - Extend GPU script to write `gpu_metrics_last_success_timestamp` gauge.
5. Make Targets & Script
   - `make support-bundle` -> tar/gzip latest artifact directory.

### Phase 2 – Metrics & Dashboards
1. Ephemeral Prometheus Script
   - `scripts/ephemeral_prometheus.sh up|down` with custom `prometheus.yml` pointing to target host.
2. Grafana JSON Dashboard
   - Panels: GPU utilization, memory usage, power draw, temperature, service uptime.
3. CI Snapshot
   - CI job to run ephemeral scrape for 30s, then store raw metrics & rendered PNG (grafana image render optional later).

### Phase 3 – Advanced Validation
1. Parsec / DCV Screenshot Diff
   - Xvfb environment + capture script -> baseline PNG + diff.
2. Root Migration Observability
   - Pre/post migration disk maps (`lsblk --json`), fstab snapshot, kernel cmdline, grub config copy.
3. Idempotency Delta Report
   - Parse JSON callback to compute changed tasks list -> `idempotency_report.json`.

### Phase 4 – Tracing & Alerting
1. Lightweight Task Tracing
   - Wrap critical shell scripts (root migration, screenshot capture) with a shim logging start/end/time to structured JSON lines (`trace.log`).
   - Optional: adopt OpenTelemetry shell exporter later.
2. Prometheus Alert Rules (Optional if persistent Prometheus used)
   - Alerts: stale GPU metrics (>2 scrape intervals), node_exporter down, high GPU temperature threshold.
3. Optional Central Log Ingestion
   - Vector or promtail -> Loki for journald units (dcvserver, parsecd, node_exporter).

## 4. Detailed Task Breakdown
| ID | Task | Phase | Done? | Notes |
|----|------|-------|-------|-------|
| O1 | Add ansible.cfg w/ json + profile_tasks | 1 |  |  |
| O2 | Artifact directory creation logic | 1 |  | Wrapper script + timestamp |
| O3 | Capture system snapshot block | 1 |  | Ansible block/tag snapshot |
| O4 | Gather facts & write facts.json | 1 |  | Use `setup` module output |
| O5 | GPU script timestamp metric | 1 |  | Add metric line when success |
| O6 | Support bundle make target | 1 |  | Tar latest artifact dir |
| O7 | Ephemeral Prometheus script | 2 |  | Docker or local binary |
| O8 | Prometheus scrape config template | 2 |  | autodiscover host from env |
| O9 | Grafana GPU dashboard JSON | 2 |  | Minimal panel set |
| O10 | CI metrics snapshot job | 2 |  | Save metrics + commit ref |
| O11 | Screenshot capture script | 3 |  | Xvfb + tool (import/xwd) |
| O12 | Baseline + diff logic | 3 |  | ImageMagick compare |
| O13 | Root migration pre/post collector | 3 |  | Tag root_migration_audit |
| O14 | Idempotency delta parser | 3 |  | Python script parse json |
| O15 | Shell trace wrapper | 4 |  | Write JSONL spans |
| O16 | Alert rules file | 4 |  | Optional gating |
| O17 | Log shipping (Vector/promtail) | 4 |  | Optional late adoption |

## 5. Acceptance Criteria
| Capability | Success Metric |
|------------|----------------|
| Structured run log | JSON file present with all tasks & timings |
| Idempotency evidence | `changes.json` empty on second run subset |
| GPU metrics heartbeat | `gpu_metrics_last_success_timestamp` within 2*interval |
| Support bundle | Single tarball <10MB for typical run |
| Dashboard | GPU util & memory graphs render without manual edit |
| Screenshot diff | Non-zero exit on > configured fuzz delta |

## 6. Security & Compliance Considerations
Exclude secrets: redact inventory sensitive vars when writing bundles. Ensure artifact tar excludes private keys (`.ssh`). Add `.artifacts/**` to `.gitignore` (except pattern for selected sanitized samples if needed).

## 7. Implementation Order Rationale
Foundation first (O1–O6) → enables evidence for all future debugging. Metrics (O7–O10) next for visibility. Advanced (O11–O14) gives richer validation. Tracing/alerting (O15–O17) only if ongoing operational footprint justifies complexity.

## 8. Open Questions
1. Will Prometheus/Grafana be ephemeral only or promoted to persistent service? (Impacts alert rules.)
2. Need multi-host scaling? (Affects labeling strategy.)
3. Preferred artifact retention policy? (Size budgets.)

## 9. Next Immediate Work
Implement O1–O3 in a single PR; O4–O6 in follow-up once baseline validated.

---
Related Docs: `IMPLEMENTATION_PLAN.md`, `MOLECULE_DELEGATED.md`.
