# Health check API - server state monitoring
from fastapi import APIRouter
import subprocess

router = APIRouter()

# Check state of machine : uptime, load, memory, disk, network
@router.get("/", tags=["Health"])
async def health_check():
    """
    Health check endpoint to monitor the state of the machine.
    Returns uptime, load, memory, disk, and network information.
    """
    # Implement logic to gather health metrics here and return them as a JSON response
    health_metrics = {
        "uptime": subprocess.run(["uptime"], capture_output=True, text=True).stdout.strip(),
        "load": subprocess.run(["cat", "/proc/loadavg"], capture_output=True, text=True).stdout.strip(),
        "memory": subprocess.run(["free", "-h"], capture_output=True, text=True).stdout.strip(),
        "disk": subprocess.run(["df", "-h", "/host"], capture_output=True, text=True).stdout.strip(),
        "network": subprocess.run(["ifconfig"], capture_output=True, text=True).stdout.strip(),
    }
    json_response = {
        "uptime": health_metrics["uptime"],
        "load": health_metrics["load"],
        "memory": health_metrics["memory"],
        "disk": health_metrics["disk"],
        "network": health_metrics["network"],
    }
    return json_response
