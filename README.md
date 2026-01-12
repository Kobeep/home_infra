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

| Service | Port | Description |
|---------|------|-------------|
| **Dashy** | 30000 | Central dashboard for all services |
| **Jenkins** | 30080 | CI/CD automation |
| **Home Assistant** | 30123 | Smart home platform |
| **Grafana** | 30300 | Monitoring dashboards |
| **Prometheus** | 30900 | Metrics collection |
| **AdGuard** | 30053 | DNS ad blocker |
| **OpenWebUI** | 30800 | AI chat interface |
| **Grocy** | 30180 | Grocery management |
| **InfluxDB** | 30086 | Time-series database |

Access all services via: `http://YOUR_SERVER_IP:PORT`

## Architecture

```
Server (Clean Ubuntu/Debian)
    ↓
Ansible installs:
  - Base packages
  - K3S (Lightweight Kubernetes)
  - kubectl & helm
    ↓
Ansible deploys all apps to K3S:
  - Each app in its own namespace
  - Persistent storage for data
  - NodePort services for local access
    ↓
Access via Dashy Dashboard
```

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

## Managing Services

```bash
# View all pods
kubectl get pods --all-namespaces

# Restart a service
kubectl rollout restart deployment/home-assistant -n home-assistant

# View logs
kubectl logs -f deployment/grafana -n monitoring

# Get Jenkins initial password
kubectl exec -n jenkins -it deployment/jenkins -- \
  cat /var/jenkins_home/secrets/initialAdminPassword
```

## Structure

```
home_infra/
├── k8s/                    # Kubernetes manifests
│   ├── jenkins/           # CI/CD
│   ├── dashy/             # Dashboard
│   ├── home-assistant/    # Smart home
│   ├── grafana/           # Monitoring
│   ├── prometheus/        # Metrics
│   ├── influxdb/          # Database
│   ├── adguard/           # DNS
│   ├── openwebui/         # AI
│   └── grocy/             # Inventory
├── ansible/
│   ├── inventory.yml      # Server configuration
│   └── playbooks/
│       └── full-setup.yml # Main playbook
└── deploy.sh              # One-command deployment
```

## Network Access

All services use NodePort (30000-32767 range) for local network access. No domain or public IP required.

Set your router to give your server a static local IP (e.g., 192.168.0.100) for consistent access.

## License

MIT
