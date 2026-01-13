#!/bin/bash

# Quick deployment script - tylko Ingress bez NodePort
# Kolory
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Szybkie wdrożenie - Ingress Only${NC}"
echo ""

# Pobierz IP
SERVER_IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}IP serwera: ${SERVER_IP}${NC}"
echo ""

# 1. Zainstaluj/zaktualizuj Ingress Controller
echo -e "${BLUE}1. Instaluję Ingress NGINX Controller...${NC}"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/baremetal/deploy.yaml

# Czekaj na gotowość
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# 2. Zaktualizuj ConfigMap Dashy
echo ""
echo -e "${BLUE}2. Aktualizuję ConfigMap Dashy...${NC}"
sed "s/SERVER_IP/${SERVER_IP}/g" k8s/dashy/configmap.yaml | kubectl apply -f -

# 3. Wdróż Ingress Rules
echo ""
echo -e "${BLUE}3. Wdrażam Ingress Rules...${NC}"
kubectl apply -f k8s/ingress-nginx.yaml

# 4. Zaktualizuj wszystkie Services na ClusterIP
echo ""
echo -e "${BLUE}4. Aktualizuję Services na ClusterIP...${NC}"
for dir in dashy jenkins grafana prometheus home-assistant adguard grocy openwebui influxdb; do
  if [ -f "k8s/$dir/service.yaml" ]; then
    kubectl apply -f k8s/$dir/service.yaml
  fi
done

# 5. Restart Dashy
echo ""
echo -e "${BLUE}5. Restartuję Dashy...${NC}"
kubectl rollout restart deployment dashy -n dashy

echo ""
echo -e "${GREEN}✅ Gotowe!${NC}"
echo ""
echo -e "${BLUE}Dostęp przez Ingress:${NC}"
echo -e "  Dashy:         http://${SERVER_IP}/"
echo -e "  Jenkins:       http://${SERVER_IP}/jenkins"
echo -e "  Grafana:       http://${SERVER_IP}/grafana"
echo -e "  Prometheus:    http://${SERVER_IP}/prometheus"
echo -e "  HomeAssistant: http://${SERVER_IP}/homeassistant"
echo -e "  AdGuard:       http://${SERVER_IP}/adguard"
echo -e "  Grocy:         http://${SERVER_IP}/grocy"
echo -e "  OpenWebUI:     http://${SERVER_IP}/openwebui"
echo -e "  InfluxDB:      http://${SERVER_IP}/influxdb"
echo ""
