#!/bin/bash
# Port-forward all abox web UIs to localhost.
# Run once; Ctrl-C stops all forwards.

set -euo pipefail

cleanup() {
  echo ""
  echo "Stopping all port-forwards..."
  kill 0
}
trap cleanup EXIT INT TERM

echo "Starting port-forwards..."
echo ""

# agentgateway admin UI (Envoy admin, port 15000 on the pod)
kubectl port-forward -n agentgateway-system \
  "$(kubectl get pod -n agentgateway-system -l gateway.networking.k8s.io/gateway-name=agentgateway-external -o jsonpath='{.items[0].metadata.name}')" \
  15000:15000 &
echo "  agentgateway   → http://localhost:15000"

# kagent UI and API
kubectl port-forward -n kagent svc/kagent-ui 8080:8080 &
echo "  kagent UI      → http://localhost:8080"
kubectl port-forward -n kagent svc/kagent-controller 8083:8083 &
echo "  kagent API     → http://localhost:8083"

# llama-cpp embeddings (service renamed to llama-cpp-embeddings in lab04)
kubectl port-forward -n llama-cpp svc/llama-cpp-embeddings 8090:8090 &
echo "  llama-cpp      → http://localhost:8090/v1/embeddings"

# Ollama embeddings
kubectl port-forward -n ollama svc/ollama 11434:80 &
echo "  ollama         → http://localhost:11434/v1/embeddings"

# MLflow — experiment tracking + LLM tracing (lab07)
kubectl port-forward -n mlflow svc/mlflow-mlflow 5000:5000 &
echo "  mlflow         → http://localhost:5000"

# OTel Demo — Astronomy Shop frontend (lab07)
kubectl port-forward -n otel-demo svc/frontend-proxy 8081:8080 &
echo "  otel-demo      → http://localhost:8081"

# Arize Phoenix — LLM observability
kubectl port-forward -n phoenix svc/phoenix-svc 6006:6006 &
echo "  phoenix        → http://localhost:6006"

# Qdrant — vector DB REST API + dashboard
kubectl port-forward -n qdrant svc/qdrant 6333:6333 &
echo "  qdrant         → http://localhost:6333/dashboard"

# Flux Operator web UI
kubectl port-forward -n flux-system svc/flux-operator 9080:9080 &
echo "  flux-operator  → http://localhost:9080"

echo ""
echo "Press Ctrl-C to stop all port-forwards."
wait
