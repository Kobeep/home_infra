<div align="center">
  <h1 align="center">Home Infrastructure</h1>

  <p align="center">
    Fully automated, GitOps-driven home lab infrastructure deployed via Ansible and K3s.
    <br />
    <br />
    <a href="#about-the-project">About The Project</a>
    ·
    <a href="#project-structure">Project Structure</a>
  </p>

  <p align="center">
    [![Contributors][contributors-shield]][contributors-url]
    [![Forks][forks-shield]][forks-url]
    [![Stargazers][stars-shield]][stars-url]
  </p>

  <p align="center">
   [![Create and publish a Docker image](https://github.com/Kobeep/home_infra/actions/workflows/api-build.yml/badge.svg)](https://github.com/Kobeep/home_infra/actions/workflows/api-build.yml)
    [![Create and publish a Jenkins custom image](https://github.com/Kobeep/home_infra/actions/workflows/jenkins-build.yml/badge.svg)](https://github.com/Kobeep/home_infra/actions/workflows/jenkins-build.yml)
  </p>
</div>

<!-- ABOUT THE PROJECT -->
## About The Project

This repository contains the complete Infrastructure-as-Code (IaC) setup for a modern, self-hosted home lab environment. It utilizes a single-command deployment strategy to provision a lightweight Kubernetes cluster (K3s) on a bare-metal server and automatically deploy a suite of essential home services.

All routing is handled securely via Ingress NGINX without exposing unnecessary NodePorts, and all persistent data is protected by a customized `Retain` storage policy.

### Core Custom Components

In addition to standard open-source tools, this infrastructure features several custom-built components:
* **Custom Home API:** A dedicated backend (`homelab-api`) serving custom logic and integrations for the home environment.
* **Custom Jenkins Image:** A pre-configured, hardened Jenkins image built dynamically via CI pipelines.
* **Automation Binaries/Scripts:** A collection of Python utility scripts (`bin/`) for database management, log cleaning, OS updates, and health monitoring.

### Built With

* [![Kubernetes][Kubernetes-badge]][Kubernetes-url]
* [![Ansible][Ansible-badge]][Ansible-url]
* [![Vault][Vault-badge]][Vault-url]
* [![Python][Python-badge]][Python-url]

<!-- PROJECT STRUCTURE -->
## Project Structure

```text
home_infra/
├── ansible/                      # Server provisioning & cluster bootstrapping
│   ├── group_vars/               # Environment variables
│   ├── playbooks/                # Ansible playbooks (e.g. full-setup.yml)
│   ├── roles/                    # Ansible roles (k3s, dependencies)
│   ├── inventory.yml             # Target server IP configuration
│   └── ansible.cfg               # Ansible runtime config
│
├── bin/                          # Python automation & monitoring scripts
│   ├── clean_orphaned_logs.py    # Log retention management
│   ├── db.py                     # Database utility scripts
│   ├── github.py                 # GitHub integration tasks
│   ├── monitor.py                # System health monitoring
│   └── update_os.py              # Automated host OS updates
├── lib/                          # Python libraries
│   ├── Utils.py                  # Utility functions
│   └── Constants.py              # Constants used in the project
├── homelab-api/                  # Custom Home API backend source code
│   ├── app/                      # Application logic
│   └── Dockerfile                # API container image definition
│
├── k8s/                          # Kubernetes workloads (Kustomize)
│   ├── adguard/                  # DNS & Ad-blocking
│   ├── cert-manager/             # Local CA & TLS certificates
│   ├── dashy/                    # Central home dashboard
│   ├── grafana/                  # Metrics visualization
│   ├── home-assistant/           # Smart home automation
│   ├── influxdb/                 # Time-series database
│   ├── infra-api/                # Custom Home API deployment
│   ├── ingress-nginx/            # HTTP routing controller
│   ├── jenkins/                  # Custom Jenkins CI/CD deployment
│   ├── opengrok/                 # Source code search engine
│   ├── prometheus/               # Cluster monitoring & metrics
│   ├── vault/                    # HashiCorp Vault for Secrets Management
│   ├── local-path-retain.yaml    # Custom StorageClass (Retain policy)
│   └── kustomization.yaml        # Main Kustomize entrypoint
│
├── .github/workflows/            # GitHub Actions pipelines
│   ├── api-build.yml             # Builds & pushes the Home API image
│   └── jenkins-build.yml         # Builds & pushes the custom Jenkins image
│
├── deploy.sh                     # Deployment script wrapper
└── README.md                     # Project documentation
```

<!-- GETTING STARTED -->
## Getting Started

To deploy this infrastructure on your own bare-metal server, follow these steps:

### Prerequisites

* A fresh Ubuntu/Debian server with SSH access.
* Ansible installed on your local control machine.
* SSH RSA Keypair configured for passwordless authentication to your server.

### Deployment

1. **Clone the repository**
   ```bash
   git clone https://github.com/Kobeep/home_infra.git
   cd home_infra
   ```

2. **Configure Authentication & Inventory**
   - Create an RSA SSH token for your server if you haven't already.
   - Edit `ansible/inventory.yml` to specify your server's IP address.
   - Ensure your local machine points to the correct SSH key for that IP (e.g., via `~/.ssh/config` or `ansible_ssh_private_key_file` in ansible config).

3. **Run the Playbook**
   ```bash
   cd ansible/playbooks/
   ansible-playbook full-setup.yml -i ../inventory.yml
   ```

[Kubernetes-badge]: https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white
[Kubernetes-url]: https://kubernetes.io/
[Ansible-badge]: https://img.shields.io/badge/ansible-%231A1918.svg?style=for-the-badge&logo=ansible&logoColor=white
[Ansible-url]: https://www.ansible.com/
[Vault-badge]: https://img.shields.io/badge/Vault-000000?style=for-the-badge&logo=Vault&logoColor=white
[Vault-url]: https://www.vaultproject.io/
[API-badge]: https://github.com/Kobeep/home_infra/actions/workflows/api-build.yml/badge.svg
[API-url]: https://github.com/Kobeep/home_infra/actions/workflows/api-build.yml
[Jenkins-badge]: https://github.com/Kobeep/home_infra/actions/workflows/jenkins-build.yml/badge.svg
[Jenkins-url]: https://github.com/Kobeep/home_infra/actions/workflows/jenkins-build.yml

[contributors-shield]: https://img.shields.io/github/contributors/Kobeep/home_infra.svg?style=for-the-badge
[contributors-url]: https://github.com/Kobeep/home_infra/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/Kobeep/home_infra.svg?style=for-the-badge
[forks-url]: https://github.com/Kobeep/home_infra/network/members
[stars-shield]: https://img.shields.io/github/stars/Kobeep/home_infra.svg?style=for-the-badge
[stars-url]: https://github.com/Kobeep/home_infra/stargazers
[Python-badge]: https://img.shields.io/badge/python-3670A0?style=for-the-badge&logo=python&logoColor=ffdd54
[Python-url]: https://www.python.org/
