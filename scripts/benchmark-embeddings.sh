#!/bin/bash
# Benchmark llama-cpp vs ollama embedding latency and throughput.
# Usage: bash scripts/benchmark-embeddings.sh [requests]

set -euo pipefail

REQUESTS="${1:-20}"
LLAMA_URL="${LLAMA_URL:-http://localhost:8090}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"

QUERIES=(
  "kubernetes pod crashloopbackoff"
  "how to configure resource limits in kubernetes"
  "flux cd gitops reconciliation"
  "qdrant vector database collection"
  "nomic embed text semantic search"
)

bench() {
  local name="$1"
  local url="$2"
  local model="$3"
  local total=0
  local errors=0

  echo "=== $name ==="
  echo "URL: $url/v1/embeddings"
  echo "Requests: $REQUESTS"
  echo ""

  local start_all
  start_all=$(date +%s%N)

  for i in $(seq 1 "$REQUESTS"); do
    local query="${QUERIES[$((( i - 1 ) % ${#QUERIES[@]}))]}"
    local t0
    t0=$(date +%s%N)

    if curl -sf "$url/v1/embeddings" \
        -H "Content-Type: application/json" \
        -d "{\"input\": \"$query\", \"model\": \"$model\"}" \
        -o /dev/null; then
      local t1
      t1=$(date +%s%N)
      local ms=$(( (t1 - t0) / 1000000 ))
      total=$((total + ms))
      echo "  [$i] ${ms}ms"
    else
      errors=$((errors + 1))
      echo "  [$i] ERROR"
    fi
  done

  local end_all
  end_all=$(date +%s%N)
  local wall_ms=$(( (end_all - start_all) / 1000000 ))
  local success=$((REQUESTS - errors))

  echo ""
  if [ "$success" -gt 0 ]; then
    echo "  avg latency : $((total / success)) ms"
    echo "  total wall  : ${wall_ms} ms"
    echo "  throughput  : $(python3 -c "print(f'{$success / ($wall_ms/1000):.2f}') ") req/s"
    echo "  errors      : $errors / $REQUESTS"
  else
    echo "  all requests failed"
  fi
  echo ""
}

bench "llama-cpp" "$LLAMA_URL" "nomic-embed-text-v1.5"
bench "ollama"    "$OLLAMA_URL" "nomic-embed-text"
