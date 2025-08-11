PYTHON ?= python
PLAYBOOK = ubuntu-cinnamon/workstation.yml
INVENTORY = inventory.ini
TAGS ?=
EXTRA ?=

ANSIBLE_PLAYBOOK = $(PYTHON) -m ansible.playbook

default: help

help:
	@echo 'Common targets:'
	@echo '  make terraform-init    - Terraform init'
	@echo '  make terraform-plan    - Terraform plan'
	@echo '  make terraform-apply   - Terraform apply (creates/changes infrastructure)' 
	@echo '  make terraform-destroy - Terraform destroy (tears down infrastructure)'
	@echo '  make provision         - End-to-end: terraform apply + ansible provisioning'
	@echo '  make lint              - Run ansible-lint'
	@echo '  make syntax            - Ansible syntax check'
	@echo '  make list-tasks        - List tasks in workstation playbook'
	@echo '  make dry-run           - Check mode full play'
	@echo '  make run-subset TAGS=dcv,parsec,gpu_monitoring - Run subset (real)'
	@echo '  make idempotency-subset TAGS=dcv,parsec,gpu_monitoring - Run twice, expect 0 changes second run'
	@echo '  make molecule ROLE=name - Run molecule test for role (delegated scenario placeholder)'
	@echo '  make molecule-delegated ROLE=gpu_monitoring TARGET_HOST=ip [TARGET_USER=root SSH_KEY=~/.ssh/id_rsa]'
	@echo '  make molecule-delegated ROLE=gpu_monitoring TARGET_HOST=ip [TARGET_USER=root SSH_KEY=~/.ssh/id_rsa]' 
	@echo '  make ax102-start HOST=ip [VARIANT=uefi ROOT=120G SWAP=16G WORKSTATION=1]' 
	@echo '  make ax102-dry HOST=ip  - Show plan only'

lint:
	ansible-lint

syntax:
	ansible-playbook --syntax-check $(PLAYBOOK)

list-tasks:
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --list-tasks

dry-run:
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --check -vv $(EXTRA)

run-subset:
	@if [ -z "$(TAGS)" ]; then echo 'Set TAGS=tag1,tag2'; exit 1; fi
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags $(TAGS) -vv $(EXTRA)

idempotency-subset:
	@if [ -z "$(TAGS)" ]; then echo 'Set TAGS=tag1,tag2'; exit 1; fi
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags $(TAGS) -vv $(EXTRA) | tee .idempotency_first.log
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags $(TAGS) -vv $(EXTRA) | tee .idempotency_second.log
	@echo 'Review .idempotency_* logs; second run should report 0 changed.'

# -------------------------------
# Dedicated AX102 one-shot automation wrapper (alpha)
# -------------------------------

AX102_SCRIPT = scripts/ax102_automate.sh

ax102-start:
	@if [ -z "$$HOST" ]; then echo 'Usage: make ax102-start HOST=ip [VARIANT=uefi|bios] [ROOT=100G] [SWAP=8G] [WORKSTATION=1]'; exit 1; fi
	VARIANT=$${VARIANT:-uefi} ROOT_SIZE=$${ROOT:-100G} SWAP_SIZE=$${SWAP:-8G} \
		bash $(AX102_SCRIPT) start --host $$HOST --variant $$VARIANT --host-name $${HOSTNAME_OVERRIDE:-ax102-host} \
		--root-size $$ROOT_SIZE --swap-size $$SWAP_SIZE $$( [ -n "$$WORKSTATION" ] && echo --full-workstation ) $$( [ -n "$$EXTRA" ] && echo --extra-ansible "$$EXTRA" )

ax102-dry:
	@if [ -z "$$HOST" ]; then echo 'Usage: make ax102-dry HOST=ip'; exit 1; fi
	bash $(AX102_SCRIPT) start --host $$HOST --dry-run

# -------------------------------
# Terraform + Provisioning
# Expects environment variable TF_VAR_hcloud_token or HCLOUD_TOKEN (auto-mapped)
# Example:
#   export TF_VAR_hcloud_token="$HCLOUD_TOKEN"
#   make provision EXTRA='-e migrate_root=true'
# -------------------------------

# Map HCLOUD_TOKEN -> TF_VAR_hcloud_token if convenient for users
export TF_VAR_hcloud_token ?= $(HCLOUD_TOKEN)

terraform-init:
	terraform init

terraform-plan: terraform-init
	@if [ -z "$$TF_VAR_hcloud_token" ]; then echo 'Missing TF_VAR_hcloud_token (Hetzner API token)'; exit 1; fi
	terraform plan -out=tfplan

terraform-apply: terraform-init
	@if [ -z "$$TF_VAR_hcloud_token" ]; then echo 'Missing TF_VAR_hcloud_token (Hetzner API token)'; exit 1; fi
	terraform apply -auto-approve

terraform-destroy:
	@if [ -z "$$TF_VAR_hcloud_token" ]; then echo 'Missing TF_VAR_hcloud_token (Hetzner API token)'; exit 1; fi
	terraform destroy -auto-approve

# Full end-to-end: infra + configuration
provision: terraform-apply
	@echo 'Generating dynamic inventory from terraform output...'
	@SERVER_IP=$$(terraform output -raw server_ip); \
	echo "[raid_server]" > inventory.generated.ini; \
	echo "$$SERVER_IP ansible_user=root" >> inventory.generated.ini; \
	echo "Generated inventory.generated.ini:"; cat inventory.generated.ini
	ansible-playbook -i inventory.generated.ini $(PLAYBOOK) -vv $(EXTRA)

# Placeholder for molecule delegated scenario (not yet implemented).
molecule:
	@if [ -z "$(ROLE)" ]; then echo 'Usage: make molecule ROLE=role_name'; exit 1; fi
	@echo 'Molecule delegated scenario for $(ROLE) not yet implemented.'

molecule-delegated:
	@if [ -z "$(ROLE)" ]; then echo 'Usage: make molecule-delegated ROLE=role_name TARGET_HOST=host'; exit 1; fi
	@if [ -z "$(TARGET_HOST)" ]; then echo 'TARGET_HOST env/var required'; exit 1; fi
	TARGET_USER=${TARGET_USER:-root} SSH_KEY=${SSH_KEY:-$$HOME/.ssh/id_rsa} \
		molecule -s delegated -d delegated -c ubuntu-cinnamon/roles/$(ROLE)/molecule/delegated/molecule.yml test

.PHONY: help lint syntax list-tasks dry-run run-subset idempotency-subset molecule
