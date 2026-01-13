#!/bin/bash
# Troubleshooting script for K3S NodePort access issues

echo "=== K3S Status ==="
sudo systemctl status k3s --no-pager

echo -e "\n=== All Pods ==="
kubectl get pods -A -o wide

echo -e "\n=== All Services ==="
kubectl get svc -A

echo -e "\n=== Check if NodePorts are listening ==="
sudo netstat -tulpn | grep -E ":(30000|30080|30123|30053|30300|30900|30086|30800|30180)" || echo "No NodePorts found listening"

echo -e "\n=== Check iptables NAT rules ==="
sudo iptables -t nat -L -n -v | grep -E "30000|30080|30123|30053|30300|30900|30086|30800|30180"

echo -e "\n=== Network Interfaces ==="
ip addr show

echo -e "\n=== K3S Configuration ==="
cat /etc/systemd/system/k3s.service.env 2>/dev/null || echo "No K3S env file"
ps aux | grep k3s | head -2

echo -e "\n=== Try curl localhost ==="
curl -s http://localhost:30000 -o /dev/null -w "Dashy (30000): HTTP %{http_code}\n" || echo "Failed"
curl -s http://localhost:30080 -o /dev/null -w "Jenkins (30080): HTTP %{http_code}\n" || echo "Failed"

echo -e "\n=== Firewall Status ==="
sudo ufw status || echo "UFW not installed"
sudo systemctl status firewalld --no-pager 2>/dev/null || echo "Firewalld not installed"
