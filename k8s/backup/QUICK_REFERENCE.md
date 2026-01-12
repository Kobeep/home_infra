# Cloud DR Orchestrator - Quick Reference

## Build & Deploy

```bash
# 1. Build image
cd ~/github/cloud-dr-orchestrator
./build.sh

# 2. Load to server
docker save ghcr.io/kobeep/cloud-dr-orchestrator:latest | \
  ssh user@homelab-server "sudo k3s ctr images import -"

# 3. Configure credentials
nano ~/github/home_infra/k8s/backup/secret.yaml

# 4. Deploy
kubectl apply -f ~/github/home_infra/k8s/backup/
```

## Daily Operations

```bash
# Manual backup NOW
kubectl create job --from=cronjob/backup-daily backup-now-$(date +%s) -n backup

# View recent logs
kubectl logs -n backup -l app=backup --tail=50

# Check backup status
kubectl get jobs -n backup

# List all backups in Oracle Cloud
# (requires OCI CLI or web console)
```

## Configuration Files

| File | Purpose |
|------|---------|
| `k8s/backup/secret.yaml` | Oracle Cloud credentials |
| `k8s/backup/configmap.yaml` | What to backup & retention |
| `k8s/backup/cronjob.yaml` | Schedule (default: 2 AM daily) |

## Monitoring

```bash
# Backup metrics
kubectl port-forward -n backup svc/backup-metrics 9090:9090
curl localhost:9090/metrics | grep backup_

# View all backup jobs
kubectl get jobs -n backup --sort-by=.status.startTime
```

## Troubleshooting

```bash
# Failed job details
kubectl describe job <job-name> -n backup

# Pod logs from failed job
kubectl logs -n backup job/<job-name>

# Test Oracle Cloud connection
kubectl run -it --rm oci-test --image=ghcr.io/kobeep/cloud-dr-orchestrator:latest \
  --restart=Never -n backup -- /app/orchestrator version
```

## Common Tasks

### Change Backup Schedule

Edit `k8s/backup/cronjob.yaml`:
```yaml
spec:
  schedule: "0 3 * * *"  # 3 AM daily
  # schedule: "0 */6 * * *"  # Every 6 hours
  # schedule: "0 2 * * 0"  # Sunday 2 AM only
```

Apply: `kubectl apply -f k8s/backup/cronjob.yaml`

### Add Database to Backup

Edit `k8s/backup/configmap.yaml`:
```yaml
postgres:
  - name: "my-database"
    host: "postgres.namespace.svc.cluster.local"
    port: 5432
    database: "dbname"
    user: "admin"
```

Apply: `kubectl apply -f k8s/backup/configmap.yaml`

### Increase Storage

Edit `k8s/backup/pvc.yaml`:
```yaml
spec:
  resources:
    requests:
      storage: 20Gi  # Was 10Gi
```

Apply: `kubectl apply -f k8s/backup/pvc.yaml`

## Oracle Cloud Free Tier

- 20GB Object Storage
- 50,000 API calls/month
- 10GB outbound transfer/month

Perfect for home lab! No credit card charges.

## Links

- [Full Integration Guide](k8s/backup/INTEGRATION.md)
- [Cloud DR Orchestrator GitHub](https://github.com/Kobeep/cloud-dr-orchestrator)
- [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/)
