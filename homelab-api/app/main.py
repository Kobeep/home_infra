import ipaddress
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from api import health, kubernetes

# Api setup
app = FastAPI(
    title="Home Lab API",
    description="API to manage and monitor the home lab environment",
    version="1.0.0",
    contact={
        "name": "Home Lab API",
        "url": "https://kobecloud.com",
        "email": "",
    },
    license_info={
        "name": "Apache 2.0",
        "url": "https://www.apache.org/licenses/LICENSE-2.0.html",
    },
)

# Include routers for different API endpoints
app.include_router(health.router, prefix="/api", tags=["Health"])
app.include_router(kubernetes.router, prefix="/api", tags=["Kubernetes"])

# list of available endpoints
@app.get("/api", tags=["API"])
async def list_endpoints():
    """
    List all available API endpoints.
    Returns a JSON response with the list of endpoints.
    """
    endpoints = [
        {"path": "/api/health", "description": "Health check endpoint to monitor the state of the machine."},
        # API/kubernetes endpoint for monitoring Kubernetes resources
        {"path": "/api/kubernetes", "description": "Kubernetes management endpoint to manage and monitor Kubernetes resources."},
        {"path": "/api/kubernetes/pods", "description": "Get a list of all pods in the Kubernetes cluster."},
        {"path": "/api/kubernetes/nodes", "description": "Get a list of all nodes in the Kubernetes cluster."},
        {"path": "/api/kubernetes/services", "description": "Get a list of all services in the Kubernetes cluster."},
        {"path": "/api/kubernetes/deployments", "description": "Get a list of all deployments in the Kubernetes cluster."},
        {"path": "/api/kubernetes/cluster-info", "description": "Get information about the Kubernetes cluster."},
        {"path": "/api/kubernetes/events/{deployment_name}/{namespace}", "description": "Get a list of all events in the Kubernetes cluster."},
        {"path": "/api/kubernetes/state", "description": "Get the current state of the Kubernetes cluster."},
        {"path": "/api/kubernetes/cluster-metrics", "description": "Get metrics about the Kubernetes cluster, such as CPU and memory usage."},
        {"path": "/api/kubernetes/logs/{pod_name}/{namespace}", "description": "Get logs from a specific pod in the Kubernetes cluster."},
        {"path": "/api/kubernetes/configmaps", "description": "Get a list of all ConfigMaps in the Kubernetes cluster."},
        {"path": "/api/kubernetes/secrets", "description": "Get a list of all Secrets in the Kubernetes cluster."},
        {"path": "/api/kubernetes/persistent-volumes", "description": "Get a list of all PersistentVolumes in the Kubernetes cluster."},
        {"path": "/api/kubernetes/persistent-volume-claims", "description": "Get a list of all PersistentVolumeClaims in the Kubernetes cluster."},
        {"path": "/api/kubernetes/ingresses", "description": "Get a list of all Ingresses in the Kubernetes cluster."},
        # Post endpoints for Kubernetes management
        {"path": "/api/kubernetes/rollout/{deployment_name}/{namespace}", "description": "Manage rollouts for deployments in the Kubernetes cluster."},
        {"path": "/api/kubernetes/kill/pods/{pod_name}/{namespace}", "description": "Delete a pod to simulate a failure."},
        {"path": "/api/kubernetes/kill/deployments/{deployment_name}/{namespace}", "description": "Delete a deployment to simulate a failure."},
        {"path": "/api/kubernetes/clean-cluster", "description": "Delete all resources in the cluster (except master nodes)."},
        {"path": "/api/kubernetes/exec/{pod_name}/{namespace}", "description": "Execute a command in a specific pod in the Kubernetes cluster."}
    ]
    return {"endpoints": endpoints}
