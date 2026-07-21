# Kubernetes API endpoints for showing the state of the Kubernetes cluster
import os
from fastapi import APIRouter
from kubernetes import client, config
from kubernetes.stream import stream

router = APIRouter()

# ---------------------------------------------------------------------------
# Kubernetes config loading — tries in-cluster first (when running inside K8s)
# then falls back to KUBECONFIG env var or the default ~/.kube/config path.
# ---------------------------------------------------------------------------

def _load_kube_config():
    kubeconfig = os.environ.get("KUBECONFIG")
    try:
        config.load_incluster_config()
    except config.ConfigException:
        config.load_kube_config(config_file=kubeconfig)


_load_kube_config()


@router.get("/kubernetes", tags=["Kubernetes"])
async def kubernetes_info():
    """Get cluster version and API server URL."""
    try:
        v1 = client.VersionApi()
        version_info = v1.get_code()
        return {
            "version": version_info.git_version,
            "platform": version_info.platform,
        }
    except Exception as e:
        return {"error": str(e)}


@router.get("/kubernetes/pods", tags=["Kubernetes"])
async def get_pods():
    """Get all pods across all namespaces."""
    try:
        v1 = client.CoreV1Api()
        pods = v1.list_pod_for_all_namespaces()
        return {
            "pods": [
                {
                    "name": pod.metadata.name,
                    "namespace": pod.metadata.namespace,
                    "status": pod.status.phase,
                    "node": pod.spec.node_name,
                    "ready": all(
                        cs.ready for cs in (pod.status.container_statuses or [])
                    ),
                }
                for pod in pods.items
            ]
        }
    except Exception as e:
        return {"error": str(e)}


@router.get("/kubernetes/nodes", tags=["Kubernetes"])
async def get_nodes():
    """Get all nodes with their status conditions."""
    try:
        v1 = client.CoreV1Api()
        nodes = v1.list_node()
        return {
            "nodes": [
                {
                    "name": node.metadata.name,
                    "status": node.status.conditions[-1].type if node.status.conditions else "Unknown",
                    "ready": next(
                        (c.status for c in (node.status.conditions or []) if c.type == "Ready"),
                        "Unknown",
                    ),
                    "roles": [
                        k.split("/", 1)[1]
                        for k in (node.metadata.labels or {})
                        if k.startswith("node-role.kubernetes.io/")
                    ],
                }
                for node in nodes.items
            ]
        }
    except Exception as e:
        return {"error": str(e)}


@router.get("/kubernetes/services", tags=["Kubernetes"])
async def get_services():
    """Get all services across all namespaces."""
    try:
        v1 = client.CoreV1Api()
        services = v1.list_service_for_all_namespaces()
        return {
            "services": [
                {
                    "name": svc.metadata.name,
                    "namespace": svc.metadata.namespace,
                    "type": svc.spec.type,
                    "cluster_ip": svc.spec.cluster_ip,
                    "ports": [
                        {"port": p.port, "protocol": p.protocol, "target_port": str(p.target_port)}
                        for p in (svc.spec.ports or [])
                    ],
                }
                for svc in services.items
            ]
        }
    except Exception as e:
        return {"error": str(e)}


@router.get("/kubernetes/deployments", tags=["Kubernetes"])
async def get_deployments():
    """Get all deployments across all namespaces."""
    try:
        apps_v1 = client.AppsV1Api()
        deployments = apps_v1.list_deployment_for_all_namespaces()
        return {
            "deployments": [
                {
                    "name": d.metadata.name,
                    "namespace": d.metadata.namespace,
                    "replicas": d.spec.replicas,
                    "ready_replicas": d.status.ready_replicas,
                    "available_replicas": d.status.available_replicas,
                }
                for d in deployments.items
            ]
        }
    except Exception as e:
        return {"error": str(e)}


@router.get("/kubernetes/cluster-info", tags=["Kubernetes"])
async def get_cluster_info():
    """Get combined cluster info: version, node count, namespace count."""
    try:
        v1 = client.CoreV1Api()
        version_api = client.VersionApi()
        version_info = version_api.get_code()
        nodes = v1.list_node()
        namespaces = v1.list_namespace()
        return {
            "version": version_info.git_version,
            "platform": version_info.platform,
            "node_count": len(nodes.items),
            "namespace_count": len(namespaces.items),
        }
    except Exception as e:
        return {"error": str(e)}


