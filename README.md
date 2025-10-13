# Home Infrastructure

[![CI GitOps](https://github.com/Kobeep/Home_infra/actions/workflows/gitops-validation.yml/badge.svg)](https://github.com/Kobeep/Home_infra/actions/workflows/gitops-validation.yml)

Automated home lab infrastructure using Ansible, k3d, and GitOps with ArgoCD.

## 🚀 Two Deployment Options

### Option 1: GitOps with k3d + ArgoCD (Recommended for new setups)

Modern cloud-native approach with GitOps principles, multi-environment support, and declarative infrastructure.

**Features:**
- ✅ GitOps workflow (infrastructure as code)
- ✅ Multi-environment (develop + prod)
- ✅ ArgoCD for continuous deployment
- ✅ k3d clusters (k3s in Docker)
- ✅ Automated setup with Ansible

```bash
# Quick start with Ansible
cd ansible
ansible-playbook playbooks/server_gitops.yml -i inventories/prod/hosts.yml

# See detailed instructions
cat gitops/GETTING_STARTED.md
```

📖 **[GitOps Documentation](gitops/README.md)** | 📝 **[Getting Started Guide](gitops/GETTING_STARTED.md)** | 📋 **[Cheat Sheet](gitops/CHEATSHEET.md)**

### Option 2: Traditional Ansible + K3S

Classic approach with direct Ansible deployment to native K3S cluster.

```bash
# 1. Clone repository
git clone https://github.com/Kobeep/Home_infra.git
cd Home_infra/ansible

# 2. Configure inventory
# Edit inventories/prod/hosts.yml with your server details

# 3. Create vault file with secrets
# ansible/playbooks/group_vars/all/vault.yml should contain:
# - vault_grafana_admin_password
# - vault_influxdb_admin_password
# - vault_jenkins_slave_secret
# - vault_openai_api_key
# - vault_google_api_key

# 4. Run playbook
ansible-playbook playbooks/server.yml \
  -i inventories/prod/hosts.yml \
  --vault-password-file ~/.vault_pass.txt
```

## What Gets Deployed

The infrastructure deploys:

- **K3S/k3d** - Lightweight Kubernetes
- **ArgoCD** - GitOps continuous delivery (GitOps mode only)
- **Jenkins** - CI/CD server
- **Home Assistant** - Home automation
- **Grafana** - Monitoring dashboards
- **Prometheus** - Metrics collection
- **InfluxDB** - Time-series database
- **Dashy** - Service dashboard
- **AdGuard** - DNS ad blocker
- **OpenWebUI** - AI interface
- **Grocy** - Inventory management

## Configuration

All roles use variables from `defaults/main.yml`. Override in your playbook or inventory:

```yaml
# Example: Custom Grafana configuration
grafana_storage_size: "10Gi"
grafana_host: "grafana.example.com"
```

## Jenkins Pipelines

Automated deployment and backup pipelines are available in:

- `Jenkinsfile` - Linux deployments
- `windows/Jenkinsfile` - Windows deployments
- `jf/Jenkinsfile` - Configuration backups
- `restore_conf/Jenkinsfile` - Configuration restore
- `dsl_script/Jenkinsfile` - Main orchestrator

## License

MIT
