# agent_transaction_detail/app/models.py
from pydantic import BaseModel, Field
from typing import Optional, Dict, Any
from datetime import datetime

class TransactionDetails(BaseModel):
    transaction_id: str
    amount: float
    currency: str = "USD"
    merchant: str
    timestamp: datetime
    status: str = "completed"

class BigQueryRequest(BaseModel):
    sql_query: str = Field(..., example="SELECT * FROM transactions WHERE amount > 100 LIMIT 10")

class BigQueryResponse(BaseModel):
    row_count: int
    results: list[Dict[str, Any]]

class HealthResponse(BaseModel):
    status: str = "ok"