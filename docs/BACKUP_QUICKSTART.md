# Backup & Restore Quick Start

## 🎯 Quick Commands

### Manual Backup
```bash
cd ~/home-infra/gitops
./scripts/trigger-backup.sh           # Backup production cluster
./scripts/trigger-backup.sh home-develop  # Backup development cluster
```

### Manual Restore
```bash
cd ~/home-infra/gitops
./scripts/restore-pvcs.sh              # Restore to production
CLUSTER_NAME=home-develop ./scripts/restore-pvcs.sh  # Restore to development
```

### Check CronJob Status
```bash
# View CronJob schedule
kubectl get cronjob pvc-backup -n default

# View recent backup jobs
kubectl get jobs -n default -l app=pvc-backup

# View latest backup logs
kubectl logs -n default -l app=pvc-backup --tail=100 -f
```

### Trigger Immediate Backup via CronJob
```bash
kubectl create job --from=cronjob/pvc-backup manual-backup-$(date +%s) -n default
```

### View Backup Archives
```bash
# On the server
ls -lh /var/lib/home-infra/backups/

# Check total size
du -sh /var/lib/home-infra/backups/
```

## 📋 What Gets Backed Up?

- ✅ **Home Assistant** - Full `/config` directory
- ✅ **Dashy** - Dashboard configuration
- ✅ **Grafana** - Dashboards, datasources, plugins
- ✅ **AdGuard Home** - DNS rules and configuration
- ✅ **OpenWebUI** - AI interface data

## ⏰ Automated Backups

- Runs daily at **2:00 AM**
- Keeps last **7 backups**
- Stored in `/var/lib/home-infra/backups/`
- Deployed via ArgoCD (GitOps managed)

## 🔧 Ansible Integration

When deploying via Ansible, backups are automatically restored:

```bash
# Full deployment with automatic restore
ansible-playbook -i inventories/hosts.yml playbooks/server_gitops.yml

# Deploy without restoring backups
ansible-playbook -i inventories/hosts.yml playbooks/server_gitops.yml -e restore_backups=false
```

## 🚨 Disaster Recovery

1. Run Ansible playbook to rebuild infrastructure:
   ```bash
   ansible-playbook -i inventories/hosts.yml playbooks/server_gitops.yml
   ```

2. Ansible automatically:
   - Installs Docker, k3d, kubectl
   - Creates k3d cluster
   - Deploys ArgoCD
   - Syncs all applications
   - **Restores all backups** 🎉

3. Verify services:
   ```bash
   kubectl get pods --all-namespaces
   ```

## 📚 Full Documentation

See [BACKUP_RESTORE.md](BACKUP_RESTORE.md) for complete documentation including:
- Architecture details
- Troubleshooting guide
- Security considerations
- Environment variables
- Migration from Jenkins

## 🆘 Common Issues

### Backup fails with "pod not found"
```bash
# Check if pods are running
kubectl get pods -n home-assistant
kubectl get pods -n dashy
kubectl get pods -n monitoring
kubectl get pods -n adguard
kubectl get pods -n openwebui
```

### Restore times out
```bash
# Increase timeout and retry
MAX_WAIT_PODS=600 ./scripts/restore-pvcs.sh
```

### CronJob not running
```bash
# Check suspension status
kubectl get cronjob pvc-backup -n default

# Enable if suspended
kubectl patch cronjob pvc-backup -n default -p '{"spec":{"suspend":false}}'
```

## 🔗 Related Scripts

- `gitops/scripts/backup-pvcs.sh` - Full backup script
- `gitops/scripts/restore-pvcs.sh` - Full restore script
- `gitops/scripts/trigger-backup.sh` - Quick backup wrapper
- `gitops/apps/backup-cronjob/` - CronJob manifests
