import os
import testinfra.utils.ansible_runner

# Uses delegated inventory produced by Molecule
test_host = testinfra.utils.ansible_runner.AnsibleRunner(
    os.environ.get("MOLECULE_INVENTORY_FILE")
).get_host("all")


def test_node_exporter_binary_present():
    f = test_host.file("/usr/local/bin/node_exporter")
    assert f.exists
    assert f.mode & 0o111, "node_exporter not executable"


def test_node_exporter_service_running():
    svc = test_host.service("node_exporter")
    # For delegated, service module support depends on systemd presence
    assert svc.is_running, "node_exporter service not running"


def test_gpu_metrics_timer_installed():
    timer = test_host.file("/etc/systemd/system/gpu-metrics.timer")
    assert timer.exists


def test_textfile_directory():
    d = test_host.file("/var/lib/node_exporter")
    assert d.is_directory
    assert d.user in ("nodeexp", "root")
