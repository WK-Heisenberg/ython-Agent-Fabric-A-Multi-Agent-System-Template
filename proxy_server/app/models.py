# proxy_server/app/models.py
from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional, List, Dict, Any

class AgentInfo(BaseModel):
    agent_id: str
    base_url: str
    name: Optional[str] = None
    description: Optional[str] = None
    capabilities_url: Optional[str] = None
    last_seen: datetime
    status: str = "active"
    raw_agent_json: Optional[Dict[str, Any]] = None # Store full agent.json

class DiscoveredAgent(BaseModel):
    agent_id: str
    base_url: str
    name: Optional[str] = None
    description: Optional[str] = None
    capabilities_url: Optional[str] = None
    last_seen: datetime
    status: str

class HealthResponse(BaseModel):
    status: str = "ok"