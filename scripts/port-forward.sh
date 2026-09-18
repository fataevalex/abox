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

# agentgateway — main ingress (kagent UI + API ride through this)
# All HTTPRoutes go through the agentgateway Gateway on port 80.
kubectl port-forward -n agentgateway-system svc/agentgateway 8080:80 &
echo "  agentgateway   → http://localhost:8080"
echo "    kagent UI    → http://localhost:8080/"
echo "    kagent API   → http://localhost:8080/api"

# Arize Phoenix — LLM observability
kubectl port-forward -n phoenix svc/phoenix 6006:6006 &
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
