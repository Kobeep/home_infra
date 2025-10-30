# GitOps Backup and Restore System

## Overview

This document describes the backup and restore system for GitOps PVC (Persistent Volume Claim) data in the Home Infrastructure k3d clusters.

## Architecture

The backup system has three main components:

### 1. Manual Backup Script (`gitops/scripts/backup-pvcs.sh`)
- Can be run manually anytime
- Backs up PVC data from running pods
- Commits backups to git repository
- Usage: `./backup-pvcs.sh`

### 2. Automated CronJob (Kubernetes)
- Runs daily at 2 AM
- Deployed via ArgoCD as part of GitOps
- Saves backups to host directory: `/var/lib/home-infra/backups`
- Keeps last 7 daily backups
- Deployed in `gitops/apps/backup-cronjob/`

### 3. Restore Script (`gitops/scripts/restore-pvcs.sh`)
- Restores configurations from git repository to pods
- Integrated with Ansible playbook for automated restore during setup
- Can be run manually anytime
- Usage: `./restore-pvcs.sh`

## Backup Coverage

The following services have their PVC data backed up:

| Service | Namespace | Path | Description |
|---------|-----------|------|-------------|
| Home Assistant | `home-assistant` | `/config` | Full configuration directory |
| Dashy | `dashy` | `/app/public/conf.yml` | Dashboard configuration |
| Grafana | `monitoring` | `/var/lib/grafana` | Dashboards, datasources, settings |
| AdGuard Home | `adguard` | `/opt/adguardhome/work` + `/conf` | DNS filtering rules and config |
| OpenWebUI | `openwebui` | `/app/backend/data` | AI interface data |

## Manual Backup

### Prerequisites
- k3d cluster running
- kubectl configured with proper context
- Pods must be in `Running` state

### Running Manual Backup

```bash
cd ~/home-infra/gitops

# Backup production cluster (default)
./scripts/backup-pvcs.sh

# Backup development cluster
CLUSTER_NAME=home-develop ./scripts/backup-pvcs.sh
```

### Backup Process
1. Script connects to k3d cluster
2. Finds running pods for each service
3. Extracts data via `kubectl exec` + tar
4. Saves to local directories (hass-config/, dashy-config/, etc.)
5. Commits to git with timestamp
6. Optionally pushes to remote repository

### Backup Locations

Backups are stored in the repository under:
```
home_infra/
├── hass-config/          # Home Assistant backup
├── dashy-config/         # Dashy backup
├── grafana-config/       # Grafana backup
├── adguard-config/       # AdGuard backup
└── openwebui-config/     # OpenWebUI backup
```

## Automated Backup (CronJob)

### Configuration

The CronJob is defined in `gitops/apps/backup-cronjob/backup-cronjob.yaml` and includes:

- **ServiceAccount**: `backup-bot` with RBAC permissions
- **ClusterRole**: Allows listing pods and executing commands
- **CronJob**: Runs at 2 AM daily
- **Storage**: Uses hostPath `/var/lib/home-infra/backups`

### Schedule

Default schedule: `0 2 * * *` (2 AM daily)

To change the schedule, edit `gitops/apps/backup-cronjob/backup-cronjob.yaml`:

```yaml
spec:
  schedule: "0 2 * * *"  # Change this cron expression
```

### Viewing CronJob Status

```bash
# Check CronJob
kubectl get cronjob pvc-backup -n default

# List backup jobs
kubectl get jobs -n default -l app=pvc-backup

# View backup pod logs
kubectl logs -n default -l app=pvc-backup --tail=100
```

### Backup Retention

- CronJob keeps last **7 daily backups**
- Older backups are automatically deleted
- Backups are stored as `.tar.gz` archives
- Location: `/var/lib/home-infra/backups/backup_YYYYMMDD_HHMMSS.tar.gz`

### Manual Trigger

To trigger a backup immediately without waiting for schedule:

```bash
kubectl create job --from=cronjob/pvc-backup manual-backup-$(date +%s) -n default
```

## Restore Process

### Automated Restore (Ansible)

When running the `ansible/playbooks/server_gitops.yml` playbook:

1. Cluster is bootstrapped
2. ArgoCD syncs all applications
3. Pods start and become ready
4. **Restore script automatically runs** if backup data exists
5. Services restart with restored configurations

Control restore behavior with Ansible variables:

