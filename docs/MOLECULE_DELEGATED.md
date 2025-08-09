# Molecule Delegated Scenario (gpu_monitoring Role)

This repo includes a delegated Molecule scenario for the `gpu_monitoring` role to validate:
- Installation of node_exporter
- GPU metrics timer + textfile directory
- Idempotency (second converge = 0 changes)

## Prerequisites
Target host (VM) must have:
- Python available for Ansible
- SSH access (key-based)
- Sudo/root privileges

Environment variables (or Make vars):
- `TARGET_HOST` (IP or DNS)
- `TARGET_USER` (default: root)
- `SSH_KEY` path to private key (default: ~/.ssh/id_rsa)

## Run
```
pip install -r requirements.txt
make molecule-delegated ROLE=gpu_monitoring TARGET_HOST=192.0.2.10
```

Equivalent raw command:
```
TARGET_HOST=192.0.2.10 molecule -s delegated -d delegated -c ubuntu-cinnamon/roles/gpu_monitoring/molecule/delegated/molecule.yml test
```

Test sequence executed: converge -> idempotence -> verify.

## Expected Outcomes
- First converge: changes applied
- Idempotence: 0 changed tasks
- Verify: all tests pass (`node_exporter` running, files exist)

## Troubleshooting
| Symptom | Cause | Fix |
|---------|-------|-----|
| SSH failure | Wrong key/user | Export correct `SSH_KEY`, `TARGET_USER` |
| Idempotence fails | Non-idempotent task (e.g., unguarded copy) | Add `creates:` or conditionals |
| Service test fails | Systemd not available | Use a full VM (not minimal container) |

Extend by duplicating this scenario structure under other roles (desktop, dcv, parsec) as needed.