@router.get("/kubernetes/events", tags=["Kubernetes"])
async def get_events(namespace: str = None):
    """Get events — optionally filtered by namespace, otherwise cluster-wide."""
    try:
        v1 = client.CoreV1Api()
        if namespace:
            events = v1.list_namespaced_event(namespace)
        else:
            events = v1.list_event_for_all_namespaces()
        return {
            "events": [
                {
                    "name": e.metadata.name,
                    "namespace": e.metadata.namespace,
                    "reason": e.reason,
                    "message": e.message,
                    "type": e.type,
                    "count": e.count,
                    "first_time": str(e.first_timestamp),
                    "last_time": str(e.last_timestamp),
                }
                for e in events.items
            ]
        }
    except Exception as e:
        return {"error": str(e)}


@router.get("/kubernetes/state", tags=["Kubernetes"])
async def get_kubernetes_state():
    """Get overall cluster state summary: nodes, pods, services, deployments."""
    try:
        v1 = client.CoreV1Api()
        apps_v1 = client.AppsV1Api()

        nodes = v1.list_node()
        pods = v1.list_pod_for_all_namespaces()
        services = v1.list_service_for_all_namespaces()
        deployments = apps_v1.list_deployment_for_all_namespaces()

        return {
            "nodes": [{"name": n.metadata.name, "status": n.status.conditions[-1].type} for n in nodes.items],
            "pods": [{"name": p.metadata.name, "namespace": p.metadata.namespace, "status": p.status.phase} for p in pods.items],
            "services": [{"name": s.metadata.name, "namespace": s.metadata.namespace, "type": s.spec.type} for s in services.items],
            "deployments": [{"name": d.metadata.name, "namespace": d.metadata.namespace, "replicas": d.spec.replicas} for d in deployments.items],
        }
    except Exception as e:
        return {"error": str(e)}


@router.get("/kubernetes/cluster-metrics", tags=["Kubernetes"])
async def get_cluster_metrics():
    """Get node capacity (CPU/memory) and pod resource requests."""
    try:
        v1 = client.CoreV1Api()

        nodes = v1.list_node()
        node_metrics = [
            {
                "name": n.metadata.name,
                "cpu_capacity": n.status.capacity.get("cpu"),
                "memory_capacity": n.status.capacity.get("memory"),
                "cpu_allocatable": n.status.allocatable.get("cpu"),
                "memory_allocatable": n.status.allocatable.get("memory"),
            }
            for n in nodes.items
        ]

        pods = v1.list_pod_for_all_namespaces()
        pod_metrics = []
        for pod in pods.items:
            for container in (pod.spec.containers or []):
                requests = (container.resources.requests or {}) if container.resources else {}
                pod_metrics.append({
                    "pod": pod.metadata.name,
                    "container": container.name,
                    "namespace": pod.metadata.namespace,
                    "cpu_request": requests.get("cpu"),
                    "memory_request": requests.get("memory"),
                })

        return {"node_metrics": node_metrics, "pod_metrics": pod_metrics}
    except Exception as e:
        return {"error": str(e)}


@router.get("/kubernetes/logs", tags=["Kubernetes"])
async def get_pod_logs(pod_name: str, namespace: str = "default", tail_lines: int = 100):
    """Get logs from a specific pod (optionally tail N lines)."""
    try:
        v1 = client.CoreV1Api()
        logs = v1.read_namespaced_pod_log(
            name=pod_name,
            namespace=namespace,
            tail_lines=tail_lines,
        )
        return {"pod_name": pod_name, "namespace": namespace, "logs": logs}
    except Exception as e:
        return {"error": str(e)}


@router.get("/kubernetes/exec", tags=["Kubernetes"])
async def exec_command_in_pod(pod_name: str, namespace: str = "default", command: str = "echo Hello"):
    """Execute a shell command inside a running pod."""
    try:
        v1 = client.CoreV1Api()
        resp = stream(
            v1.connect_get_namespaced_pod_exec,
            pod_name,
            namespace,
            command=["/bin/sh", "-c", command],
            stderr=True,
            stdin=False,
            stdout=True,
            tty=False,
        )
        return {"pod_name": pod_name, "namespace": namespace, "command": command, "output": resp}
    except Exception as e:
        return {"error": str(e)}


@router.get("/kubernetes/scale", tags=["Kubernetes"])
async def scale_deployment(deployment_name: str, namespace: str = "default", replicas: int = 1):
    """Scale a deployment to the specified number of replicas."""
    try:
        apps_v1 = client.AppsV1Api()
        scale = apps_v1.read_namespaced_deployment_scale(deployment_name, namespace)
        scale.spec.replicas = replicas
        apps_v1.replace_namespaced_deployment_scale(deployment_name, namespace, scale)
        return {"deployment_name": deployment_name, "namespace": namespace, "replicas": replicas}
    except Exception as e:
        return {"error": str(e)}


