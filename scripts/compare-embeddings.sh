#!/bin/bash
# Compare embedding vectors from llama-cpp and ollama.
# Sends the same query to both endpoints and prints cosine similarity.
#
# Usage:
#   bash scripts/compare-embeddings.sh "your query text"
#   bash scripts/compare-embeddings.sh  # uses default query

set -euo pipefail

QUERY="${1:-kubernetes pod crashloopbackoff}"
LLAMA_URL="${LLAMA_URL:-http://localhost:8090}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"

echo "Query: \"${QUERY}\""
echo ""

# Get embedding from llama-cpp
echo "Fetching from llama-cpp..."
LLAMA_RESP=$(curl -sf "${LLAMA_URL}/v1/embeddings" \
  -H "Content-Type: application/json" \
  -d "{\"input\": \"${QUERY}\", \"model\": \"nomic-embed-text-v1.5\"}")

# Get embedding from ollama
echo "Fetching from ollama..."
OLLAMA_RESP=$(curl -sf "${OLLAMA_URL}/v1/embeddings" \
  -H "Content-Type: application/json" \
  -d "{\"input\": \"${QUERY}\", \"model\": \"nomic-embed-text\"}")

# Compare with python
python3 - <<EOF
import json, math

llama = json.loads('''${LLAMA_RESP}''')
ollama = json.loads('''${OLLAMA_RESP}''')

a = llama['data'][0]['embedding']
b = ollama['data'][0]['embedding']

if len(a) != len(b):
    print(f"Dimension mismatch: llama-cpp={len(a)}, ollama={len(b)}")
else:
    dot   = sum(x*y for x,y in zip(a,b))
    mag_a = math.sqrt(sum(x*x for x in a))
    mag_b = math.sqrt(sum(x*x for x in b))
    cos   = dot / (mag_a * mag_b)

    print(f"llama-cpp dimensions : {len(a)}")
    print(f"ollama    dimensions : {len(b)}")
    print(f"cosine similarity    : {cos:.6f}")
    print()
    if cos > 0.99:
        print("Vectors are nearly identical (same model weights)")
    elif cos > 0.90:
        print("Vectors are very similar")
    elif cos > 0.70:
        print("Vectors are somewhat similar")
    else:
        print("Vectors are different (different model or quantization)")
EOF
