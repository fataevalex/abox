FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir uv

RUN uv pip install --system --no-cache-dir mcp-server-qdrant

ENV QDRANT_URL=""
ENV QDRANT_API_KEY=""
ENV COLLECTION_NAME="default-collection"
ENV EMBEDDING_MODEL="sentence-transformers/all-MiniLM-L6-v2"

CMD ["mcp-server-qdrant"]
