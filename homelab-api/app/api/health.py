# Health check API - server state monitoring
from fastapi import APIRouter
import subprocess

router = APIRouter()

@router.get("/health", tags=["Health"])
async def health_check():
    """
    Health check endpoint to monitor the state of the machine.
    Returns a JSON response with the status of the machine.
    """
    try:
        # Run a simple command to check if the server is responsive
        subprocess.run(["echo", "Health check"], check=True)
        return {"status": "healthy"}
    except subprocess.CalledProcessError:
        return {"status": "unhealthy"}
