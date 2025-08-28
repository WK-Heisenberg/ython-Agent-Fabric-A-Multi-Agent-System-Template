# agent_transaction_detail/app/main.py
import os
import logging
from fastapi import FastAPI, HTTPException, Query
from fastapi.staticfiles import StaticFiles
from pathlib import Path
from datetime import datetime
import yaml

from .models import TransactionDetails, BigQueryRequest, BigQueryResponse, HealthResponse

logger = logging.getLogger(__name__)

app = FastAPI(
    title="Transaction Detail Agent",
    description="Provides transaction details and simulated BigQuery access.",
    version="0.1.0"
)

# --- Pydantic models defined in models.py ---

# --- Mock Data ---
MOCK_TRANSACTIONS = {
    "TX12345": TransactionDetails(transaction_id="TX12345", amount=150.75, currency="USD", merchant="Coffee Shop", timestamp=datetime(2023, 10, 26, 10, 30, 0), status="completed"),
    "TX67890": TransactionDetails(transaction_id="TX67890", amount=25.00, currency="USD", merchant="Bookstore", timestamp=datetime(2023, 10, 25, 15, 0, 0), status="completed"),
    "TX11223": TransactionDetails(transaction_id="TX11223", amount=500.00, currency="USD", merchant="Electronics Store", timestamp=datetime(2023, 10, 27, 11, 0, 0), status="pending"),
}

# --- Static files for .well-known/a2a ---
well_known_path = Path(__file__).parent / "well_known"
openapi_path = well_known_path / "a2a" / "openapi.yaml"

if openapi_path.exists():
    with open(openapi_path, 'r', encoding='utf-8') as f:
        openapi_spec = yaml.safe_load(f)
    app.openapi_schema = openapi_spec
else:
    logger.warning(f"OpenAPI spec not found at {openapi_path}")

app.mount("/.well-known", StaticFiles(directory=well_known_path, html=True), name="well-known")

@app.get("/healthz", response_model=HealthResponse, tags=["Health"])
async def health_check():
    return HealthResponse(status="ok")

@app.get("/get_transaction_details",
          response_model=TransactionDetails,
          summary="Get Transaction Details by ID",
          operation_id="get_transaction_details_get",
          tags=["A2ACapabilities"])
async def get_transaction_details(transaction_id: str = Query(..., description="The ID of the transaction to retrieve.")):
    """
    Retrieves details for a specific transaction ID from mock data.
    """
    if transaction_id in MOCK_TRANSACTIONS:
        return MOCK_TRANSACTIONS[transaction_id]
    else:
        raise HTTPException(status_code=404, detail=f"Transaction '{transaction_id}' not found")

@app.post("/query_bigquery",
           response_model=BigQueryResponse,
           summary="Query Transactions (Simulated BigQuery)",
           operation_id="query_bigquery_post",
           tags=["A2ACapabilities"])
async def query_bigquery(request: BigQueryRequest):
    """
    Simulates running a SQL query. In a real scenario, this would interact with BigQuery.
    For now, it returns some mock data if the query contains 'amount >'.
    """
    logger.info(f"Received BigQuery request: {request.sql_query}")
    if "amount >" in request.sql_query.lower() or "merchant" in request.sql_query.lower():
        results = [tx.model_dump() for tx in MOCK_TRANSACTIONS.values() if tx.amount > 100 or "store" in tx.merchant.lower()]
        if "limit" in request.sql_query.lower():
             try:
                limit = int(request.sql_query.lower().split("limit")[1].strip().split()[0])
                results = results[:limit]
             except:
                pass # ignore if limit cannot be parsed
        return BigQueryResponse(row_count=len(results), results=results)
    else:
        results = list(MOCK_TRANSACTIONS.values())[:2] # return first 2 if no specific condition
        return BigQueryResponse(row_count=len(results), results=[r.model_dump() for r in results])

if __name__ == "__main__":
    import uvicorn
    from dotenv import load_dotenv
    load_dotenv(dotenv_path="../../.env")
    port = int(os.getenv("AGENT_TRANSACTION_PORT", 8001))
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")