@router.get("/kubernetes/rollout", tags=["Kubernetes"])
async def rollout_status(deployment_name: str, namespace: str = "default"):
    """Get rollout status for a deployment."""
    try:
        apps_v1 = client.AppsV1Api()
        deployment = apps_v1.read_namespaced_deployment(deployment_name, namespace)
        return {
            "deployment_name": deployment.metadata.name,
            "namespace": deployment.metadata.namespace,
            "desired_replicas": deployment.spec.replicas,
            "ready_replicas": deployment.status.ready_replicas,
            "available_replicas": deployment.status.available_replicas,
            "unavailable_replicas": deployment.status.unavailable_replicas,
        }
    except Exception as e:
        return {"error": str(e)}


@router.get("/kubernetes/configmaps", tags=["Kubernetes"])
async def get_configmaps(namespace: str = None):
    """List ConfigMaps — cluster-wide if no namespace specified."""
    try:
        v1 = client.CoreV1Api()
        if namespace:
            cms = v1.list_namespaced_config_map(namespace)
        else:
            cms = v1.list_config_map_for_all_namespaces()
        return {
            "configmaps": [
                {"name": cm.metadata.name, "namespace": cm.metadata.namespace, "data_keys": list((cm.data or {}).keys())}
                for cm in cms.items
            ]
        }
    except Exception as e:
        return {"error": str(e)}


@router.get("/kubernetes/secrets", tags=["Kubernetes"])
async def get_secrets(namespace: str = None):
    """List Secrets (names and types only — never data). Cluster-wide if no namespace."""
    try:
        v1 = client.CoreV1Api()
        if namespace:
            secrets = v1.list_namespaced_secret(namespace)
        else:
            secrets = v1.list_secret_for_all_namespaces()
        return {
            "secrets": [
                {"name": s.metadata.name, "namespace": s.metadata.namespace, "type": s.type}
                for s in secrets.items
            ]
        }
    except Exception as e:
        return {"error": str(e)}


@router.get("/kubernetes/persistent-volumes", tags=["Kubernetes"])
async def get_persistent_volumes():
    """List all PersistentVolumes with capacity and status."""
    try:
        v1 = client.CoreV1Api()
        pvs = v1.list_persistent_volume()
        return {
            "persistent_volumes": [
                {
                    "name": pv.metadata.name,
                    "capacity": pv.spec.capacity,
                    "access_modes": pv.spec.access_modes,
                    "status": pv.status.phase,
                    "claim": (
                        f"{pv.spec.claim_ref.namespace}/{pv.spec.claim_ref.name}"
                        if pv.spec.claim_ref else None
                    ),
                }
                for pv in pvs.items
            ]
        }
    except Exception as e:
        return {"error": str(e)}


@router.get("/kubernetes/persistent-volume-claims", tags=["Kubernetes"])
async def get_persistent_volume_claims(namespace: str = None):
    """List PVCs — cluster-wide if no namespace specified."""
    try:
        v1 = client.CoreV1Api()
        if namespace:
            pvcs = v1.list_namespaced_persistent_volume_claim(namespace)
        else:
            pvcs = v1.list_persistent_volume_claim_for_all_namespaces()
        return {
            "persistent_volume_claims": [
                {
                    "name": pvc.metadata.name,
                    "namespace": pvc.metadata.namespace,
                    "status": pvc.status.phase,
                    "capacity": (pvc.status.capacity or {}).get("storage"),
                    "volume_name": pvc.spec.volume_name,
                }
                for pvc in pvcs.items
            ]
        }
    except Exception as e:
        return {"error": str(e)}


@router.get("/kubernetes/ingresses", tags=["Kubernetes"])
async def get_ingresses():
    """Get all Ingress resources across all namespaces."""
    try:
        networking_v1 = client.NetworkingV1Api()
        ingresses = networking_v1.list_ingress_for_all_namespaces()
        return {
            "ingresses": [
                {
                    "name": ing.metadata.name,
                    "namespace": ing.metadata.namespace,
                    "hosts": [rule.host for rule in (ing.spec.rules or []) if rule.host],
                    "tls": [
                        {"hosts": tls.hosts, "secret": tls.secret_name}
                        for tls in (ing.spec.tls or [])
                    ],
                }
                for ing in ingresses.items
            ]
        }
    except Exception as e:
        return {"error": str(e)}
