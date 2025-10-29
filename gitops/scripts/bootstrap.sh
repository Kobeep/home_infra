#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_ROOT="$(dirname "$SCRIPT_DIR")"

check_prerequisites() {
    echo "INFO=> Checking required tools..."

    local missing=()
    command -v docker >/dev/null 2>&1 || missing+=("docker")
    command -v kubectl >/dev/null 2>&1 || missing+=("kubectl")
    command -v k3d >/dev/null 2>&1 || missing+=("k3d")
    command -v helm >/dev/null 2>&1 || missing+=("helm")

    if [ ${#missing[@]} -ne 0 ]; then
        echo "INFO=> Missing: ${missing[*]}"
        exit 1
    fi

    echo "INFO=> All tools available"
}

create_directories() {
    echo "INFO=> Creating persistent volume directories..."
    sudo mkdir -p /var/lib/home-infra/{home-assistant,grafana,prometheus,influxdb,adguard}
    sudo chown -R $USER:$USER /var/lib/home-infra
    echo "INFO=> Directories created"
}

create_develop_cluster() {
    echo "INFO=> Creating DEVELOP cluster..."

    if k3d cluster list | grep -q "home-develop"; then
        echo "INFO=> DEVELOP cluster already exists, skipping"
    else
        k3d cluster create --config "$GITOPS_ROOT/clusters/develop/cluster-config.yaml"
        echo "INFO=> DEVELOP cluster created"
    fi
}

create_prod_cluster() {
    echo "INFO=> Creating PRODUCTION cluster..."

    if k3d cluster list | grep -q "home-prod"; then
        echo "INFO=> PRODUCTION cluster already exists, skipping"
    else
        k3d cluster create --config "$GITOPS_ROOT/clusters/prod/cluster-config.yaml"
        echo "INFO=> PRODUCTION cluster created"
    fi
}

install_argocd() {
    local context=$1
    local cluster_name=$2

    echo "INFO=> Installing ArgoCD on $cluster_name cluster..."
    kubectl config use-context "$context"

    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    echo "INFO=> Waiting for ArgoCD to be ready (this may take a few minutes)..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

    echo "INFO=> Patching ArgoCD to run in insecure mode..."
    kubectl patch deployment argocd-server -n argocd --type='json' \
        -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--insecure"}]'

    kubectl rollout status deployment/argocd-server -n argocd
    echo "INFO=> ArgoCD installed on $cluster_name"
}

deploy_root_app() {
    local context=$1
    local env=$2

    echo "INFO=> Deploying root application..."
    kubectl config use-context "$context"
    kubectl apply -f "$GITOPS_ROOT/clusters/$env/argocd-apps/root-app.yaml"
    echo "INFO=> Root application deployed"
}

show_credentials() {
    echo ""
    echo "INFO=> Retrieving ArgoCD credentials..."
    echo ""

    if [ "$1" != "prod" ]; then
        kubectl config use-context k3d-home-develop
        DEV_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "N/A")
        echo "DEVELOP:"
        echo "  URL: http://localhost:8080"
        echo "  User: admin"
        echo "  Pass: $DEV_PASSWORD"
        echo "  Port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443 --context k3d-home-develop"
        echo ""
    fi

    if [ "$1" != "develop" ] && [ "$1" != "dev" ]; then
        kubectl config use-context k3d-home-prod
        PROD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "N/A")
        echo "PRODUCTION:"
        echo "  URL: http://localhost:9090"
        echo "  User: admin"
        echo "  Pass: $PROD_PASSWORD"
        echo "  Port-forward: kubectl port-forward svc/argocd-server -n argocd 9090:443 --context k3d-home-prod"
        echo ""
    fi
}

main() {
    echo "INFO=> Starting Home Infrastructure bootstrap"
    echo ""

    check_prerequisites
    create_directories
    echo ""

    if [ "$1" == "develop" ] || [ "$1" == "dev" ]; then
        create_develop_cluster
        install_argocd "k3d-home-develop" "DEVELOP"
        deploy_root_app "k3d-home-develop" "develop"
    elif [ "$1" == "prod" ] || [ "$1" == "production" ]; then
        create_prod_cluster
        install_argocd "k3d-home-prod" "PRODUCTION"
        deploy_root_app "k3d-home-prod" "prod"
    else
        create_develop_cluster
        create_prod_cluster
        echo ""
        install_argocd "k3d-home-develop" "DEVELOP"
        echo ""
        install_argocd "k3d-home-prod" "PRODUCTION"
        echo ""
        deploy_root_app "k3d-home-develop" "develop"
        deploy_root_app "k3d-home-prod" "prod"
    fi

    show_credentials "$1"
    echo "INFO=> Bootstrap completed! 🚀"
    echo ""
}

main "$@"
