#!/bin/bash

# Kolory dla outputu
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Home Lab - Ingress NGINX Setup & Deployment         ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Funkcja do sprawdzania czy komenda istnieje
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Sprawdzenie kubectl
if ! command_exists kubectl; then
    echo -e "${RED}❌ kubectl nie jest zainstalowany!${NC}"
    exit 1
fi

# Pobierz IP serwera
SERVER_IP=$(hostname -I | awk '{print $1}')
echo -e "${YELLOW}🔍 Wykryty IP serwera: ${SERVER_IP}${NC}"
echo ""

# Zapytaj użytkownika o IP lub użyj domyślnego
read -p "Czy użyć tego IP? (T/n) lub podaj własny: " user_input
if [[ $user_input != "T" && $user_input != "t" && $user_input != "" ]]; then
    if [[ $user_input =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        SERVER_IP=$user_input
        echo -e "${GREEN}✓ Używam IP: ${SERVER_IP}${NC}"
    else
        echo -e "${RED}❌ Nieprawidłowy format IP!${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     Krok 1: Instalacja Ingress NGINX Controller           ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Sprawdź czy Ingress NGINX jest już zainstalowany
if kubectl get namespace ingress-nginx >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Namespace ingress-nginx już istnieje${NC}"
    read -p "Czy chcesz przeinstalować? (t/N): " reinstall
    if [[ $reinstall == "t" || $reinstall == "T" ]]; then
        echo -e "${YELLOW}🗑️  Usuwanie starej instalacji...${NC}"
        kubectl delete namespace ingress-nginx
        sleep 5
    else
        echo -e "${BLUE}➡️  Pomijam instalację kontrolera${NC}"
    fi
fi

# Instalacja Ingress NGINX przez Helm lub manifest
if ! kubectl get namespace ingress-nginx >/dev/null 2>&1; then
    echo -e "${GREEN}📦 Instaluję NGINX Ingress Controller...${NC}"

    if command_exists helm; then
        echo -e "${BLUE}🎯 Używam Helm...${NC}"
        helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
        helm repo update
        helm install ingress-nginx ingress-nginx/ingress-nginx \
            --create-namespace \
            --namespace ingress-nginx \
            --set controller.service.type=NodePort \
            --set controller.service.nodePorts.http=30080 \
            --set controller.service.nodePorts.https=30443
    else
        echo -e "${BLUE}🎯 Używam manifestu YAML...${NC}"
        kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/baremetal/deploy.yaml

        # Modyfikuj service aby używał NodePort
        kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec":{"type":"NodePort","ports":[{"port":80,"nodePort":30080,"name":"http"},{"port":443,"nodePort":30443,"name":"https"}]}}'
    fi

    echo -e "${GREEN}✓ Ingress NGINX Controller zainstalowany${NC}"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     Krok 2: Aktualizacja konfiguracji Dashy               ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Backup starego configmap
if kubectl get configmap dashy-config -n dashy >/dev/null 2>&1; then
    echo -e "${YELLOW}💾 Tworzę backup starego configu...${NC}"
    kubectl get configmap dashy-config -n dashy -o yaml > /tmp/dashy-config-backup-$(date +%Y%m%d-%H%M%S).yaml
fi

# Zastąp SERVER_IP w configmap
echo -e "${GREEN}📝 Aktualizuję ConfigMap Dashy z IP: ${SERVER_IP}${NC}"
sed "s/SERVER_IP/${SERVER_IP}/g" k8s/dashy/configmap.yaml | kubectl apply -f -

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     Krok 3: Wdrożenie Ingress Rules                       ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Zastąp SERVER_IP w ingress i wdróż
echo -e "${GREEN}🚀 Wdrażam Ingress rules dla wszystkich namespace'ów...${NC}"
kubectl apply -f k8s/ingress-nginx.yaml

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     Krok 4: Aktualizacja Services na ClusterIP            ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${GREEN}🔄 Aktualizuję wszystkie Services na ClusterIP...${NC}"
kubectl apply -f k8s/dashy/service.yaml
kubectl apply -f k8s/jenkins/service.yaml
kubectl apply -f k8s/grafana/service.yaml
kubectl apply -f k8s/prometheus/service.yaml
kubectl apply -f k8s/home-assistant/service.yaml
kubectl apply -f k8s/adgua6d/service.yaml
kubectl apply -f k8s/grocy/service.yaml
kubectl apply -f k8s/openwebui/service.yaml
kubectl apply -f k8s/influxdb/service.yaml

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     Krok 5: Restart Dashy                                 ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${GREEN}🔄 Restartuję Dashy pod...${NC}"
kubectl rollout restart deployment dashy -n dashy
kubectl rollout status deployment dashy -n dashy

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     Krok 5: Weryfikacja                                   ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}⏳ Czekam na gotowość Ingress Controller...${NC}"
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

echo ""
echo -e "${GREEN}✓ Sprawdzam status Ingress...${NC}"
kubectl get ingress -A

echo ""
echo -e "${GREEN}✓ Sprawdzam status serwisów...${NC}"
kubectl get svc -A | grep -E "dashy|jenkins|grafana|prometheus|home-assistant|adguard|grocy|openwebui|influxdb"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Instalacja zakończona pomyślnie!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}📍 Dostęp do aplikacji przez Ingress:${NC}"
echo ""
echo -e "  🏠 Dashy Dashboard:      ${GREEN}http://${SERVER_IP}/${NC}"
echo -e "  🔧 Jenkins:              ${GREEN}http://${SERVER_IP}/jenkins${NC}"
echo -e "  📊 Grafana:              ${GREEN}http://${SERVER_IP}/grafana${NC}"
echo -e "  📈 Prometheus:           ${GREEN}http://${SERVER_IP}/prometheus${NC}"
echo -e "  🏡 Home Assistant:       ${GREEN}http://${SERVER_IP}/homeassistant${NC}"
echo -e "  🛡️  AdGuard:              ${GREEN}http://${SERVER_IP}/adguard${NC}"
echo -e "  🛒 Grocy:                ${GREEN}http://${SERVER_IP}/grocy${NC}"
echo -e "  🤖 OpenWebUI:            ${GREEN}http://${SERVER_IP}/openwebui${NC}"
echo -e "  💾 InfluxDB:             ${GREEN}http://${SERVER_IP}/influxdb${NC}"
echo ""
echo -e "${YELLOW}💡 Wskazówki:${NC}"
echo -e "  • Wszystkie aplikacje dostępne są TYLKO przez Ingress"
echo -e "  • Serwisy są typu ClusterIP (bez NodePort)"
echo -e "  • Dashboard Dashy jest na głównej ścieżce /"
echo -e "  • Wszystkie serwisy mają health check włączony"
echo -e "  • Status sprawdzany jest co 60 sekund"
echo -e "  • Ingress NGINX używa portów domyślnych (80/443)"
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
