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

# agentgateway-external — main ingress
kubectl port-forward -n agentgateway-system svc/agentgateway-external 8080:80 &
echo "  agentgateway   → http://localhost:8080"

# kagent UI and API — direct, bypassing gateway
kubectl port-forward -n kagent svc/kagent-ui 8081:8080 &
echo "  kagent UI      → http://localhost:8081"
kubectl port-forward -n kagent svc/kagent-controller 8083:8083 &
echo "  kagent API     → http://localhost:8083"

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
