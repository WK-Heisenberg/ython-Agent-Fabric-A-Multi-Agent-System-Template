import asyncio
import httpx
import google.auth.transport.requests
import google.oauth2.id_token
import os
from datetime import datetime, timedelta, timezone
import logging
from typing import Dict, List, Optional

from .models import AgentInfo

# Logging is configured in main.py now, just get the logger
logger = logging.getLogger("Discovery")

active_agents: Dict[str, AgentInfo] = {} # Key: base_url
POLL_INTERVAL_SECONDS = 30
# Mark as inactive if not successfully polled for 3 intervals + a buffer
INACTIVE_THRESHOLD_SECONDS = POLL_INTERVAL_SECONDS * 3 + 5

# Lock for thread-safe access to active_agents (good practice even with asyncio if state could be accessed externally)
discovery_lock = asyncio.Lock()

# --- Authentication Helper ---

async def get_gcp_id_token(audience: str) -> Optional[str]:
    """Fetches a GCP Identity Token for the specified audience."""
    try:
        # Use default credentials (picks up service account in Cloud Run, or ADC locally)
        auth_req = google.auth.transport.requests.Request()
        id_token = google.oauth2.id_token.fetch_id_token(auth_req, audience)
        logger.debug(f"Successfully fetched ID token for audience: {audience}")
        return id_token
    except google.auth.exceptions.DefaultCredentialsError as e:
        logger.error(f"Could not find default credentials. Ensure you are running on Cloud Run "
                     f"with a service account or have run 'gcloud auth application-default login'. Error: {e}")
        return None
    except Exception as e:
        logger.error(f"Failed to fetch GCP ID token for audience {audience}: {e}", exc_info=True)
        return None

# --- Discovery Logic ---

async def poll_agent(client: httpx.AsyncClient, agent_url: str):
    """Polls a single agent's well-known endpoint."""
    global active_agents
    agent_wellknown_url = f"{agent_url.strip('/')}/.well-known/a2a/agent.json"
    headers = {}
    agent_id = None # Keep track of agent_id for logging even on failure

    try:
        # Fetch token if running in GCP environment (where default creds are available)
        token = await get_gcp_id_token(agent_url) # Use the agent's base URL as audience
        if token:
            headers["Authorization"] = f"Bearer {token}"
        else:
            logger.warning(f"Could not obtain ID token for polling {agent_url}. Proceeding without auth. "
                           f"This will likely fail if the target agent requires authentication.")

        logger.debug(f"Polling agent at {agent_wellknown_url} with headers: {list(headers.keys())}")
        response = await client.get(agent_wellknown_url, timeout=10.0, headers=headers)
        response.raise_for_status() # Raises HTTPStatusError for 4xx/5xx responses

        agent_json = response.json()
        agent_id = agent_json.get("id") # Get agent_id for logging
        if not agent_id:
            logger.warning(f"Agent at {agent_url} missing 'id' in agent.json response.")
            # Decide if you want to mark as unreachable or just ignore
            raise ValueError("Agent JSON missing 'id'") # Treat as an error for now

        async with discovery_lock:
            now = datetime.now(timezone.utc)
            active_agents[agent_url] = AgentInfo(
                agent_id=agent_id,
                base_url=agent_url,
                name=agent_json.get("name"),
                description=agent_json.get("description"),
                capabilities_url=agent_json.get("capabilities_url"),
                last_seen=now,
                status="active", # Mark as active on successful poll
                raw_agent_json=agent_json
            )
        logger.info(f"Successfully polled agent: {agent_id} at {agent_url}")
        return agent_id # Return agent_id on success

    except (httpx.TimeoutException, httpx.ConnectTimeout):
        logger.warning(f"Timeout polling agent {agent_id or 'unknown'} at {agent_url}")
    except httpx.ConnectError as e:
         logger.warning(f"Connection error polling agent {agent_id or 'unknown'} at {agent_url}: {e}")
    except httpx.HTTPStatusError as e:
        # Handle specific HTTP errors
        if e.response.status_code == 401:
            logger.error(f"Received 401 Unauthorized from {agent_url}. Token might be invalid, expired, missing, or audience incorrect.")
        elif e.response.status_code == 403:
            logger.error(f"Received 403 Forbidden from {agent_url}. Check proxy service account IAM permissions ('Cloud Run Invoker' role on target agent {agent_url}).")
        elif e.response.status_code == 404:
            logger.warning(f"Received 404 Not Found polling {agent_wellknown_url}. Agent endpoint might be incorrect or not deployed.")
        else:
            logger.warning(f"HTTP error {e.response.status_code} polling agent {agent_id or 'unknown'} at {agent_url}: {e}")
    except Exception as e:
        # Catch other potential errors like JSON decoding, ValueError from missing ID, etc.
        logger.error(f"Unexpected error polling agent {agent_id or 'unknown'} at {agent_url}: {e}", exc_info=True)

    # --- If any exception occurred, mark as unreachable ---
    async with discovery_lock:
        if agent_url in active_agents:
            # Only log if status changes from active to unreachable
            if active_agents[agent_url].status == "active":
                 logger.warning(f"Marking agent {active_agents[agent_url].agent_id} at {agent_url} as unreachable due to polling error.")
            active_agents[agent_url].status = "unreachable"
            # Keep the last known info but update status
            # Liveness check will eventually remove it if it stays unreachable

    return None # Return None on failure

