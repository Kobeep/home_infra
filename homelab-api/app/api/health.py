# Health check API - server state monitoring
from fastapi import APIRouter
from paramiko import SSHClient, AutoAddPolicy
from sqlite3 import connect
from requests import get
import urllib3

# Disable warnings from unverified HTTPS requests
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

router = APIRouter()

# Health check of all the services in the k3s cluster.
# Under path /host/var/services/db.sqlite we have all the addresses of the services in the k3s cluster. We will check if they are reachable via SSH and if they are running.

@router.get("/health", tags=["Health"])
async def health_check():
    # Connect to the SQLite database
    conn = connect("/host/var/services/db.sqlite")
    cursor = conn.cursor()

    # Query the database for all services
    cursor.execute("SELECT name, namespace, host FROM ingresses")
    services = cursor.fetchall()

    # Initialize a list to hold the health check results
    health_results = []

    # Iterate through each service and perform health checks
    for ingress in services:
        name, namespace, host = ingress

        # Extract the first host if it is comma-separated
        primary_host = host.split(',')[0].strip() if host else ""

        if not primary_host or primary_host == "N/A":
            ssh_status = "unreachable: No valid host"
            service_status = "not running: No valid host"
        else:
            # Check if the service is reachable via SSH
            ssh_client = SSHClient()
            ssh_client.set_missing_host_key_policy(AutoAddPolicy())
            try:
                ssh_client.connect(primary_host, port=22, timeout=5)
                ssh_status = "reachable"
            except Exception as e:
                ssh_status = f"unreachable: {str(e)}"
            finally:
                ssh_client.close()

            # Check if the service is running by sending an HTTP GET request
            try:
                # Use verify=False since services might use local/self-signed certs
                response = get(f"https://{primary_host}", verify=False, timeout=5)
                if response.status_code == 200:
                    service_status = "running"
                else:
                    service_status = f"not running: HTTP {response.status_code}"
            except Exception as e:
                service_status = f"not running: {str(e)}"

        # Append the results to the health_results list
        health_results.append({
            "service_name": name,
            "ssh_status": ssh_status,
            "service_status": service_status
        })

    # Close the database connection
    conn.close()

    return {"health_results": health_results}
