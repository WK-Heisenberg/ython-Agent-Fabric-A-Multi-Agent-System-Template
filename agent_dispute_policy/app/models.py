# agent_dispute_policy/app/models.py
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
from enum import Enum

class PolicyDecisionEnum(str, Enum):
    APPROVED = "Approved"
    REJECTED = "Rejected"
    NEEDS_REVIEW = "NeedsReview"

class TransactionDetails(BaseModel):
    transaction_id: str
    amount: float
    currency: str = "USD"
    merchant: str
    timestamp: datetime
    status: str = "completed"

class DisputePolicyCheckRequest(BaseModel):
    transaction: TransactionDetails
    reason: str = Field(..., example="Product not received")
    customer_notes: Optional[str] = None

class DisputePolicyCheckResponse(BaseModel):
    dispute_id: str
    transaction_id: str
    policy_decision: PolicyDecisionEnum = Field(..., description="The decision based on the policy check.")
    reasoning: str
    next_steps: Optional[str] = None

class HealthResponse(BaseModel):
    status: str = "ok"