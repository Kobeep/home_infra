# Health check API - server state monitoring
import os
from fastapi import APIRouter
from sqlite3 import connect
from requests import get
import urllib3

# Disable warnings from unverified HTTPS requests
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

router = APIRouter()

# DB_PATH can be overridden by environment variable for portability.
# Default: /host/var/services/db.sqlite (in-container path via hostPath volume mount)
DB_PATH = os.environ.get("SERVICES_DB_PATH", "/host/var/services/db.sqlite")


@router.get("/health", tags=["Health"])
async def health_check():
    """
    Health check of all services registered in the k3s cluster.
    Reads service ingress hosts from the SQLite DB and checks HTTP reachability.
    """
    try:
        conn = connect(DB_PATH)
    except Exception as e:
        return {"error": f"Cannot open database at {DB_PATH}: {e}"}

    cursor = conn.cursor()
    cursor.execute("SELECT name, namespace, host FROM ingresses")
    services = cursor.fetchall()
    conn.close()

    health_results = []

    for ingress in services:
        name, namespace, host = ingress

        # Extract the first host if it is comma-separated
        primary_host = host.split(',')[0].strip() if host else ""

        if not primary_host or primary_host == "N/A":
            service_status = "unknown: no valid host"
        else:
            # Check HTTP/HTTPS reachability
            for scheme in ("https", "http"):
                try:
                    response = get(
                        f"{scheme}://{primary_host}",
                        verify=False,
                        timeout=5,
                        allow_redirects=True,
                    )
                    if response.status_code < 500:
                        service_status = f"running ({scheme} {response.status_code})"
                    else:
                        service_status = f"degraded: HTTP {response.status_code}"
                    break
                except Exception as e:
                    service_status = f"unreachable: {e}"

        health_results.append({
            "service_name": name,
            "namespace": namespace,
            "host": primary_host,
            "status": service_status,
        })

    return {"health_results": health_results}
