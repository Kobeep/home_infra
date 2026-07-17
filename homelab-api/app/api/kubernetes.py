# Kubernetes API endpoints for showing the state of the Kubernetes cluster
from fastapi import APIRouter
from kubernetes import client, config

router = APIRouter()

@router.get("/", tags=["Kubernetes"])
async def kubernetes_info():
    """
    Get information about the Kubernetes cluster.
    Returns the cluster version and API server URL in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        v1 = client.VersionApi()
        version_info = v1.get_code()
        cluster_info = {
            "version": version_info.git_version,
            "api_server": version_info.server_address,
        }
        json_response = {
            "version": cluster_info["version"],
            "api_server": cluster_info["api_server"],
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}

@router.get("/cluster-info", tags=["Kubernetes"])
async def get_cluster_info():
    """
    Get information about the Kubernetes cluster.
    Returns the cluster version and API server URL and returns it in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        v1 = client.VersionApi()
        version_info = v1.get_code()
        cluster_info = {
            "version": version_info.git_version,
            "api_server": version_info.server_address,
        }
        json_response = {
            "version": cluster_info["version"],
            "api_server": cluster_info["api_server"],
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}

@router.get("/nodes", tags=["Kubernetes"])
async def get_nodes():
    """
    Get a list of nodes in the Kubernetes cluster.
    Returns node names and their statuses in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        v1 = client.CoreV1Api()
        nodes = v1.list_node()
        node_info = []
        for node in nodes.items:
            node_info.append({
                "name": node.metadata.name,
                "status": node.status.conditions[-1].type,
            })
        json_response = {
            "nodes": node_info
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}

@router.get("/pods", tags=["Kubernetes"])
async def get_pods():
    """
    Get a list of pods in the Kubernetes cluster.
    Returns pod names, namespaces, and their statuses in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        v1 = client.CoreV1Api()
        pods = v1.list_pod_for_all_namespaces()
        pod_info = []
        for pod in pods.items:
            pod_info.append({
                "name": pod.metadata.name,
                "namespace": pod.metadata.namespace,
                "status": pod.status.phase,
            })
        json_response = {
            "pods": pod_info
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}

@router.get("/services", tags=["Kubernetes"])
async def get_services():
    """
    Get a list of services in the Kubernetes cluster.
    Returns service names, namespaces, and their types in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        v1 = client.CoreV1Api()
        services = v1.list_service_for_all_namespaces()
        service_info = []
        for service in services.items:
            service_info.append({
                "name": service.metadata.name,
                "namespace": service.metadata.namespace,
                "type": service.spec.type,
            })
        json_response = {
            "services": service_info
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}

@router.get("/deployments", tags=["Kubernetes"])
async def get_deployments():
    """
    Get a list of deployments in the Kubernetes cluster.
    Returns deployment names, namespaces, and their replicas in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        apps_v1 = client.AppsV1Api()
        deployments = apps_v1.list_deployment_for_all_namespaces()
        deployment_info = []
        for deployment in deployments.items:
            deployment_info.append({
                "name": deployment.metadata.name,
                "namespace": deployment.metadata.namespace,
                "replicas": deployment.spec.replicas,
            })
        json_response = {
            "deployments": deployment_info
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}

