#!/bin/bash
# Home Lab GitOps - Helper Script
# Quick commands for managing your home lab infrastructure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."

    if ! command_exists kubectl; then
        print_error "kubectl not found. Please install kubectl first."
        exit 1
    fi

    if ! command_exists k3d && ! command_exists kind && ! kubectl cluster-info &>/dev/null; then
        print_error "No Kubernetes cluster found. Install k3d/kind or configure kubectl."
        exit 1
    fi

    print_success "Prerequisites check passed!"
}

# Show cluster status
show_status() {
    print_info "Cluster Status:"
    echo ""

    echo "📊 Namespaces:"
    kubectl get namespaces | grep -E "dashy|home-assistant|adguard|grocy|openwebui|monitoring|argocd" || echo "No app namespaces found"
    echo ""

    echo "🚀 Deployments:"
    kubectl get deployments -A | grep -E "dashy|home-assistant|adguard|grocy|openwebui|grafana|argocd" || echo "No deployments found"
    echo ""

    echo "🔌 Services:"
    kubectl get svc -A | grep -E "dashy|home-assistant|adguard|grocy|openwebui|grafana|argocd|prometheus" || echo "No services found"
    echo ""

    echo "🌐 Ingresses:"
    kubectl get ingress -A || echo "No ingresses found"
}

# Test DNS from Dashy pod
test_dns() {
    print_info "Testing DNS from Dashy pod..."

    POD=$(kubectl get pod -n dashy -l app=dashy -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)

    if [ -z "$POD" ]; then
        print_error "Dashy pod not found. Is Dashy deployed?"
        return 1
    fi

    print_info "Testing DNS resolution from pod: $POD"
    echo ""

    # Test services
    SERVICES=(
        "home-assistant.home-assistant.svc.cluster.local"
        "adguard.adguard.svc.cluster.local"
        "monitoring-prod-grafana.monitoring.svc.cluster.local"
        "argocd-server.argocd.svc.cluster.local"
    )

    for service in "${SERVICES[@]}"; do
        if kubectl exec -n dashy "$POD" -- nslookup "$service" &>/dev/null; then
            print_success "DNS: $service"
        else
            print_warning "DNS: $service (might not be deployed)"
        fi
    done
}

# Port forward services
port_forward() {
    SERVICE=$1

    case $SERVICE in
        dashy)
            print_info "Port forwarding Dashy to http://localhost:8080"
            kubectl port-forward -n dashy svc/dashy 8080:80
            ;;
        grafana)
            print_info "Port forwarding Grafana to http://localhost:3000"
            kubectl port-forward -n monitoring svc/monitoring-prod-grafana 3000:80
            ;;
        argocd)
            print_info "Port forwarding ArgoCD to http://localhost:8081"
            kubectl port-forward -n argocd svc/argocd-server 8081:80
            ;;
        home-assistant)
            print_info "Port forwarding Home Assistant to http://localhost:8123"
            kubectl port-forward -n home-assistant svc/home-assistant 8123:8123
            ;;
        *)
            print_error "Unknown service: $SERVICE"
            echo "Available services: dashy, grafana, argocd, home-assistant"
            exit 1
            ;;
    esac
}

# Update Dashy config
update_dashy_config() {
    print_info "Updating Dashy ConfigMap..."

    if [ ! -f "gitops/apps/dashy/base/configmap.yaml" ]; then
        print_error "ConfigMap file not found. Are you in the correct directory?"
        exit 1
    fi

    kubectl apply -f gitops/apps/dashy/base/configmap.yaml
    print_success "ConfigMap updated!"

    print_info "Restarting Dashy deployment..."
    kubectl rollout restart -n dashy deployment/dashy

    print_info "Waiting for rollout to complete..."
    kubectl rollout status -n dashy deployment/dashy

    print_success "Dashy updated successfully!"
}

# Show logs
show_logs() {
    APP=$1
    NAMESPACE=$2

    if [ -z "$APP" ]; then
        print_error "Usage: $0 logs <app-name> [namespace]"
        echo "Examples:"
        echo "  $0 logs dashy"
        echo "  $0 logs grafana monitoring"
        exit 1
    fi

    if [ -z "$NAMESPACE" ]; then
        # Try to find namespace
        NAMESPACE=$(kubectl get deployment -A | grep "$APP" | awk '{print $1}' | head -1)
    fi

    if [ -z "$NAMESPACE" ]; then
        print_error "Could not find deployment for $APP"
        exit 1
    fi

    print_info "Showing logs for $APP in namespace $NAMESPACE..."
    kubectl logs -n "$NAMESPACE" deployment/"$APP" -f --tail=100
}

# Setup /etc/hosts
setup_hosts() {
    print_warning "This will add entries to /etc/hosts (requires sudo)"

    ENTRIES=(
        "127.0.0.1 dashy.kobeep.pl"
        "127.0.0.1 argocd.kobeep.pl"
        "127.0.0.1 grafana.kobeep.pl"
        "127.0.0.1 home-assistant.kobeep.pl"
        "127.0.0.1 adguard.kobeep.pl"
        "127.0.0.1 grocy.kobeep.pl"
        "127.0.0.1 openwebui.kobeep.pl"
    )

    echo ""
    echo "Will add the following entries:"
    for entry in "${ENTRIES[@]}"; do
        echo "  $entry"
    done
    echo ""

    read -p "Continue? (y/N) " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Cancelled."
        exit 0
    fi

    for entry in "${ENTRIES[@]}"; do
        if grep -q "$entry" /etc/hosts; then
            print_warning "Already exists: $entry"
        else
            echo "$entry" | sudo tee -a /etc/hosts >/dev/null
            print_success "Added: $entry"
        fi
    done

    print_success "Done! You can now access services via http://dashy.kobeep.pl"
}

# Show help
show_help() {
    cat << EOF
🏠 Home Lab GitOps - Helper Script

Usage: $0 <command> [options]

Commands:
  status              Show cluster status (pods, services, ingresses)
  dns                 Test DNS resolution from Dashy pod
  forward <service>   Port forward a service to localhost
                      Services: dashy, grafana, argocd, home-assistant
  update-dashy        Apply Dashy ConfigMap changes and restart
  logs <app> [ns]     Show logs for an application
  hosts               Setup /etc/hosts for local access
  help                Show this help message

Examples:
  $0 status
  $0 dns
  $0 forward dashy
  $0 update-dashy
  $0 logs dashy
  $0 logs grafana monitoring
  $0 hosts

Quick Access:
  Port forward Dashy:     $0 forward dashy
  Then open:              http://localhost:8080

  Or setup /etc/hosts:    $0 hosts
  Then open:              http://dashy.kobeep.pl

EOF
}

# Main script
main() {
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi

    check_prerequisites

    case "$1" in
        status)
            show_status
            ;;
        dns)
            test_dns
            ;;
        forward)
            port_forward "$2"
            ;;
        update-dashy)
            update_dashy_config
            ;;
        logs)
            show_logs "$2" "$3"
            ;;
        hosts)
            setup_hosts
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
