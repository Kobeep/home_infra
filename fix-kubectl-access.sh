#!/bin/bash

# Fix kubeconfig for local access
# Kolory
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔧 Naprawa dostępu kubectl do klastra...${NC}"
echo ""

# Dane z inventory
SERVER_IP="192.168.1.16"
SERVER_USER="server"
SSH_KEY="~/.ssh/server/id_rsa"

# Rozwiń ścieżkę SSH key
SSH_KEY="${SSH_KEY/#\~/$HOME}"

echo -e "${YELLOW}📋 Konfiguracja:${NC}"
echo -e "  Serwer: ${SERVER_IP}"
echo -e "  User: ${SERVER_USER}"
echo -e "  SSH Key: ${SSH_KEY}"
echo ""

# Sprawdź czy możemy połączyć się SSH
echo -e "${BLUE}1. Sprawdzam połączenie SSH...${NC}"
if ! ssh -i "${SSH_KEY}" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${SERVER_USER}@${SERVER_IP}" "echo 'OK'" &>/dev/null; then
    echo -e "${RED}❌ Nie można połączyć się z serwerem!${NC}"
    echo -e "${YELLOW}Sprawdź:${NC}"
    echo -e "  - Czy serwer działa: ${SERVER_IP}"
    echo -e "  - Czy klucz SSH jest poprawny: ${SSH_KEY}"
    echo -e "  - Czy użytkownik istnieje: ${SERVER_USER}"
    exit 1
fi
echo -e "${GREEN}✓ Połączenie SSH działa${NC}"
echo ""

# Pobierz kubeconfig z serwera
echo -e "${BLUE}2. Pobieram kubeconfig z serwera...${NC}"
REMOTE_KUBECONFIG=$(ssh -i "${SSH_KEY}" "${SERVER_USER}@${SERVER_IP}" "sudo cat /etc/rancher/k3s/k3s.yaml" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$REMOTE_KUBECONFIG" ]; then
    echo -e "${RED}❌ Nie można pobrać kubeconfig z serwera!${NC}"
    echo -e "${YELLOW}Sprawdź czy K3s jest zainstalowany na serwerze.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Kubeconfig pobrany${NC}"
echo ""

# Backup starego kubeconfig
echo -e "${BLUE}3. Tworzę backup starego kubeconfig...${NC}"
if [ -f ~/.kube/config ]; then
    cp ~/.kube/config ~/.kube/config.backup-$(date +%Y%m%d-%H%M%S)
    echo -e "${GREEN}✓ Backup utworzony${NC}"
else
    mkdir -p ~/.kube
    echo -e "${YELLOW}⚠️  Brak starego config - tworzę nowy${NC}"
fi
echo ""

# Zapisz nowy kubeconfig z poprawionym adresem
echo -e "${BLUE}4. Zapisuję poprawiony kubeconfig...${NC}"
echo "$REMOTE_KUBECONFIG" | sed "s/127.0.0.1/${SERVER_IP}/g" > ~/.kube/config
chmod 600 ~/.kube/config
echo -e "${GREEN}✓ Kubeconfig zapisany${NC}"
echo ""

# Testuj połączenie
echo -e "${BLUE}5. Testuję połączenie z klastrem...${NC}"
if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✓ Połączenie działa!${NC}"
    echo ""

    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ Dostęp naprawiony!${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo ""

    # Pokaż status
    echo -e "${YELLOW}📊 Status klastra:${NC}"
    kubectl cluster-info | grep -E "Kubernetes|running"
    echo ""

    echo -e "${YELLOW}🔍 Sprawdzam Ingress NGINX...${NC}"
    kubectl get pods -n ingress-nginx 2>/dev/null || echo "Namespace ingress-nginx nie istnieje"
    echo ""

    echo -e "${YELLOW}🌐 Sprawdzam Ingress rules...${NC}"
    kubectl get ingress -A 2>/dev/null || echo "Brak Ingress rules"
    echo ""

    echo -e "${YELLOW}🚀 Sprawdzam serwisy...${NC}"
    kubectl get svc -A | grep -E "NAME|dashy|jenkins|grafana|ingress" | head -10
    echo ""

    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}💡 Przydatne komendy:${NC}"
    echo -e "  kubectl get pods -A           # Wszystkie pody"
    echo -e "  kubectl get ingress -A        # Ingress rules"
    echo -e "  kubectl get svc -A            # Wszystkie serwisy"
    echo -e "  kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller  # Logi Ingress"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
else
    echo -e "${RED}❌ Nadal problemy z połączeniem!${NC}"
    echo -e "${YELLOW}Debug info:${NC}"
    kubectl cluster-info
    exit 1
fi
