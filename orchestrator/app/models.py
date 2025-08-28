# orchestrator/app/models.py
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime
from enum import Enum

class PolicyDecisionEnum(str, Enum):
    APPROVED = "Approved"
    REJECTED = "Rejected"
    NEEDS_REVIEW = "NeedsReview"

# --- Models for Agent Capabilities (as expected by Orchestrator) ---
class TransactionDetails(BaseModel):
    transaction_id: str
    amount: float
    currency: str = "USD"
    merchant: str
    timestamp: datetime
    status: str = "completed"

class BigQueryResponse(BaseModel):
    row_count: int
    results: list[Dict[str, Any]]

class DisputePolicyCheckResponse(BaseModel):
    dispute_id: str
    transaction_id: str
    policy_decision: PolicyDecisionEnum
    reasoning: str
    next_steps: Optional[str] = None

# --- Models for interacting with Proxy ---
class DiscoveredAgent(BaseModel):
    agent_id: str
    base_url: str
    name: Optional[str] = None
    description: Optional[str] = None
    capabilities_url: Optional[str] = None
    last_seen: datetime
    status: str