@router.get("/state", tags=["Kubernetes"])
async def get_kubernetes_state():
    """
    Get the overall state of the Kubernetes cluster.
    Returns a summary of nodes, pods, services, and deployments in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        v1 = client.CoreV1Api()
        apps_v1 = client.AppsV1Api()

        # Get nodes
        nodes = v1.list_node()
        node_info = [{"name": node.metadata.name, "status": node.status.conditions[-1].type} for node in nodes.items]

        # Get pods
        pods = v1.list_pod_for_all_namespaces()
        pod_info = [{"name": pod.metadata.name, "namespace": pod.metadata.namespace, "status": pod.status.phase} for pod in pods.items]

        # Get services
        services = v1.list_service_for_all_namespaces()
        service_info = [{"name": service.metadata.name, "namespace": service.metadata.namespace, "type": service.spec.type} for service in services.items]

        # Get deployments
        deployments = apps_v1.list_deployment_for_all_namespaces()
        deployment_info = [{"name": deployment.metadata.name, "namespace": deployment.metadata.namespace, "replicas": deployment.spec.replicas} for deployment in deployments.items]

        json_response = {
            "nodes": node_info,
            "pods": pod_info,
            "services": service_info,
            "deployments": deployment_info,
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}

@router.get("/cluster-health", tags=["Kubernetes"])
async def get_cluster_health():
    """
    Get the health status of the Kubernetes cluster.
    Returns a summary of the health of nodes, pods, and deployments in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        v1 = client.CoreV1Api()
        apps_v1 = client.AppsV1Api()

        # Get nodes health
        nodes = v1.list_node()
        node_health = [{"name": node.metadata.name, "status": node.status.conditions[-1].type} for node in nodes.items]

        # Get pods health
        pods = v1.list_pod_for_all_namespaces()
        pod_health = [{"name": pod.metadata.name, "namespace": pod.metadata.namespace, "status": pod.status.phase} for pod in pods.items]

        # Get deployments health
        deployments = apps_v1.list_deployment_for_all_namespaces()
        deployment_health = [{"name": deployment.metadata.name, "namespace": deployment.metadata.namespace, "replicas": deployment.spec.replicas} for deployment in deployments.items]

        json_response = {
            "node_health": node_health,
            "pod_health": pod_health,
            "deployment_health": deployment_health,
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}

@router.get("/cluster-metrics", tags=["Kubernetes"])
async def get_cluster_metrics():
    """
    Get metrics of the Kubernetes cluster.
    Returns CPU and memory usage of nodes and pods in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        v1 = client.CoreV1Api()

        # Get nodes metrics
        nodes = v1.list_node()
        node_metrics = []
        for node in nodes.items:
            node_metrics.append({
                "name": node.metadata.name,
                "cpu": node.status.capacity.get("cpu"),
                "memory": node.status.capacity.get("memory"),
            })

        # Get pods metrics
        pods = v1.list_pod_for_all_namespaces()
        pod_metrics = []
        for pod in pods.items:
            pod_metrics.append({
                "name": pod.metadata.name,
                "namespace": pod.metadata.namespace,
                "cpu": pod.status.container_statuses[0].resources.requests.get("cpu") if pod.status.container_statuses else None,
                "memory": pod.status.container_statuses[0].resources.requests.get("memory") if pod.status.container_statuses else None,
            })

        json_response = {
            "node_metrics": node_metrics,
            "pod_metrics": pod_metrics,
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}

@router.get("/cluster-logs", tags=["Kubernetes"])
async def get_cluster_logs():
    """
    Get logs of the Kubernetes cluster.
    Returns logs of all pods in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        v1 = client.CoreV1Api()

        # Get pods logs
        pods = v1.list_pod_for_all_namespaces()
        pod_logs = []
        for pod in pods.items:
            try:
                log = v1.read_namespaced_pod_log(name=pod.metadata.name, namespace=pod.metadata.namespace)
                pod_logs.append({
                    "name": pod.metadata.name,
                    "namespace": pod.metadata.namespace,
                    "log": log,
                })
            except Exception as e:
                pod_logs.append({
                    "name": pod.metadata.name,
                    "namespace": pod.metadata.namespace,
                    "error": str(e),
                })

        json_response = {
            "pod_logs": pod_logs,
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}

@router.get("/cluster-events", tags=["Kubernetes"])
async def get_cluster_events():
    """
    Get events of the Kubernetes cluster.
    Returns events of all namespaces in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        v1 = client.CoreV1Api()

        # Get events
        events = v1.list_event_for_all_namespaces()
        event_info = []
        for event in events.items:
            event_info.append({
                "name": event.metadata.name,
                "namespace": event.metadata.namespace,
                "reason": event.reason,
                "message": event.message,
                "type": event.type,
                "timestamp": event.last_timestamp,
            })

        json_response = {
            "events": event_info,
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}
