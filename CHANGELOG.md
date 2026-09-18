# Changelog

## [Unreleased] — lab03

### Added
- `docs/adr-001-embedding-model.md` — ADR по вибору embedding-моделі для текстового пошуку. Обрано `nomic-ai/nomic-embed-text-v1.5` (GGUF) через llama.cpp: нативна підтримка GGUF, контекст 8k токенів, мінімальні ресурси (500m CPU / 512Mi RAM).
- `docs/todo-embedding-local.md` — інструкція запуску моделі локально через llama.cpp та Ollama з перевіркою `/v1/embeddings`.
- `docs/todo-embedding-cluster.md` — інструкція запуску моделі у кластері: standalone Deployment у namespace `llama-cpp`, через llm-d (InferencePool + EndpointPicker), та як sidecar-контейнер поруч з агентом.
- `releases/llama-cpp-embeddings.yaml` — Deployment + Service + HTTPRoute для nomic-embed-text-v1.5 у namespace `llama-cpp`. Образ `ghcr.io/den-vasyliev/abox/nomic-embed` містить llama-server та модель, запускається на порту 8090. Endpoint: `http://llama-cpp.llama-cpp.svc/v1/embeddings`, розмірність вектора: 768.

### Verified
- `GET /health` → `{"status":"ok"}`
- `POST /v1/embeddings` → вектор розмірністю 768 ✓

---

## [0.1.1] — 2026-09-16

### Changed
- Форкнуто репозиторій `den-vasyliev/abox` у `fataevalex/abox`
- Зібрано власний OCI-артефакт через GitHub Actions (`flux-push.yaml`) з тегом `v0.1.1`
- Стек abox розгорнуто з власного артефакту `ghcr.io/fataevalex/abox/releases:0.1.1`
