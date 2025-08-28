# proxy_server/Dockerfile
FROM python:3.10-slim

WORKDIR /app

COPY requirements.txt requirements.txt
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

COPY ./app /app/app

# Make port configurable through environment variable, default to 8000
ENV PORT 8000
ENV AGENT_URLS ""

EXPOSE $PORT

CMD uvicorn app.main:app --host 0.0.0.0 --port $PORT