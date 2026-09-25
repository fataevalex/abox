# Lab07 — Звіт

## Мета

Розгорнути стек GenAI observability: OpenTelemetry Demo (Astronomy Shop),
MLflow Tracing та Arize Phoenix. Отримати трейси від Astronomy Shop agent
та kagent агентів. Порівняти три o11y рішення з точки зору GenAI.

Роботи виконані у власному репозиторії [fataevalex/abox](https://github.com/fataevalex/abox)
у гілці `lab07`, з підтягуванням маніфестів з upstream `den-vasyliev/abox`
(гілка `feat/triage`).

---

## Що зроблено

### 1. Інфраструктура

- **OpenTelemetry Demo (Astronomy Shop)** — еталонний мікросервісний застосунок
  OTel проекту (~25 сервісів), namespace `otel-demo`. Bundled backends (Jaeger,
  Prometheus, Grafana, OpenSearch) вимкнені для економії ресурсів (~1.7Gi RAM).
  Load generator активований (LOCUST_HEADLESS=false) для постійного трафіку.

- **MLflow v3.14.0** — ML-платформа з OTLP ingestion, namespace `mlflow`.
  SQLite backend + server-proxied artifacts на одному PVC. 2 uvicorn workers
  для ізоляції health check від trace ingestion.

- **Arize Phoenix 12.0.10** — LLM observability, namespace `phoenix`.
  PostgreSQL backend. Startup probe розширено до 10 хвилин (Alembic migrations
  на KinD повільніші за дефолтний 31s бюджет).

### 2. OTel Collector bridge (mlflow namespace)

Центральний fan-out хаб між джерелами трейсів і backends:

```
kagent        ──gRPC──►┐
                        otel-collector ──HTTP──► MLflow (exp 1 / exp 2)
otel-demo DaemonSet ──►┘               ──gRPC──► Phoenix
```

- **Routing connector** розподіляє спани по `k8s.namespace.name`:
  `otel-demo` → MLflow experiment `otel-demo` (ID 1),
  `kagent` → MLflow experiment `kagent` (ID 2)
- **Phoenix exporter** отримує всі спани паралельно через `otlp/phoenix`
  з Bearer auth (`${env:PHOENIX_API_KEY}` — читається з k8s Secret,
  не хардкодиться в конфіг)

### 3. Автоматизація секретів

`make secrets` — єдина команда для створення всіх секретів після `make run`:
- **Gemini API key** → Secret `gemini-gemini-2-5-flash-lite` (namespace kagent)
- **Phoenix API key** → автоматично генерується через GraphQL
  (`createUserApiKey` mutation), зберігається в Secret `phoenix-api-key`
  (namespace mlflow). Не потребує ручного управління між Codespace recreations.

### 4. Виправлення інфраструктури Codespaces

- **`make move-docker-to-tmp`** — переносить Docker data-root з `/var/lib/docker`
  на `/tmp/docker` (більший ext4 том). Інтегровано в `setup.sh` — спрацьовує
  автоматично при `make run`.
- **`make fix-docker-acl`** — виправляє ACL на `/tmp` що знімає `o+x` з
  розпакованих шарів контейнерів.

---

## Результати

### MLflow

Два MLflow experiments з живими трейсами:

| Experiment | Джерело | Трейсів |
|---|---|---|
| `otel-demo` (ID 1) | frontend-proxy, checkout, payment, fraud-detection та ін. | безперервно від load generator |
| `kagent` (ID 2) | kagent-controller | підтверджено через A2A API виклик |

Трейси містять повний k8s контекст: `k8s.namespace.name`, `k8s.pod.name`,
`k8s.deployment.name`, `k8s.cluster.uid`, `container.image.tag`.

**Проблема стабільності**: SQLite write блокує uvicorn event loop під
навантаженням otel-demo (~25 сервісів) → liveness probe timeout.
Вирішено збільшенням `failureThreshold` з 5 до 10 (100s tolerance).

### OTel Demo Chatbot (Astronomy Shop)

Chatbot переключено з OpenAI на Gemini через OpenAI-compatible endpoint
(`https://generativelanguage.googleapis.com/v1beta/openai/`). Chatbot
відповідає на запити про телескопи, будує кошик, виконує тулкол
`GET /api/products`. API key з Secret `gemini-api-key` (namespace `otel-demo`).

Обмеження: `agent` компонент не використовує OTel LLM instrumentation —
Gemini виклики відображаються як звичайні HTTP spans без `gen_ai.*` атрибутів.

### Phoenix

| Метрика | Значення |
|---|---|
| Проект | `default` |
| Трейсів | 28777+ (otel-demo + kagent) |
| Auth | Bearer JWT (auto-generated via `make secrets`) |

Phoenix отримує всі трейси через fan-out в otel-collector. Span viewer
зручніший за MLflow для аналізу розподілених трейсів. LLM-специфічні
атрибути (`gen_ai.*`) відсутні в поточних джерелах — для повноцінного
LLM observability потрібна OTel GenAI instrumentation в агентах.

### kagent A2A API

Підтверджено програмний виклик k8s-agent через A2A JSON-RPC:

```bash
POST /api/a2a/kagent/k8s-agent
{"jsonrpc":"2.0","id":1,"method":"message/send","params":{
  "message":{"messageId":"...","role":"user",
    "parts":[{"kind":"text","text":"list all pods in mlflow namespace"}],
    "contextId":"<session-id>"}}}
```

Агент відповів переліком подів, трейс зафіксовано в MLflow experiment `kagent`.

### ADR-004

Повне порівняння трьох рішень задокументовано в
[docs/adr-004-genai-observability.md](adr-004-genai-observability.md).

**Висновок**: Phoenix — основний інструмент для GenAI observability (рідна
підтримка LLM span types, онлайн eval, зручний UI). MLflow — для ML
experiment tracking і кореляції трейсів з model runs.

---

## Технічні проблеми та вирішення

| Проблема | Причина | Рішення |
|---|---|---|
| Docker data-root переповнює `/` | KinD образи ~10GB, `/` = 32G overlay | move-docker-to-tmp скрипт |
| `systemctl` exit 0 але dockerd не зупиняється | В Codespaces немає systemd | Перевірка стану сокета, `pkill dockerd` |
| MLflow `/v1/traces` 404 | Experiments не створені | `POST /api/2.0/mlflow/experiments/create` до старту трафіку |
| curl на :5000 → AirTunes | macOS AirPlay Receiver займає порт 5000 | MLflow port-forward на :5001 |
| Phoenix 401 на OTLP | Auth обов'язковий навіть при `auth.enabled: false` | GraphQL API key + Bearer header в collector |
| `make secrets` port conflict на :6006 | port-forward скрипт вже тримає порт | Тимчасовий форвард на :16006, `fuser -k` перед bind |
| MLflow liveness probe timeout | SQLite блокує uvicorn event loop | failureThreshold: 5→10 |
| otel-demo chatbot 500 | OpenAI key відсутній | Переключено на Gemini (`LLM_BASE_URL` + `LLM_MODEL` override, `USE_VCR=False`) |
| Gemini 404 з `gemini/` prefix | litellm routing syntax ≠ model name | Прибрано prefix: `gemini-2.5-flash-lite` |
| kagent API 404 на `/api/sessions/{id}/runs` | kagent використовує A2A JSON-RPC, не REST runs | `POST /api/a2a/{ns}/{name}` з `method: message/send` |
| MLflow ngrok "Invalid Host header" | DNS-rebinding guard блокує ngrok Host | Додано `*.ngrok-free.dev` в `allowed-hosts` (fnmatch wildcard) |

---

## Публічний доступ (ngrok)

MLflow UI доступний публічно через ngrok free tier:

```bash
make ngrok-mlflow   # встановлює ngrok якщо потрібно, запускає тунель
```

MLflow's DNS-rebinding guard (`fastapi_security`) налаштований з wildcard
`*.ngrok-free.dev` — автоматично приймає будь-який ngrok free-tier URL без
зміни конфігурації при кожному перезапуску тунелю.

## Посилання

- [Репозиторій fataevalex/abox](https://github.com/fataevalex/abox) (гілка `lab07`)
- [ADR-004: GenAI Observability](adr-004-genai-observability.md)
- [Upstream den-vasyliev/abox](https://github.com/den-vasyliev/abox)
- [MLflow Tracing docs](https://mlflow.org/docs/latest/llms/tracing/index.html)
- [Phoenix docs](https://docs.arize.com/phoenix)
- [OTel GenAI Semantic Conventions](https://opentelemetry.io/blog/2026/genai-observability/)
