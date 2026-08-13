
Home Infra — infrastructure repository
=====================================

This README provides a concise, practical guide to run and maintain the infrastructure managed by this repository.

Key principles
- Ansible orchestrates configuration, file copies and permissions.
- Procedural shell actions are implemented as bash scripts in `ansible/scripts/` (idempotent where possible). Scripts emit errors and warnings in the format: "INFO =>: **...**".
- Global variables live in `ansible/group_vars/all.yml`; each role provides sensible defaults in `ansible/roles/*/defaults/main.yml`.

Requirements
- Controller: Python 3, Ansible (compatible version), curl, ripgrep (`rg`) recommended for scans.
- Target hosts: standard tooling as required (curl, openssl, docker, kubectl/helm when applicable).

Repository layout (selected)
- `ansible/` — playbooks, inventory and `group_vars`
- `ansible/roles/` — Ansible roles with defaults in `defaults/`
- `ansible/scripts/` — bash scripts for procedural operations (callable from playbooks or run manually)
- `k8s/` — Kubernetes manifests, kustomize/Helm templates

Quick start (dry-run)
1) Search for inline shell/command/raw (should be none):
```bash
rg --hidden -n "(^|\\s)(shell:|command:|raw:)" || true
```
2) Syntax check an important playbook, for example:
```bash
ansible-playbook -i ansible/inventory.yml ansible/playbooks/full-setup.yml --syntax-check
```
3) Example check-run (no changes applied):
```bash
ansible-playbook -i ansible/inventory.yml ansible/playbooks/full-setup.yml --check --diff
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

Run scripts manually
1) Make scripts executable:
```bash
chmod +x ansible/scripts/*.sh
```
2) Example test run (update helm repos):
```bash
bash ansible/scripts/helm_repo_update.sh stable https://charts.helm.sh/stable
```

Variables and secrets
- Edit non-sensitive defaults in `ansible/group_vars/all.yml` (paths, hostnames, chart versions).
- Keep secrets (tokens, passwords) out of the repository — use a secure store or an encrypted file such as `ansible/env.cfg` (excluded/ignored) or an external secret manager.

Idempotency and testing
- Start with `ansible-playbook --check` for critical playbooks.
- For an idempotency check, run a playbook twice (without `--check`) — the second run should report `ok` for previously applied tasks (no `changed`).
- I can add an automated idempotency script that performs two runs and reports any differences — tell me if you want it.

Next steps and contribution
- Keep procedural logic in `ansible/scripts/` and prefer Ansible modules for resource management (files, packages, services).
- If you want, I will add an automated idempotency runner and a short CONTRIBUTING / USAGE section per playbook.

If you want the idempotency runner created now, reply: "yes".
