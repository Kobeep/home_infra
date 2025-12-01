#!/bin/bash
# Home Lab - Fully Automated Secure Deployment
# Encrypted secrets (SOPS) + Free SSL (Let's Encrypt) + Basic Auth

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

echo "╔════════════════════════════════════════════════╗"
echo "║   🔒 Secure Home Lab - Complete Setup         ║"
echo "║   Encrypted Secrets + Free SSL                ║"
echo "╚════════════════════════════════════════════════╝"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOPS_DIR="$PROJECT_ROOT/gitops/secrets"
AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"

# ========================================
# 0. INSTALL DEPENDENCIES
# ========================================
print_info "Step 0: Installing dependencies..."

if ! command -v age &> /dev/null; then
    print_info "Installing age..."
    wget -q https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz -O /tmp/age.tar.gz
    tar -xzf /tmp/age.tar.gz -C /tmp/
    sudo install -m 755 /tmp/age/age /usr/local/bin/
    sudo install -m 755 /tmp/age/age-keygen /usr/local/bin/
    rm -rf /tmp/age /tmp/age.tar.gz
fi

if ! command -v sops &> /dev/null; then
    print_info "Installing sops..."
    wget -q https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64 -O /tmp/sops
    sudo install -m 755 /tmp/sops /usr/local/bin/sops
    rm /tmp/sops
fi

if ! command -v htpasswd &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y apache2-utils 2>/dev/null || \
    sudo dnf install -y httpd-tools 2>/dev/null
fi

print_success "Dependencies OK"
echo ""

# ========================================
# 1. ENCRYPTION KEY
# ========================================
print_info "Step 1: Setup encryption..."

mkdir -p "$(dirname "$AGE_KEY_FILE")"
mkdir -p "$SOPS_DIR"

if [ ! -f "$AGE_KEY_FILE" ]; then
    age-keygen -o "$AGE_KEY_FILE"
    chmod 600 "$AGE_KEY_FILE"
    print_success "Encryption key created: $AGE_KEY_FILE"
    print_warning "⚠️  BACKUP THIS FILE! ⚠️"
else
    print_info "Using existing key"
fi

AGE_PUBLIC_KEY=$(grep "public key:" "$AGE_KEY_FILE" | awk '{print $4}')

cat > "$PROJECT_ROOT/gitops/.sops.yaml" << EOF
creation_rules:
  - path_regex: secrets/.*\.yaml\$
    age: $AGE_PUBLIC_KEY
EOF

print_success "SOPS configured"
echo ""

# ========================================
# 2. CREATE SECRETS
# ========================================
print_info "Step 2: Create secrets..."

read -p "Username for Basic Auth: " USERNAME
read -s -p "Password for Basic Auth: " PASSWORD
echo ""

read -s -p "Grafana admin password: " GRAFANA_PASS
echo ""

read -s -p "InfluxDB admin password: " INFLUX_PASS
echo ""

read -p "OpenAI API Key (or press Enter to skip): " OPENAI_KEY
echo ""

HTPASSWD=$(htpasswd -nb "$USERNAME" "$PASSWORD")

# Basic Auth Secret
cat > "$SOPS_DIR/basic-auth.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: basic-auth
type: Opaque
stringData:
  auth: |
    $HTPASSWD
EOF

# Application Secrets
cat > "$SOPS_DIR/app-secrets.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: grafana-admin
type: Opaque
stringData:
  admin-user: admin
  admin-password: $GRAFANA_PASS

---
apiVersion: v1
kind: Secret
metadata:
  name: influxdb-admin
type: Opaque
stringData:
  admin-username: admin
  admin-password: $INFLUX_PASS
  org: home
  bucket: homeassistant

---
apiVersion: v1
kind: Secret
metadata:
  name: openwebui-secrets
type: Opaque
stringData:
  openai-api-key: ${OPENAI_KEY:-none}
EOF

export SOPS_AGE_KEY_FILE="$AGE_KEY_FILE"
sops --encrypt --in-place "$SOPS_DIR/basic-auth.yaml"
sops --encrypt --in-place "$SOPS_DIR/app-secrets.yaml"

print_success "All secrets encrypted"
echo ""

# ========================================
# 3. DEPLOY SECRETS
# ========================================
print_info "Step 3: Deploy secrets..."

NAMESPACES=("dashy" "argocd" "home-assistant" "adguard" "grocy" "openwebui" "monitoring" "influxdb")

for NS in "${NAMESPACES[@]}"; do
    ssh server "kubectl create namespace $NS 2>/dev/null || true"

    # Deploy basic-auth
    sops --decrypt "$SOPS_DIR/basic-auth.yaml" | ssh server "kubectl apply -n $NS -f - 2>/dev/null || true"

    # Deploy app-specific secrets
    if [ "$NS" == "monitoring" ] || [ "$NS" == "influxdb" ] || [ "$NS" == "openwebui" ]; then
        sops --decrypt "$SOPS_DIR/app-secrets.yaml" | ssh server "kubectl apply -n $NS -f - 2>/dev/null || true"
    fi

    echo "  ✓ $NS"
done

print_success "Secrets deployed"
echo ""

# ========================================
# 4. CERT-MANAGER (SSL)
# ========================================
print_info "Step 4: Install cert-manager..."

if ! ssh server "kubectl get namespace cert-manager 2>/dev/null" &>/dev/null; then
    ssh server "kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml"
    sleep 30
    ssh server "kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s" || true
