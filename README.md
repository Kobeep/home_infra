# Home Infrastructure

This repository contains infrastructure as code for home lab setup including Jenkins pipelines for backup and restore operations.

## Services

The infrastructure includes automated backup and restore for the following services:

- **Home Assistant** - Home automation platform (namespace: `home`)
- **Dashy** - Dashboard application (namespace: `monitoring`) 
- **Grafana** - Monitoring and observability (namespace: `monitoring`)
- **AdGuard Home** - DNS ad blocker (namespace: `default`)
- **OpenWebUI** - Web UI for AI models (namespace: `ai`)

## Backup & Restore Pipelines

- **Config_backup** pipeline: Backs up configurations from all services
- **Deploy_configs** pipeline: Restores configurations to all services

Both pipelines are automatically updated to include the new AdGuard Home and OpenWebUI services.