```bash
# Disable automatic restore
ansible-playbook -i inventories/hosts.yml playbooks/server_gitops.yml -e restore_backups=false

# Force restore even if backups are missing (will skip missing ones)
ansible-playbook -i inventories/hosts.yml playbooks/server_gitops.yml -e restore_backups=true
```

### Manual Restore

```bash
cd ~/home-infra/gitops

# Restore to production cluster (default)
./scripts/restore-pvcs.sh

# Restore to development cluster
CLUSTER_NAME=home-develop ./scripts/restore-pvcs.sh

# Selective restore (disable specific services)
RESTORE_HOME_ASSISTANT=false \
RESTORE_DASHY=true \
RESTORE_GRAFANA=true \
RESTORE_ADGUARD=true \
RESTORE_OPENWEBUI=true \
./scripts/restore-pvcs.sh
```

### Restore Process Details

1. Script verifies cluster connectivity
2. Checks backup data existence
3. Waits for pods to be Running (max 5 minutes per service)
4. Streams tar archive into pod via `kubectl exec`
5. For Dashy: Updates ConfigMap and restarts deployment
6. Generates restore report

### Post-Restore

After restore completes:
- Services may take 1-2 minutes to fully restart
- Check pod logs if services don't come up:
  ```bash
  kubectl logs -n home-assistant -l app=home-assistant
  ```
- Some services may need manual restart:
  ```bash
  kubectl rollout restart deployment/home-assistant -n home-assistant
  ```

## Troubleshooting

### Backup Issues

**Problem**: Pod not found or not running
```
⚠️ Home Assistant pod not found or not running in home-assistant
```

**Solution**: Check pod status
```bash
kubectl get pods -n home-assistant
kubectl describe pod -n home-assistant
```

**Problem**: Permission denied during tar extraction
```
✗ Backup failed for home-assistant/home-assistant-xxx
```

**Solution**: Check pod security context and file permissions

### Restore Issues

**Problem**: Timeout waiting for pod
```
✗ Timeout waiting for pod in home-assistant
```

**Solution**: Increase wait timeout
```bash
MAX_WAIT_PODS=600 ./scripts/restore-pvcs.sh  # Wait 10 minutes instead of 5
```

**Problem**: ConfigMap update fails
```
✗ Failed to update ConfigMap
```

**Solution**: Check ArgoCD sync status, may need manual sync
```bash
kubectl get applications -n argocd
kubectl -n argocd get application dashy-prod -o yaml
```

### CronJob Issues

**Problem**: CronJob not running

Check CronJob suspension status:
```bash
kubectl get cronjob pvc-backup -n default -o yaml | grep suspend
```

If suspended, enable it:
```bash
kubectl patch cronjob pvc-backup -n default -p '{"spec":{"suspend":false}}'
```

**Problem**: Backup job fails

Check job logs:
```bash
kubectl get jobs -n default
kubectl logs -n default job/pvc-backup-<timestamp>
```

**Problem**: Insufficient disk space

Check host storage:
```bash
df -h /var/lib/home-infra/backups
```

Clean old backups manually if needed:
```bash
sudo ls -lh /var/lib/home-infra/backups/
sudo rm /var/lib/home-infra/backups/backup_20240101_*.tar.gz
```

## Migration from Jenkins Pipeline

If you were previously using the Jenkins backup pipeline:

### Differences

| Aspect | Old (Jenkins) | New (GitOps) |
|--------|---------------|--------------|
| Trigger | Jenkins cron | Kubernetes CronJob |
| Namespaces | home, monitoring, default, ai | home-assistant, dashy, monitoring, adguard, openwebui |
| Storage | Git only | Git + host directory archives |
| Execution | SSH + kubectl remotely | Native kubectl in cluster |
| Restore | Jenkins pipeline | Ansible playbook + manual script |

### Migration Steps

1. ✅ Update namespace references (already done in scripts)
2. ✅ Create Kubernetes CronJob (already deployed via ArgoCD)
3. ✅ Integrate restore with Ansible (already added to playbook)
4. **TODO**: Disable old Jenkins pipelines:
   - `jf/Jenkinsfile` (backup)
   - `restore_conf/Jenkinsfile` (restore)
5. **Optional**: Push existing backup directories to git if not already committed

## Environment Variables

### backup-pvcs.sh

- `CLUSTER_NAME` - k3d cluster name (default: `home-prod`)
- `KUBECONFIG` - Path to kubeconfig (default: `~/.kube/config`)
- `BACKUP_BASE_DIR` - Repository root (auto-detected)

