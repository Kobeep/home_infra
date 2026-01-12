# Cloud DR Orchestrator Integration

This guide explains how to integrate Cloud DR Orchestrator into home_infra.

## Quick Integration

### 1. Build Docker Image

```bash
cd /path/to/cloud-dr-orchestrator
./build.sh
```

### 2. Load Image into K3S

On your server:
```bash
docker save ghcr.io/kobeep/cloud-dr-orchestrator:latest | \
  sudo k3s ctr images import -
```

Or push to container registry:
```bash
docker login ghcr.io
docker push ghcr.io/kobeep/cloud-dr-orchestrator:latest
```

### 3. Configure Oracle Cloud

Edit `k8s/backup/secret.yaml` with your Oracle Cloud credentials:
- User OCID
- Tenancy OCID
- API Key Fingerprint
- Private Key
- Encryption Key (32 characters)

### 4. Deploy

```bash
kubectl apply -f k8s/backup/
```

## Configuration

### Backup Schedule

Default: Daily at 2 AM

Edit `k8s/backup/cronjob.yaml`:
```yaml
spec:
  schedule: "0 2 * * *"  # Cron format
```

### What Gets Backed Up

Edit `k8s/backup/configmap.yaml`:
- Databases (PostgreSQL, MySQL)
- Files and directories
- K8s configs
- Application data

### Retention Policy

```yaml
retention:
  days: 30           # Keep daily backups for 30 days
  keep_weekly: 4     # Keep 4 weekly backups
  keep_monthly: 6    # Keep 6 monthly backups
```

## Manual Operations

### Trigger Manual Backup

```bash
kubectl create job --from=cronjob/backup-daily manual-backup-$(date +%s) -n backup
```

### View Logs

```bash
# Latest job logs
kubectl logs -n backup -l job-name=backup-daily --tail=100

# All backup jobs
kubectl get jobs -n backup

# Specific job logs
kubectl logs job/backup-daily-12345678 -n backup
```

### Test Configuration

```bash
kubectl exec -it -n backup $(kubectl get pod -n backup -l job-name=backup-daily -o name | head -1) -- /app/orchestrator version
```

## Monitoring

Backup metrics are exposed for Prometheus:
- `backup_duration_seconds` - Backup duration
- `backup_size_bytes` - Backup size
- `backup_success` - Success/failure
- `backup_files_total` - Number of files backed up

Add to Prometheus scrape config in `k8s/prometheus/configmap.yaml`:
```yaml
- job_name: 'backup'
  static_configs:
    - targets: ['backup-service.backup.svc.cluster.local:9090']
```

## Troubleshooting

### Check CronJob Status

```bash
kubectl get cronjobs -n backup
kubectl describe cronjob backup-daily -n backup
```

### View Failed Jobs

```bash
kubectl get jobs -n backup --field-selector status.successful=0
```

### Debug Pod

```bash
kubectl run -it --rm debug --image=ghcr.io/kobeep/cloud-dr-orchestrator:latest --restart=Never -n backup -- sh
```

### Common Issues

1. **Oracle Cloud Auth Failed**
   - Verify credentials in secret.yaml
   - Check API key format (no extra spaces/newlines)

2. **Database Connection Failed**
   - Verify database service names
   - Check network policies
   - Verify database credentials

3. **Storage Full**
   - Increase PVC size in `k8s/backup/pvc.yaml`
   - Clean old backups manually

## Oracle Cloud Free Tier Limits

- ✅ 20GB Object Storage (2 buckets)
- ✅ 50,000 API calls/month
- ✅ 10GB outbound data transfer/month

Perfect for home lab backups!

## Security Notes

- All backups are encrypted with AES-256-GCM
- Encryption keys stored in Kubernetes secrets
- Private keys never leave the cluster
- Use RBAC to limit access to backup namespace

## Updates

To update the backup image:

```bash
cd /path/to/cloud-dr-orchestrator
git pull
./build.sh
docker save ghcr.io/kobeep/cloud-dr-orchestrator:latest | \
  ssh user@server "sudo k3s ctr images import -"
kubectl rollout restart cronjob/backup-daily -n backup
```
