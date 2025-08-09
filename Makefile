PYTHON ?= python
PLAYBOOK = ubuntu-cinnamon/workstation.yml
INVENTORY = inventory.ini
TAGS ?=
EXTRA ?=

ANSIBLE_PLAYBOOK = $(PYTHON) -m ansible.playbook

default: help

help:
	@echo 'Common targets:'
	@echo '  make lint              - Run ansible-lint'
	@echo '  make syntax            - Ansible syntax check'
	@echo '  make list-tasks        - List tasks in workstation playbook'
	@echo '  make dry-run           - Check mode full play'
	@echo '  make run-subset TAGS=dcv,parsec,gpu_monitoring - Run subset (real)'
	@echo '  make idempotency-subset TAGS=dcv,parsec,gpu_monitoring - Run twice, expect 0 changes second run'
	@echo '  make molecule ROLE=name - Run molecule test for role (delegated scenario placeholder)'
	@echo '  make molecule-delegated ROLE=gpu_monitoring TARGET_HOST=ip [TARGET_USER=root SSH_KEY=~/.ssh/id_rsa]'
	@echo '  make molecule-delegated ROLE=gpu_monitoring TARGET_HOST=ip [TARGET_USER=root SSH_KEY=~/.ssh/id_rsa]' 

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

# Placeholder for molecule delegated scenario (not yet implemented).
molecule:
	@if [ -z "$(ROLE)" ]; then echo 'Usage: make molecule ROLE=role_name'; exit 1; fi
	@echo 'Molecule delegated scenario for $(ROLE) not yet implemented.'

molecule-delegated:
	@if [ -z "$(ROLE)" ]; then echo 'Usage: make molecule-delegated ROLE=role_name TARGET_HOST=host'; exit 1; fi
	@if [ -z "$(TARGET_HOST)" ]; then echo 'TARGET_HOST env/var required'; exit 1; fi
	TARGET_USER=${TARGET_USER:-root} SSH_KEY=${SSH_KEY:-$$HOME/.ssh/id_rsa} \
		molecule -s delegated -d delegated -c ubuntu-cinnamon/roles/$(ROLE)/molecule/delegated/molecule.yml test

molecule-delegated:
	@if [ -z "$(ROLE)" ]; then echo 'Usage: make molecule-delegated ROLE=role_name TARGET_HOST=host'; exit 1; fi
	@if [ -z "$(TARGET_HOST)" ]; then echo 'TARGET_HOST env/var required'; exit 1; fi
	TARGET_USER=${TARGET_USER:-root} SSH_KEY=${SSH_KEY:-$$HOME/.ssh/id_rsa} \
		molecule -s delegated -d delegated -c ubuntu-cinnamon/roles/$(ROLE)/molecule/delegated/molecule.yml test

.PHONY: help lint syntax list-tasks dry-run run-subset idempotency-subset molecule
