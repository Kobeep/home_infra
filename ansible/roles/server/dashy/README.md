# Ansible Role: Dashy

Deploy Dashy dashboard to a K3S Kubernetes cluster.

## Requirements

- K3S cluster running
- kubectl configured
- python3-kubernetes package installed

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

```yaml
dashy_namespace: monitoring
dashy_replicas: 1
dashy_image: "lissy93/dashy:latest"
dashy_host: dashy.kobeeq.eu
dashy_title: "Home Services"
dashy_node_port: 30001
```

## Dependencies

None.

## Example Playbook

```yaml
- hosts: servers
  roles:
    - role: server/dashy
      vars:
        dashy_host: dashy.example.com
        dashy_title: "My Dashboard"
```

## License

MIT

## Author Information

Created by Jakub Pospieszny
