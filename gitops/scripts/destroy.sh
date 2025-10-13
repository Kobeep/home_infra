#!/usr/bin/env bash
set -e

destroy_cluster() {
    local cluster_name=$1

    if k3d cluster list | grep -q "$cluster_name"; then
        echo "INFO=> Destroying cluster: $cluster_name"
        k3d cluster delete "$cluster_name"
        echo "INFO=> Cluster $cluster_name destroyed"
    else
        echo "INFO=> Cluster $cluster_name does not exist"
    fi
}

main() {
    echo "INFO=> This will destroy all k3d clusters for Home Infrastructure"
    read -p "Are you sure? (yes/no): " -r
    echo

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "INFO=> Aborted"
        exit 0
    fi

    if [ "$1" == "develop" ] || [ "$1" == "dev" ]; then
        destroy_cluster "home-develop"
    elif [ "$1" == "prod" ] || [ "$1" == "production" ]; then
        destroy_cluster "home-prod"
    else
        destroy_cluster "home-develop"
        destroy_cluster "home-prod"
    fi

    echo "INFO=> Done!"
}

main "$@"