async def check_agent_liveness():
    """Marks agents as inactive if not seen recently and removes very old ones."""
    global active_agents
    now = datetime.now(timezone.utc)
    inactive_since = now - timedelta(seconds=INACTIVE_THRESHOLD_SECONDS)
    # Define a longer threshold for complete removal
    very_old_since = now - timedelta(seconds=INACTIVE_THRESHOLD_SECONDS * 5) # e.g., 5 cycles
    agents_to_remove = []
    status_changed = False

    async with discovery_lock:
        for url, agent_info in active_agents.items():
            if agent_info.last_seen < very_old_since:
                agents_to_remove.append(url)
                status_changed = True
            # Mark as inactive if last seen is beyond the threshold AND it's currently active or unreachable
            # Note: We check against 'inactive' to avoid redundant logging if already inactive.
            elif agent_info.last_seen < inactive_since and agent_info.status != "inactive":
                agent_info.status = "inactive"
                logger.info(f"Agent '{agent_info.agent_id}' at {url} marked as inactive (last seen: {agent_info.last_seen}).")
                status_changed = True
            # REMOVED: The logic that incorrectly marked agents as active again based only on last_seen

        # Remove agents marked for removal
        for url in agents_to_remove:
            if url in active_agents:
                logger.warning(f"Removing very old unreachable/inactive agent: {active_agents[url].agent_id} at {url}")
                del active_agents[url]

    if status_changed:
         logger.debug(f"Agent liveness check complete. Current agents: {list(active_agents.keys())}")


async def continuous_polling_loop(agent_urls: List[str], client: httpx.AsyncClient):
    """The actual loop that polls agents and checks liveness periodically."""
    logger.info(f"Polling loop starting: every {POLL_INTERVAL_SECONDS}s for agents: {agent_urls}")
    while True:
        try:
            # Poll all agents concurrently
            tasks = [poll_agent(client, url) for url in agent_urls]
            results = await asyncio.gather(*tasks, return_exceptions=False) # Exceptions handled in poll_agent
            successful_polls = [agent_id for agent_id in results if agent_id is not None]
            logger.debug(f"Polling cycle completed. Successfully polled: {successful_polls}")

            # Check liveness after polling results are processed
            await check_agent_liveness()

            # Wait for the next interval
            await asyncio.sleep(POLL_INTERVAL_SECONDS)
        except asyncio.CancelledError:
            logger.info("Polling loop cancelled.")
            break
        except Exception as e:
            logger.error(f"Error in main polling loop: {e}", exc_info=True)
            # Avoid crashing the loop, wait before retrying
            await asyncio.sleep(POLL_INTERVAL_SECONDS)


async def start_continuous_polling():
    """Async entry point called by FastAPI startup to run the polling loop."""
    logger.info("Initializing continuous polling task...")
    agent_urls_str = os.getenv("AGENT_URLS")
    if not agent_urls_str:
        logger.warning("AGENT_URLS environment variable not set. No agents to poll.")
        return # Exit if no URLs

    agent_urls = [url.strip() for url in agent_urls_str.split(',') if url.strip()]
    if not agent_urls:
        logger.warning("No valid AGENT_URLS found after parsing the environment variable.")
        return

    # Create a single client session to reuse for polling
    # Consider adding retry logic to the client if needed:
    # transport = httpx.AsyncHTTPTransport(retries=2)
    # async with httpx.AsyncClient(transport=transport, follow_redirects=True) as client:
    async with httpx.AsyncClient(follow_redirects=True) as client:
        try:
            # Start and run the polling loop indefinitely (until cancelled)
            await continuous_polling_loop(agent_urls, client)
        except Exception as e:
             logger.error(f"Polling client encountered an unrecoverable error: {e}", exc_info=True)
        finally:
             logger.info("Polling client session closed.")


def get_active_agents() -> List[AgentInfo]:
    """Returns agents considered active (status is 'active')."""
    # We rely on the status field updated by polling and liveness checks
    return [
        info for info in active_agents.values() if info.status == "active"
    ]

def get_all_discovered_agents() -> List[AgentInfo]:
    """Returns all agents currently in the dictionary, regardless of status."""
    # Return a copy to prevent modification of the internal state
    return list(active_agents.values())
