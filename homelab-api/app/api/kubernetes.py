# Kubernetes API endpoints for showing the state of the Kubernetes cluster
from fastapi import APIRouter
from kubernetes import client, config

router = APIRouter()

@router.get("/kubernetes", tags=["Kubernetes"])
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

@router.get("/kubernetes/pods", tags=["Kubernetes"])
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

@router.get("/kubernetes/nodes", tags=["Kubernetes"])
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

@router.get("/kubernetes/services", tags=["Kubernetes"])
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

@router.get("/kubernetes/deployments", tags=["Kubernetes"])
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

@router.get("/kubernetes/cluster-info", tags=["Kubernetes"])
async def get_cluster_info():
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

@router.get("/kubernetes/events", tags=["Kubernetes"])
async def get_events():
    """
    Get a list of events in the Kubernetes cluster.
    Returns event names, namespaces, reasons, and messages in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        v1 = client.CoreV1Api()
        events = v1.list_event_for_all_namespaces()
        event_info = []
        for event in events.items:
            event_info.append({
                "name": event.metadata.name,
                "namespace": event.metadata.namespace,
                "reason": event.reason,
                "message": event.message,
            })
        json_response = {
            "events": event_info
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}

@router.get("/kubernetes/state", tags=["Kubernetes"])
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

@router.get("/kubernetes/cluster-metrics", tags=["Kubernetes"])
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

@router.get("/kubernetes/logs", tags=["Kubernetes"])
async def get_pod_logs(pod_name: str, namespace: str = "default"):
    """
    Get logs from a specific pod in the Kubernetes cluster.
    Returns the logs of the specified pod in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        v1 = client.CoreV1Api()

        # Get pod logs
        logs = v1.read_namespaced_pod_log(name=pod_name, namespace=namespace)
        json_response = {
            "pod_name": pod_name,
            "namespace": namespace,
            "logs": logs,
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}

@router.get("/kubernetes/exec", tags=["Kubernetes"])
async def exec_command_in_pod(pod_name: str, namespace: str = "default", command: str = "echo Hello"):
    """
    Execute a command in a specific pod in the Kubernetes cluster.
    Returns the output of the command executed in the specified pod in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        v1 = client.CoreV1Api()

        # Execute command in pod
        exec_command = [
            '/bin/sh',
            '-c',
            command
        ]
        resp = client.stream.stream(v1.connect_get_namespaced_pod_exec,
                                     pod_name,
                                     namespace,
                                     command=exec_command,
                                     stderr=True, stdin=False,
                                     stdout=True, tty=False)
        json_response = {
            "pod_name": pod_name,
            "namespace": namespace,
            "command": command,
            "output": resp,
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}

@router.get("/kubernetes/scale", tags=["Kubernetes"])
async def scale_deployment(deployment_name: str, namespace: str = "default", replicas: int = 1):
    """
    Scale a deployment in the Kubernetes cluster.
    Returns the new number of replicas for the specified deployment in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        apps_v1 = client.AppsV1Api()

        # Scale deployment
        scale = apps_v1.read_namespaced_deployment_scale(deployment_name, namespace)
        scale.spec.replicas = replicas
        apps_v1.replace_namespaced_deployment_scale(deployment_name, namespace, scale)

        json_response = {
            "deployment_name": deployment_name,
            "namespace": namespace,
            "replicas": replicas,
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}

@router.get("/kubernetes/rollout", tags=["Kubernetes"])
async def rollout_status(deployment_name: str, namespace: str = "default"):
    """
    Get the rollout status of a deployment in the Kubernetes cluster.
    Returns the current rollout status of the specified deployment in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        apps_v1 = client.AppsV1Api()

        # Get rollout status
        deployment = apps_v1.read_namespaced_deployment(deployment_name, namespace)
        rollout_status = {
            "deployment_name": deployment.metadata.name,
            "namespace": deployment.metadata.namespace,
            "replicas": deployment.spec.replicas,
            "available_replicas": deployment.status.available_replicas,
            "unavailable_replicas": deployment.status.unavailable_replicas,
        }
        return rollout_status
    except Exception as e:
        return {"error": str(e)}

@router.get("/kubernetes/configmaps", tags=["Kubernetes"])
async def get_configmaps(namespace: str = "default"):
    """
    Get a list of ConfigMaps in the Kubernetes cluster.
    Returns ConfigMap names and their data in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        v1 = client.CoreV1Api()

        # Get ConfigMaps
        configmaps = v1.list_namespaced_config_map(namespace)
        configmap_info = []
        for configmap in configmaps.items:
            configmap_info.append({
                "name": configmap.metadata.name,
                "data": configmap.data,
            })
        json_response = {
            "configmaps": configmap_info
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}

@router.get("/kubernetes/secrets", tags=["Kubernetes"])
async def get_secrets(namespace: str = "default"):
    """
    Get a list of Secrets in the Kubernetes cluster.
    Returns Secret names and their types in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        v1 = client.CoreV1Api()

        # Get Secrets
        secrets = v1.list_namespaced_secret(namespace)
        secret_info = []
        for secret in secrets.items:
            secret_info.append({
                "name": secret.metadata.name,
                "type": secret.type,
            })
        json_response = {
            "secrets": secret_info
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}

@router.get("/kubernetes/persistent-volumes", tags=["Kubernetes"])
async def get_persistent_volumes():
    """
    Get a list of Persistent Volumes in the Kubernetes cluster.
    Returns Persistent Volume names and their capacities in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        v1 = client.CoreV1Api()

        # Get Persistent Volumes
        pvs = v1.list_persistent_volume()
        pv_info = []
        for pv in pvs.items:
            pv_info.append({
                "name": pv.metadata.name,
                "capacity": pv.spec.capacity,
            })
        json_response = {
            "persistent_volumes": pv_info
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}

@router.get("/kubernetes/persistent-volume-claims", tags=["Kubernetes"])
async def get_persistent_volume_claims(namespace: str = "default"):
    """
    Get a list of Persistent Volume Claims in the Kubernetes cluster.
    Returns Persistent Volume Claim names and their statuses in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        v1 = client.CoreV1Api()

        # Get Persistent Volume Claims
        pvcs = v1.list_namespaced_persistent_volume_claim(namespace)
        pvc_info = []
        for pvc in pvcs.items:
            pvc_info.append({
                "name": pvc.metadata.name,
                "status": pvc.status.phase,
            })
        json_response = {
            "persistent_volume_claims": pvc_info
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}

@router.get("/kubernetes/ingresses", tags=["Kubernetes"])
async def get_ingresses(namespace: str = "default"):
    """
    Get a list of Ingresses in the Kubernetes cluster.
    Returns Ingress names, pod, and their Address in JSON format.
    """
    try:
        # Load Kubernetes configuration
        config.load_kube_config()
        networking_v1 = client.NetworkingV1Api()

        # Get Ingresses
        ingresses = networking_v1.list_namespaced_ingress(namespace)
        ingress_info = []
        for ingress in ingresses.items:
            ingress_info.append({
                "name": ingress.metadata.name,
                "address": ingress.status.load_balancer.ingress[0].ip if ingress.status.load_balancer.ingress else None,
            })
        json_response = {
            "ingresses": ingress_info
        }
        return json_response
    except Exception as e:
        return {"error": str(e)}
