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

| Experiment | Джерело | Трейсів (зразок) |
|---|---|---|
| `otel-demo` (ID 1) | frontend-proxy, checkout, payment та ін. | безперервно від load generator |
| `kagent` (ID 2) | kagent-controller | 5 трейсів від k8s-agent запиту |

Трейси містять повний k8s контекст: `k8s.namespace.name`, `k8s.pod.name`,
`k8s.deployment.name`, `k8s.cluster.uid`, `container.image.tag`.

**Проблема стабільності**: SQLite write блокує uvicorn event loop під
навантаженням otel-demo (~25 сервісів) → liveness probe timeout.
Вирішено збільшенням `failureThreshold` з 5 до 10 (100s tolerance).

### Phoenix

| Метрика | Значення |
|---|---|
| Проект | `default` |
| Трейсів | 2368 (otel-demo + kagent) |
| Auth | Bearer JWT (auto-generated) |

Phoenix відображає LLM спани значно зручніше за MLflow: prompt/response
як читабельний текст замість raw JSON атрибутів.

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
| `make secrets` port conflict на :6006 | port-forward скрипт вже тримає порт | Тимчасовий форвард на :16006 |
| MLflow liveness probe timeout | SQLite блокує uvicorn event loop | failureThreshold: 5→10 |

---

## Посилання

- [Репозиторій fataevalex/abox](https://github.com/fataevalex/abox) (гілка `lab07`)
- [ADR-004: GenAI Observability](adr-004-genai-observability.md)
- [Upstream den-vasyliev/abox](https://github.com/den-vasyliev/abox)
- [MLflow Tracing docs](https://mlflow.org/docs/latest/llms/tracing/index.html)
- [Phoenix docs](https://docs.arize.com/phoenix)
- [OTel GenAI Semantic Conventions](https://opentelemetry.io/blog/2026/genai-observability/)
