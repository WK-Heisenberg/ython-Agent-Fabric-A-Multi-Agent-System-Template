import os
import asyncio
import logging
from fastapi import FastAPI, HTTPException, status
from typing import List
from dotenv import load_dotenv, find_dotenv

from .models import AgentInfo, DiscoveredAgent, HealthResponse
from .discovery import start_continuous_polling, get_active_agents, get_all_discovered_agents

# Configure logging early
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Load .env file for local execution - using find_dotenv for robustness
dotenv_path = find_dotenv()
if dotenv_path:
    load_dotenv(dotenv_path=dotenv_path)
    logger.info(f".env file found and loaded from: {dotenv_path}")
else:
    logger.info("Running without .env file (expected in container/cloud run).")

app = FastAPI(
    title="A2A Discovery Proxy Server",
    description="Discovers and provides a list of active A2A agents.",
    version="0.1.0"
)

@app.on_event("startup")
async def startup_event():
    logger.info("Executing FastAPI startup event...")
    try:
        # Schedule the background polling task using asyncio's recommended way
        asyncio.create_task(start_continuous_polling())
        logger.info("Background polling task scheduled successfully.")
    except Exception as e:
        logger.error(f"Error scheduling background polling task during startup: {e}", exc_info=True)
        # Depending on the severity, you might want to raise the exception
        # or prevent the app from fully starting if polling is critical.

@app.get("/healthz", response_model=HealthResponse, tags=["Health"], status_code=status.HTTP_200_OK)
async def health_check():
    """
    Simple health check endpoint. Returns 200 OK if the server is running.
    """
    # In a real scenario, you might add checks here:
    # - Check if the background polling task is still running
    # - Check database connections if applicable
    return HealthResponse(status="ok")

@app.get("/discover", response_model=List[DiscoveredAgent], tags=["Discovery"])
async def discover_agents(only_active: bool = True):
    """
    Returns a list of discovered A2A agents.
    By default, returns only agents considered 'active'.
    Use ?only_active=false to see all ever discovered agents with their status.
    """
    if only_active:
        agents = get_active_agents()
        # Convert AgentInfo to DiscoveredAgent for the response model
        return [DiscoveredAgent(**agent.model_dump(exclude={'raw_agent_json'})) for agent in agents]
    else:
        all_agents = get_all_discovered_agents()
        # Convert AgentInfo to DiscoveredAgent for the response model
        return [DiscoveredAgent(**agent.model_dump(exclude={'raw_agent_json'})) for agent in all_agents]

@app.get("/discover/raw", response_model=List[AgentInfo], tags=["Discovery"], include_in_schema=False)
async def discover_agents_raw():
    """Returns raw internal representation of agents (for debugging)."""
    return get_all_discovered_agents()


if __name__ == "__main__":
    import uvicorn
    # Use PORT environment variable for Cloud Run compatibility, default to 8000 locally
    DEFAULT_PORT = 8000
    try:
        port = int(os.getenv("PORT", DEFAULT_PORT))
    except ValueError:
        logger.warning(f"Warning: Invalid PORT value '{os.getenv('PORT')}'. Falling back to default port {DEFAULT_PORT}.")
        port = DEFAULT_PORT

    logger.info(f"Attempting to start proxy locally on host 0.0.0.0, port: {port}")
    logger.info(f"AGENT_URLS for polling: {os.getenv('AGENT_URLS')}")
    # Use log_level="info" or "debug" for more verbose output during local development
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")
