# Home Infrastructure

Fully automated home lab infrastructure using Ansible and K3S. Zero configuration needed - just run one command.

## Quick Start

```bash
# 1. Clone repository
git clone https://github.com/Kobeep/Home_infra.git
cd home_infra

# 2. Configure your server IP
nano ansible/inventory.yml
# Change ansible_host to your server IP

# 3. Deploy everything
./deploy.sh
```

That's it! All services will be automatically deployed and accessible on your local network.

## What Gets Deployed

| Service | URL Path | Description |
|---------|----------|-------------|
| **Dashy** | `/` | Central dashboard for all services |
| **Jenkins** | `/jenkins` | CI/CD automation |
| **Home Assistant** | `/homeassistant` | Smart home platform |
| **Grafana** | `/grafana` | Monitoring dashboards |
| **Prometheus** | `/prometheus` | Metrics collection |
| **AdGuard** | `/adguard` | DNS ad blocker |
| **OpenWebUI** | `/openwebui` | AI chat interface |
| **Grocy** | `/grocy` | Grocery management |
| **InfluxDB** | `/influxdb` | Time-series database |
| **HashiCorp Vault** | `vault.home.local` | Secrets Management |
| **Cloud DR Backup** | CronJob | Automated backups to Oracle Cloud |

Access services natively via `http://<service>.home.local` if your DNS is configured, or explicitly via the IP mappings in Ingress.

Example: `http://192.168.0.100/jenkins`

## Architecture

```
Server (Clean Ubuntu/Debian)
    ↓
Ansible installs:
  - Base packages
  - K3S (Lightweight Kubernetes)
  - kubectl & helm
  - Ingress NGINX Controller
    ↓
Ansible deploys all apps to K3S:
  - Each app in its own namespace
  - Persistent storage for data
  - ClusterIP services (internal only)
  - Ingress rules for HTTP routing
    ↓
Access via Ingress NGINX → http://YOUR_IP/<service>
```

## Features

✅ **Single Entry Point** - All services through Ingress (ports 80/443)
✅ **Path-based Routing** - Clean URLs like `/jenkins`, `/grafana`
✅ **No NodePort Exposure** - Increased security with ClusterIP services
✅ **Health Checks** - Automatic service monitoring in Dashy
✅ **Zero Configuration** - Ansible handles everything
✅ **Production Ready** - Standard Kubernetes patterns

## Requirements

- Fresh Ubuntu 20.04+ or Debian 11+ server
- SSH access to server
- Ansible installed locally (script auto-installs if missing)
- Local network access to server

## Manual Deployment

If you prefer manual control:

```bash
ansible-playbook \
  -i ansible/inventory.yml \
  ansible/playbooks/full-setup.yml
```

## Remote Access

Access your cluster from any computer on your local network:

```bash
# Copy kubeconfig from server
scp user@192.168.0.100:/etc/rancher/k3s/k3s.yaml ~/.kube/homelab-config

# Edit server address (change 127.0.0.1 to your server IP)
nano ~/.kube/homelab-config

# Use kubectl remotely
export KUBECONFIG=~/.kube/homelab-config
kubectl get pods -A

# Or use k9s for terminal UI
k9View Ingress rules
kubectl get ingress -A

# Restart a service
kubectl rollout restart deployment/home-assistant -n home-assistant

# View logs
kubectl logs -f deployment/grafana -n monitoring

# Get Jenkins initial password
kubectl exec -n jenkins -it deployment/jenkins -- \
  cat /var/jenkins_home/secrets/initialAdminPassword

# Check Ingress NGINX status
kubectl get pods -n ingress-nginx
kubectl get pods --all-namespaces

# Restart a service
kubectl rollout restart deployment/home-assistant -n home-assistant

# View logs
kubectl logs -f deployment/grafana -n monitoring

  cat /var/jenkins_home/secrets/initialAdminPassword
```

## HashiCorp Vault & Secrets Management