### restore-pvcs.sh

- `CLUSTER_NAME` - k3d cluster name (default: `home-prod`)
- `KUBECONFIG` - Path to kubeconfig (default: `~/.kube/config`)
- `BACKUP_BASE_DIR` - Repository root (auto-detected)
- `RESTORE_HOME_ASSISTANT` - Enable/disable HA restore (default: `true`)
- `RESTORE_DASHY` - Enable/disable Dashy restore (default: `true`)
- `RESTORE_GRAFANA` - Enable/disable Grafana restore (default: `true`)
- `RESTORE_ADGUARD` - Enable/disable AdGuard restore (default: `true`)
- `RESTORE_OPENWEBUI` - Enable/disable OpenWebUI restore (default: `true`)
- `MAX_WAIT_PODS` - Pod wait timeout in seconds (default: `300`)

## Security Considerations

### Sensitive Data

Backup directories may contain sensitive information:
- Home Assistant: API tokens, integrations
- Grafana: Datasource credentials, API keys
- AdGuard: DNS filtering rules
- OpenWebUI: User data, API keys

**Recommendations**:
1. Ensure git repository is **private**
2. Use `.gitignore` for sensitive files if needed
3. Encrypt backups if storing externally
4. Restrict access to `/var/lib/home-infra/backups` on host

### RBAC Permissions

The `backup-bot` ServiceAccount has ClusterRole permissions:
- Read pods (get, list)
- Execute commands in pods (pods/exec)

This is required for backup operations but should not be granted to untrusted workloads.

## Best Practices

1. **Test restores regularly** - Don't wait for disaster to test
2. **Monitor CronJob execution** - Check logs weekly
3. **Verify backup sizes** - Sudden size changes may indicate issues
4. **Keep multiple restore points** - Don't rely on single backup
5. **Document custom configurations** - Some settings may need manual steps
6. **Update scripts when adding services** - Add new services to backup coverage

## Examples

### Full Backup and Restore Cycle

```bash
# 1. Manual backup before changes
cd ~/home-infra/gitops
./scripts/backup-pvcs.sh

# 2. Make changes, push to git
git add .
git commit -m "Updated configurations"
git push

# 3. If needed, restore to previous state
./scripts/restore-pvcs.sh
```

### Disaster Recovery

```bash
# 1. Fresh server setup via Ansible
ansible-playbook -i inventories/hosts.yml playbooks/server_gitops.yml

# 2. Ansible automatically:
#    - Installs Docker, k3d, kubectl, helm
#    - Clones repository
#    - Bootstraps cluster
#    - Restores backups

# 3. Verify services are running
kubectl get pods --all-namespaces
```

### Selective Backup Testing

```bash
# Backup only Home Assistant
cd ~/home-infra/gitops
RESTORE_DASHY=false \
RESTORE_GRAFANA=false \
RESTORE_ADGUARD=false \
RESTORE_OPENWEBUI=false \
./scripts/backup-pvcs.sh
```

## Future Enhancements

Potential improvements to consider:

- [ ] Add backup encryption (GPG or age)
- [ ] External backup storage (S3, rsync, etc.)
- [ ] Slack/email notifications on backup failures
- [ ] Incremental backups instead of full copies
- [ ] Backup validation/integrity checks
- [ ] Prometheus metrics for backup monitoring
- [ ] Helm chart for easier CronJob configuration
- [ ] Support for custom backup schedules per service
- [ ] Automatic cleanup of old git commits (keep last N)

## Support

For issues or questions:
1. Check pod logs: `kubectl logs -n <namespace> <pod>`
2. Check CronJob logs: `kubectl logs -n default -l app=pvc-backup`
3. Review ArgoCD application status: `kubectl get applications -n argocd`
4. Check script output for detailed error messages

## Related Files

- `gitops/scripts/backup-pvcs.sh` - Manual backup script
- `gitops/scripts/restore-pvcs.sh` - Manual restore script
- `gitops/apps/backup-cronjob/` - Kubernetes CronJob manifests
- `ansible/playbooks/server_gitops.yml` - Automated deployment with restore
- `jf/Jenkinsfile` - Old Jenkins backup pipeline (deprecated)
- `restore_conf/Jenkinsfile` - Old Jenkins restore pipeline (deprecated)
