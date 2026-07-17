# Infrastructer API to manage and monitor the home lab environment
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from api import health
from api import kubernetes

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

# CORS setup
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers for different API endpoints
app.include_router(health.router, prefix="/api/health", tags=["Health"])
app.include_router(kubernetes.router, prefix="/api/kubernetes", tags=["Kubernetes"])

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
        {"path": "/api/kubernetes/events", "description": "Get a list of all events in the Kubernetes cluster."},
        {"path": "/api/kubernetes/state", "description": "Get the current state of the Kubernetes cluster."},
        {"path": "/api/kubernetes/cluster-metrics", "description": "Get metrics about the Kubernetes cluster, such as CPU and memory usage."},
        {"path": "/api/kubernetes/logs", "description": "Get logs from a specific pod in the Kubernetes cluster."},
        {"path": "/api/kubernetes/exec", "description": "Execute a command in a specific pod in the Kubernetes cluster."},
        {"path": "/api/kubernetes/scale", "description": "Scale a deployment in the Kubernetes cluster."},
        {"path": "/api/kubernetes/rollout", "description": "Manage rollouts for deployments in the Kubernetes cluster."},
        {"path": "/api/kubernetes/configmaps", "description": "Get a list of all ConfigMaps in the Kubernetes cluster."},
        {"path": "/api/kubernetes/secrets", "description": "Get a list of all Secrets in the Kubernetes cluster."},
        {"path": "/api/kubernetes/persistent-volumes", "description": "Get a list of all PersistentVolumes in the Kubernetes cluster."},
        {"path": "/api/kubernetes/persistent-volume-claims", "description": "Get a list of all PersistentVolumeClaims in the Kubernetes cluster."},
    ]
    return {"endpoints": endpoints}