This lab comes with **HashiCorp Vault** and **External Secrets Operator (ESO)** pre-installed. All manual secrets management should be handled through Vault instead of plain Kubernetes Secrets.

### 1. Initializing Vault
Vault starts "sealed" and must be initialized on the first run.
```bash
# Exec into the vault pod
kubectl exec -it vault-0 -n vault -- /bin/sh

# Initialize vault (Save the Unseal Keys and Root Token somewhere safe!)
vault operator init

# Unseal Vault (Run this 3 times with 3 different keys from the init step)
vault operator unseal
```

### 2. Accessing Vault UI
Vault is accessible within your network at `http://vault.home.local` (ensure your DNS router / Adguard redirects `*.home.local` to your server IP). Login using the Root Token generated above.

### 3. Using External Secrets
External Secrets fetches secrets from Vault automatically. To connect ESO to your unsealed Vault:
1. Create a `SecretStore` in Kubernetes pointing to Vault.
2. In Vault, create a KVv2 Secret Engine.
3. Use `ExternalSecret` manifests in your apps rather than raw `Secret`. ESO will auto-generate the Kubernetes `Secret` containing your Vault payload!

## Structure

```
home_infra/
├── k8s/                    # Kubernetes manifests
│   ├── ingress-nginx.yaml # Ingress routing rules
│   ├── jenkins/           # CI/CD
│   ├── dashy/             # Dashboard
│   ├── home-assistant/    # Smart home
│   ├── grafana/           # Monitoring
│   ├── prometheus/        # Metrics
│   ├── influxdb/          # Database
│   ├── adguard/           # DNS
│   ├── openwebui/         # AI
│   ├── grocy/             # Inventory
│   └── backup/            # Cloud DR Orchestrator
├── ansible/
│   ├── inventory.yml      # Server configuration
│   └── playbooks/
│       └── full-setup.yml # Main playbook (includes Ingress)
├── deploy.sh              # One-command deployment
└── troubleshoot.sh        # Debugging helper
```

## Backup System (Cloud DR Orchestrator)

Automated daily backups to Oracle Cloud Free Tier (20GB free storage):

### Setup

1. **Get Oracle Cloud credentials** (Free Tier)
   - Sign up at [oracle.com/cloud/free](https://www.oracle.com/cloud/free/)
   - Create Object Storage bucket
   - Generate API keys

2. **Configure backup secrets**
   ```bash
   nano k8s/backup/secret.yaml
   # Add your Oracle Cloud credentials
   ```

3. **Deploy** (included in main setup)
   ```bash
   kubectl apply -f k8s/backup/
   ```

### Features

- 🗄️ Database backups (PostgreSQL, InfluxDB)
- 📁 File/config backups (Jenkins, K8s configs)
- 🔐 AES-256-GCM encryption
- 📊 Prometheus metrics
- 🕐 Daily automated runs (2 AM)
- 💰 Free (Oracle Cloud Free Tier)

### Manual backup

```bash
kubectl create job --from=cronjob/backup-daily manual-backup-$(date +%s) -n backup
```

### View backup logs

```bash
kubectl logs -n backup -l job-name=backup-daily --tail=100
```
│   ├── adguard/           # DNS
│   ├── openwebui/         # AI
│   └── grocy/             # Inventory
├── ansible/
│   ├── inventory.yml      # Server configuration
│   └── playbooks/
│       └── fare accessed through **Ingress NGINX** on standard HTTP/HTTPS ports (80/443). No need for port numbers in URLs.

**Services use ClusterIP** (internal K8s networking only) for enhanced security. External access is controlled through Ingress routing rules.

Set your router to give your server a static local IP (e.g., 192.168.0.100) for consistent access.

### Example Access URLs
- Dashboard: `http://192.168.0.100/`
- Jenkins: `http://192.168.0.100/jenkins`
- Grafana: `http://192.168.0.100/grafana`

## Network Access

All services use NodePort (30000-32767 range) for local network access. No domain or public IP required.

Set your router to give your server a static local IP (e.g., 192.168.0.100) for consistent access.

## License

MIT
