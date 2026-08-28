Home Infra — infrastructure repository
=====================================

This README provides a concise, practical guide to run and maintain the infrastructure managed by this repository.

Key principles
- **Decoupled Architecture**: K3s cluster provisioning and node setup (`provision-cluster.yml`) are completely separated from application and platform service deployments (`deploy-apps.yml`).
- **Modular Roles**: Each platform service (`harbor`, `vault`, `jenkins`) and application workload (`adguard`, `dashy`, `home_assistant`, `infra_api`, `monitoring`, `opengrok`) is implemented as an independent Ansible role.
- **Ansible Orchestration**: Ansible handles configuration, templating, permissions, and deployment execution.
- Global variables live in `ansible/group_vars/all.yml`.

Requirements
- Controller: Python 3, Ansible (compatible version), curl, ripgrep (`rg`) recommended for scans.
- Target hosts: standard tooling as required (curl, openssl, docker, kubectl/helm when applicable).

Repository layout (selected)
- `ansible/` — playbooks, inventory, roles, and `group_vars`
  - `playbooks/provision-cluster.yml` — K3s cluster installation & core infrastructure controllers
  - `playbooks/deploy-apps.yml` — Application and platform service deployments
  - `playbooks/full-setup.yml` / `site.yml` — Master entrypoint running cluster provisioning and app deployments
  - `playbooks/apps/` — Targeted single-service deployment playbooks (`deploy-jenkins.yml`, `deploy-harbor.yml`, etc.)
- `ansible/roles/` — Modular Ansible roles (`k3s`, `ingress_nginx`, `cert_manager`, `external_secrets`, `harbor`, `vault`, `jenkins`, etc.)
- `ansible/scripts/` — bash scripts for procedural operations
- `k8s/` — Kubernetes manifests, kustomize/Helm templates

Quick start (Ansible Execution Options)

1) **Full Provisioning & Deployment** (Complete setup):
```bash
ansible-playbook -i ansible/inventory.yml ansible/playbooks/full-setup.yml
```

2) **Provision K3s Cluster & Core Controllers Only**:
```bash
ansible-playbook -i ansible/inventory.yml ansible/playbooks/provision-cluster.yml
```

3) **Deploy/Update Applications Only**:
```bash
ansible-playbook -i ansible/inventory.yml ansible/playbooks/deploy-apps.yml
```

4) **Target a Specific Service**:
```bash
# Deploy only Jenkins
ansible-playbook -i ansible/inventory.yml ansible/playbooks/apps/deploy-jenkins.yml

# Or using Ansible tags:
ansible-playbook -i ansible/inventory.yml ansible/playbooks/deploy-apps.yml --tags harbor
```

5) **Syntax Check**:
```bash
ansible-playbook -i ansible/inventory.yml ansible/playbooks/full-setup.yml --syntax-check
ansible-playbook -i ansible/inventory.yml ansible/playbooks/provision-cluster.yml --syntax-check
ansible-playbook -i ansible/inventory.yml ansible/playbooks/deploy-apps.yml --syntax-check
```

Important scripts (selected)
- `ansible/scripts/install_k3s.sh` — install k3s (idempotent where possible)
- `ansible/scripts/install_kubectl.sh` — install `kubectl`
- `ansible/scripts/install_helm.sh` — install `helm`
- `ansible/scripts/cert_manager_install.sh` — add repo and install cert-manager
- `ansible/scripts/create_image_pull_secret.sh` — create or apply docker-registry secret
- `ansible/scripts/attach_imagepullsecret.sh` — attach imagePullSecret to `default` ServiceAccount
- `ansible/scripts/apply_kustomize.sh` — `kubectl apply -k <root>` wrapper
- `ansible/scripts/bootstrap_harbor.sh` — bootstrap Harbor project and user
- `ansible/scripts/docker_compose_*.sh` — `build|pull|up|ps` wrappers for docker-compose

Variables and secrets
- Edit non-sensitive defaults in `ansible/group_vars/all.yml` (paths, hostnames, chart versions).
- Keep secrets (tokens, passwords) out of the repository — use a secure store or an encrypted file such as `ansible/env.cfg` (excluded/ignored) or an external secret manager.

Idempotency and testing
- Start with `ansible-playbook --check` for critical playbooks.
- For an idempotency check, run a playbook twice (without `--check`) — the second run should report `ok` for previously applied tasks (no `changed`).