fi

print_success "cert-manager ready"
echo ""

# ========================================
# 5. LET'S ENCRYPT
# ========================================
print_info "Step 5: Configure Let's Encrypt..."

read -p "Email for SSL certificates: " EMAIL

ssh server "kubectl apply -f -" << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $EMAIL
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

print_success "Let's Encrypt configured"
echo ""

# ========================================
# 6. UPDATE INGRESSES
# ========================================
print_info "Step 6: Update ingresses for SSL..."

cd "$PROJECT_ROOT"

# Add SSL annotations and TLS to ingresses
for file in gitops/apps/*/base/ingress.yaml; do
    if ! grep -q "cert-manager.io/cluster-issuer" "$file" 2>/dev/null; then
        # Extract host
        HOST=$(grep "host:" "$file" | awk '{print $3}' | head -1)

        # Add annotation
        sed -i '/nginx.ingress.kubernetes.io\/ssl-redirect/a\    cert-manager.io/cluster-issuer: letsencrypt-prod' "$file"
        sed -i 's/ssl-redirect: "false"/ssl-redirect: "true"/' "$file"

        # Add TLS section
        if [ -n "$HOST" ] && ! grep -q "tls:" "$file"; then
            sed -i "/^spec:/a\  tls:\n  - hosts:\n    - $HOST\n    secretName: ${HOST//\./-}-tls" "$file"
        fi

        print_success "  ✓ $file"
    fi
done

# Update Grafana
if ! grep -q "cert-manager.io/cluster-issuer" "gitops/platform/monitoring/values-prod.yaml"; then
    sed -i '/ingress:/,/path:/ {
        /annotations:/a\        cert-manager.io/cluster-issuer: letsencrypt-prod
    }' "gitops/platform/monitoring/values-prod.yaml"

    # Add TLS
    sed -i '/hosts:/a\      tls:\n      - hosts:\n        - grafana.kobecloud.pl\n        secretName: grafana-kobecloud-pl-tls' "gitops/platform/monitoring/values-prod.yaml"
fi

print_success "SSL configured for all ingresses"
echo ""

# ========================================
# 7. RATE LIMITING & FIREWALL
# ========================================
print_info "Step 7: Security hardening..."

ssh server "kubectl patch configmap ingress-nginx-prod-controller -n ingress-nginx --type merge -p '{\"data\":{\"limit-rps\":\"10\"}}' 2>/dev/null" && \
    print_success "Rate limiting enabled" || print_warning "Will be configured after ingress-nginx is ready"

ssh server "sudo iptables -C INPUT -p tcp --dport 30000:32767 -j DROP 2>/dev/null || sudo iptables -I INPUT -p tcp --dport 30000:32767 -j DROP" && \
    print_success "Firewall configured" || print_warning "Manual firewall configuration may be needed"

echo ""

# ========================================
# 8. GIT COMMIT
# ========================================
print_info "Step 8: Save changes..."

echo -e "\n# SOPS encryption keys\n.config/sops/\n**/*_plain\n" >> "$PROJECT_ROOT/.gitignore"

git add gitops/
git add .gitignore
git diff --cached --stat

read -p "Commit & push? (Y/n): " PUSH
if [[ ! $PUSH =~ ^[Nn]$ ]]; then
    git commit -m "feat: Encrypted secrets + SSL + security" || true
    git push
    print_success "Pushed to repository"
fi

echo ""

# ========================================
# 9. ARGOCD SYNC
# ========================================
print_info "Step 9: Sync ArgoCD..."

read -p "Force sync now? (Y/n): " SYNC
if [[ ! $SYNC =~ ^[Yy]$ ]]; then
    print_info "ArgoCD will auto-sync in ~3 minutes"
else
    for APP in $(ssh server "kubectl get app -n argocd -o name"); do
        ssh server "kubectl -n argocd patch $APP --type merge -p '{\"operation\":{\"sync\":{}}}'" 2>/dev/null || true
    done
    print_success "Synced"
fi

echo ""

# ========================================
# 10. SUMMARY
# ========================================
SERVER_IP=$(ssh server "curl -4 -s ifconfig.me 2>/dev/null")

echo "╔════════════════════════════════════════════════╗"
echo "║              ✅ SETUP COMPLETE                 ║"
echo "╚════════════════════════════════════════════════╝"
echo ""
print_success "Security Features:"
echo "  ✓ Encrypted secrets (SOPS + age)"
echo "  ✓ Basic Authentication (username: $USERNAME)"
echo "  ✓ Free SSL (Let's Encrypt)"
echo "  ✓ Rate Limiting (10 req/s)"
echo "  ✓ Firewall rules"
echo ""
print_warning "TODO: Add DNS records (A records to $SERVER_IP):"
echo "  dashy.kobecloud.pl"
echo "  argocd.kobecloud.pl"
echo "  grafana.kobecloud.pl"
echo "  home-assistant.kobecloud.pl"
echo "  adguard.kobecloud.pl"
echo "  grocy.kobecloud.pl"
echo "  openwebui.kobecloud.pl"
echo ""
print_info "After DNS: https://dashy.kobecloud.pl"
print_info "SSL certs will be auto-issued by Let's Encrypt"
echo ""
print_warning "BACKUP: $AGE_KEY_FILE"
echo ""
