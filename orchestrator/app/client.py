# orchestrator/app/client.py
import httpx
import logging
from typing import List, Optional, Dict, Any

from .models import DiscoveredAgent, TransactionDetails, BigQueryResponse, DisputePolicyCheckResponse

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("A2AClient")

class A2AClient:
    def __init__(self, proxy_url: str):
        self.proxy_url = proxy_url.strip('/')
        self.http_client = httpx.AsyncClient(timeout=10.0)
        self.discovered_agents: Dict[str, DiscoveredAgent] = {} # agent_id: DiscoveredAgent

    async def close(self):
        await self.http_client.aclose()

    async def discover_agents(self, required_agent_ids: List[str] = None) -> bool:
        """
        Queries the proxy and updates internal agent registry.
        Returns True if all required_agent_ids are found and active.
        """
        discover_url = f"{self.proxy_url}/discover?only_active=true"
        try:
            response = await self.http_client.get(discover_url)
            response.raise_for_status()
            agents_list = response.json()
            self.discovered_agents.clear()
            found_agents = []
            for agent_data in agents_list:
                agent = DiscoveredAgent(**agent_data)
                self.discovered_agents[agent.agent_id] = agent
                found_agents.append(agent.agent_id)
                logger.info(f"Discovered Agent: {agent.agent_id} at {agent.base_url} (Status: {agent.status})")

            if not required_agent_ids:
                return bool(self.discovered_agents)

            missing = [agent_id for agent_id in required_agent_ids if agent_id not in self.discovered_agents]
            if missing:
                logger.warning(f"Missing required agents after discovery: {missing}. Found: {found_agents}")
                return False
            logger.info(f"All required agents discovered: {required_agent_ids}")
            return True

        except httpx.RequestError as e:
            logger.error(f"Failed to discover agents from proxy {self.proxy_url}: {e}")
        except Exception as e:
            logger.error(f"Error processing discovered agents: {e}", exc_info=True)

        return False

    def get_agent_url(self, agent_id: str) -> Optional[str]:
        agent = self.discovered_agents.get(agent_id)
        return agent.base_url.strip('/') if agent else None

    async def get_transaction_details(self, transaction_id: str) -> Optional[TransactionDetails]:
        agent_id = "Transaction_Detail_Agent"
        base_url = self.get_agent_url(agent_id)
        if not base_url:
            logger.error(f"{agent_id} not discovered.")
            return None

        url = f"{base_url}/get_transaction_details"
        params = {"transaction_id": transaction_id}
        try:
            response = await self.http_client.get(url, params=params)
            if response.status_code == 404:
                logger.warning(f"Transaction '{transaction_id}' not found via {agent_id}.")
                return None
            response.raise_for_status()
            return TransactionDetails(**response.json())
        except httpx.RequestError as e:
            logger.error(f"Error calling {agent_id} for tx details: {e}")
        except Exception as e:
            logger.error(f"Error processing tx details response: {e}", exc_info=True)
        return None

    async def query_transactions(self, sql: str) -> Optional[BigQueryResponse]:
        agent_id = "Transaction_Detail_Agent"
        base_url = self.get_agent_url(agent_id)
        if not base_url:
            logger.error(f"{agent_id} not discovered.")
            return None

        url = f"{base_url}/query_bigquery"
        payload = {"sql_query": sql}
        try:
            response = await self.http_client.post(url, json=payload)
            response.raise_for_status()
            return BigQueryResponse(**response.json())
        except httpx.RequestError as e:
            logger.error(f"Error calling {agent_id} for query: {e}")
        except Exception as e:
            logger.error(f"Error processing query response: {e}", exc_info=True)
        return None

    async def check_dispute_policy(self, transaction: TransactionDetails, reason: str) -> Optional[DisputePolicyCheckResponse]:
        agent_id = "Dispute_Policy_Agent"
        base_url = self.get_agent_url(agent_id)
        if not base_url:
            logger.error(f"{agent_id} not discovered.")
            return None

        url = f"{base_url}/check_dispute_policy"
        payload = {"transaction": transaction.model_dump(), "reason": reason}
        try:
            response = await self.http_client.post(url, json=payload)
            response.raise_for_status()
            return DisputePolicyCheckResponse(**response.json())
        except httpx.RequestError as e:
            logger.error(f"Error calling {agent_id} for policy check: {e}")
        except Exception as e:
            logger.error(f"Error processing policy check response: {e}", exc_info=True)
        return None