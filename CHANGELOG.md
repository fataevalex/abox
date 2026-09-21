# Changelog

## [0.9.19] — lab03

### Added

**Документація**
- `docs/adr-001-embedding-model.md` — ADR: вибір runtime для embedding-інференсу.
  Порівняння llama.cpp vs Ollama на однаковій моделі `nomic-embed-text-v1.5`.
  Реальні benchmark результати (Codespaces, 4 CPU, 20 запитів sequential):
  - llama-cpp: 92ms avg, 10.35 req/s, без cold start
  - ollama: 178ms avg (1675ms cold start), 5.53 req/s
  - cosine similarity: 0.998025 (вектори практично ідентичні)
- `docs/adr-002-llmd-inference.md` — ADR: llm-d як production inference runtime.
  Порівняльна таблиця llama.cpp / ollama / llm-d. ToDo для розгортання через
  llm-d InferencePool + vLLM на GPU-кластері.
- `scripts/benchmark-embeddings.sh` — benchmark latency та throughput для обох рантаймів
- `scripts/compare-embeddings.sh` — cosine similarity порівняння векторів

**Кластерне розгортання**
- `releases/llama-cpp-embeddings.yaml` — Deployment + Service для nomic-embed-text-v1.5
  у namespace `llama-cpp`. Модель вбудована в образ, запускається без initContainer.
  Endpoint: `http://llama-cpp.llama-cpp:80/v1/embeddings`, dims: 768.
- `releases/ollama.yaml` — Deployment + Service для Ollama у namespace `ollama`.
  initContainer завантажує nomic-embed-text в emptyDir при старті.
  Endpoint: `http://ollama.ollama:80/v1/embeddings`, dims: 768.
- `releases/patches/k8s-agent-sidecar.yaml` — strategic merge patch: додає
  nomic-embed sidecar до k8s-agent Deployment у namespace kagent.
- `releases/embeddings-route.yaml` — HTTPRoute + ReferenceGrants для weighted routing
  через agentgateway: llama-cpp 80% / ollama 20% на `/v1/embeddings`.
- `releases/agent-embeddings.yaml` — kagent Agent CRD з системним промптом для
  розгортання, перевірки та troubleshooting embedding сервісу.

**Локальне розгортання**
- `docker-compose.yml` — локальний запуск llama-cpp на порту 8090.
  Volume монтується з `/tmp/abox-models` (root filesystem може бути обмежений).

**Kagent**
- `releases/kagent.yaml` — перемикання default-model-config на Gemini
  (`gemini-2.5-flash-lite`) замість OpenAI placeholder.

### Verified
- `GET /health` → `{"status":"ok"}` (llama-cpp) ✓
- `POST /v1/embeddings` → вектор розмірністю 768 ✓ (llama-cpp та ollama)
- Cosine similarity між llama-cpp та ollama: **0.998025** ✓
- `embeddings-agent` READY=True, ACCEPTED=True в кластері ✓
- Weighted HTTPRoute `/v1/embeddings` через agentgateway ✓
- OCI артефакт `ghcr.io/fataevalex/abox/releases:0.9.19` ✓

---

## [0.1.1] — 2026-09-16

### Changed
- Форкнуто репозиторій `den-vasyliev/abox` у `fataevalex/abox`
- Зібрано власний OCI-артефакт через GitHub Actions (`flux-push.yaml`) з тегом `v0.1.1`
- Стек abox розгорнуто з власного артефакту `ghcr.io/fataevalex/abox/releases:0.1.1`
