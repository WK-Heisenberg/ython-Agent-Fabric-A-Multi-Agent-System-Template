# orchestrator/Dockerfile
FROM python:3.10-slim

WORKDIR /app

COPY requirements.txt requirements.txt
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

COPY ./app /app/app

ENV PROXY_URL "http://proxy_server:8000"
ENV TEST_TX_ID "TX12345"
ENV TEST_REASON "Duplicate transaction."

# Keeps container running if needed, or use CMD for single run
CMD ["python", "app/main.py", "--txid", "$TEST_TX_ID", "--reason", "$TEST_REASON"]
# To run interactively: docker run --env PROXY_URL=... orchestrator_image python app/main.py --txid TX... --reason "..."