# ADR-004: GenAI Observability — порівняння OTel Demo / MLflow / Phoenix

## Контекст

Lab07 розгортає три o11y рішення паралельно для порівняння їх можливостей
з точки зору GenAI спостережуваності:

- **OpenTelemetry Demo (Astronomy Shop)** — еталонний мікросервісний застосунок
  від OTel проекту з вбудованим AI агентом (`agent` компонент, переключений на
  Gemini через OpenAI-compatible endpoint)
- **MLflow Tracing** — ML-платформа з підтримкою OTLP ingestion (з v3.x),
  фокус на ML experiments і model lifecycle
- **Arize Phoenix** — спеціалізований LLM observability інструмент,
  фокус на GenAI трейсингу, оцінці якості відповідей і аналізі промптів

## Архітектура збору трейсів

```
kagent (gRPC :4317)
        │
        ▼
otel-collector (mlflow ns)
        │
        ├──► MLflow /v1/traces (HTTP)   x-mlflow-experiment-id: "2"
        └──► Phoenix :4317 (gRPC)       Bearer <api-key>

otel-demo collector (DaemonSet)
        │  kube_attributes processor додає k8s.namespace.name
        ▼
otel-collector (mlflow ns)
        │
        ├──► MLflow /v1/traces (HTTP)   x-mlflow-experiment-id: "1"
        └──► Phoenix :4317 (gRPC)       Bearer <api-key>
```

Routing connector в otel-collector розподіляє спани по `k8s.namespace.name`:
`otel-demo` → experiment 1, `kagent` → experiment 2. Phoenix отримує всі спани
в єдиний проект `default`.

## Спостереження

### OpenTelemetry (стандарт)

OTel є протоколом і SDK, а не самостійним UI. В otel-demo роль UI виконував
Jaeger (вимкнений для економії ресурсів). Ключові спостереження:

- **Сильні сторони**: вендор-незалежний стандарт, будь-який backend приймає OTLP,
  rich semantic conventions для HTTP/DB/messaging
- **GenAI підтримка**: OTel GenAI semantic conventions (draft, 2026) стандартизують
  атрибути `gen_ai.system`, `gen_ai.request.model`, `gen_ai.usage.input_tokens`
  тощо — але підтримка в SDK ще нерівномірна
- **Слабкі сторони**: без спеціалізованого UI немає prompt/response inspection,
  немає оцінки якості відповідей, немає агрегації по моделях

### MLflow Tracing

MLflow v3.x додав OTLP ingestion і Traces UI поверх своєї ML-платформи.

| Характеристика | Оцінка |
|---|---|
| OTLP ingestion | ✅ HTTP `/v1/traces` |
| Routing по experiment | ✅ `x-mlflow-experiment-id` header |
| Span viewer | ✅ waterfall view з атрибутами |
| Prompt/response | ⚠️ тільки якщо SDK логує як span attributes |
| Model metrics | ✅ рідний ML tracking (runs, params, metrics) |
| LLM eval | ✅ MLflow Evaluate API (офлайн) |
| GenAI focus | ⚠️ вторинна фіча поверх ML платформи |
| Стабільність під навантаженням | ⚠️ SQLite блокує uvicorn event loop при >25 сервісах |

**Спостереження з кластеру**: kagent-controller трейси надійшли з правильними
k8s атрибутами. otel-demo трейси (frontend-proxy та інші ~25 сервісів) містять
повний k8s контекст: pod, replicaset, deployment, node, cluster.uid.

kagent API (A2A JSON-RPC `message/send`) успішно викликаний програмно — агент
відповів про поди в mlflow namespace, трейси з'явились в experiment `kagent`.

MLflow зручний якщо вже використовується для ML-експериментів — трейси
інтегруються в той самий UI де живуть runs і моделі.

### Arize Phoenix

Phoenix — спеціалізований LLM observability інструмент від Arize AI.

| Характеристика | Оцінка |
|---|---|
| OTLP ingestion | ✅ gRPC :4317 і HTTP :4318 |
| Span viewer | ✅ waterfall з prompt/response rendering |
| Prompt inspection | ✅ рідна підтримка LLM span types |
| Token usage | ✅ агрегація input/output tokens по трейсах |
| LLM eval | ✅ онлайн eval з annotators |
| Dataset/experiment | ✅ збереження traces в datasets для порівняння |
| Auth | ⚠️ Bearer token обов'язковий навіть для dev (на відміну від MLflow) |
| Ресурси | ✅ легший ніж MLflow-full (немає torch/sklearn) |
| GenAI focus | ✅ основне призначення |

**Спостереження з кластеру**: Phoenix отримав 28777 трейсів (otel-demo + kagent)
в єдиний проект `default`. UI значно зручніший для аналізу LLM спанів —
prompt/response відображаються як читабельний текст, а не raw JSON атрибути.

Зауваження: otel-demo `agent` компонент використовує httpx для виклику Gemini
без OTel LLM instrumentation — LLM спани не мають `gen_ai.*` атрибутів, тому
Phoenix не виділяє їх як LLM. kagent-controller генерує власні OTel спани через
свій SDK, але вони також приходять як `spanKind=unknown` в Phoenix — потребує
додаткового налаштування OpenInference/OpenTelemetry GenAI SDK в самому kagent.

## Порівняльна таблиця

| Критерій | OTel (Jaeger) | MLflow | Phoenix |
|---|---|---|---|
| Призначення | General distributed tracing | ML lifecycle + tracing | LLM/GenAI observability |
| OTLP підтримка | ✅ рідна | ✅ з v3.x | ✅ рідна |
| GenAI семантика | ⚠️ draft conventions | ⚠️ через атрибути | ✅ рідна |
| Prompt/response UI | ❌ | ⚠️ | ✅ |
| Token metrics | ❌ | ⚠️ | ✅ |
| LLM eval | ❌ | ✅ офлайн | ✅ онлайн+офлайн |
| ML experiment tracking | ❌ | ✅ | ❌ |
| Складність налаштування | низька | середня | середня |
| Ресурси (пам'ять) | ~200Mi | ~2Gi | ~500Mi |
| Auth для OTLP | ❌ | ❌ | ✅ обов'язковий |

## Рішення

Для GenAI агентського стеку (kagent + retrieval-agent) рекомендується **Phoenix**
як основний інструмент спостережуваності:

- рідна підтримка LLM span types (prompt, completion, tool calls)
- зручний UI для аналізу якості відповідей
- онлайн eval без окремого пайплайну

**MLflow** залишається для:

- відстеження ML-експериментів (embedding benchmark, модельні метрики)
- correlation між трейсами і ML runs

**OTel collector** як інфраструктурний шар — fan-out трейсів в обидва backend
через routing connector без змін в агентах.

## Наслідки

- otel-collector в `mlflow` namespace стає центральним fan-out хабом
- Phoenix API key автоматично генерується через `make secrets` при кожному
  новому Codespace (GraphQL mutation `createUserApiKey`)
- MLflow потребує попереднього створення experiments через REST API після deploy
- При SQLite backend MLflow нестабільний під навантаженням otel-demo (~25 сервісів);
  для production потрібен Postgres backend
