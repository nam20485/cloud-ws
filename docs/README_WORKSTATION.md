# High-Performance Remote Workstation Provisioning

Provision a GPU-accelerated remote workstation with:

1. 4x NVMe RAID10 -> LVM (OS + DATA)  
2. Ubuntu 24.04 Cinnamon desktop  
3. NVIDIA proprietary driver (persistence enabled)  
4. NICE DCV (high quality tuning)  
5. Parsec (low latency high bitrate)  
6. Safe / idempotent automation (reboots only when required)  
7. Optional automated root migration onto RAID10 LVM (disabled by default)  
8. Optional GPU monitoring (Prometheus node_exporter + custom nvidia-smi textfile)

Run:

```bash
ansible-playbook -i inventory.ini ubuntu-cinnamon/workstation.yml
```

Adjust variables at top of `workstation.yml` before first run (device names, versions, bitrates).

Root migration automation: set `migrate_root: true` to copy the current root into the OS LV, install GRUB on each NVMe device, regenerate initramfs & grub, and reboot. A marker file prevents repeats.

GPU monitoring: enabled by default (`enable_gpu_monitoring: true`). Exposes metrics via node_exporter on port 9100 (default). Custom textfile metrics include utilization, memory, temperature, and power.

Test in a disposable environment before production. Back up data drives prior to initial RAID creation.
