# ADR-001: Вибір runtime для embedding-інференсу

## Контекст

Стек abox використовує Qdrant як векторну базу даних для семантичного пошуку. Retrieval-agent індексує Kubernetes-маніфести і відповідає на запити типу "що конфігурує X" через vector search. Для цього необхідний локальний embedding-сервіс, який:

- Працює без зовнішніх API
- Запускається в кластері з обмеженими ресурсами (GitHub Codespaces: 4–8 CPU, 8–16 GB RAM)
- Надає OpenAI-сумісний `/v1/embeddings` endpoint
- Підтримує nomic-embed-text-v1.5 (обрана модель: 768-dim, 8k контекст, GGUF)

## Обрана модель

**`nomic-ai/nomic-embed-text-v1.5`** (GGUF Q4_K_M, ~275 MB)

- Розмірність вектора: 768
- Контекст: 8 192 токенів — вміщує цілі YAML-маніфести без розбиття
- Ліцензія: Apache 2.0
- Формат: GGUF — нативна підтримка llama.cpp

## Розглянуті варіанти runtime

### 1. llama.cpp (обрано)

Запуск через образ `ghcr.io/den-vasyliev/abox/nomic-embed:v1.18.1` з вбудованим llama-server.

**Переваги:**
- Модель вбудована в образ — немає initContainer, немає pull при старті
- CPU-only, мінімальне споживання пам'яті (memory-mapped GGUF)
- Детерміністичний старт — readinessProbe `/health` спрацьовує одразу
- Підходить для sidecar-патерну (малий footprint)

**Недоліки:**
- Однопотоковий, не масштабується під великим навантаженням

### 2. Ollama

Запуск через `ollama/ollama` з initContainer, який тягне модель при першому старті.

**Переваги:**
- Простий model management, легкий старт
- Широка екосистема моделей

**Недоліки:**
- initContainer завантажує модель (~275 MB) у emptyDir при кожному рестарті pod
- Займає значно більше місця на диску (образ + модель окремо)
- Довший час до готовності

## Практичне порівняння

Оточення: GitHub Codespaces (4 CPU, 8 GB RAM), KinD кластер, CPU-only.  
Скрипти: `scripts/compare-embeddings.sh`, `scripts/benchmark-embeddings.sh`.

### Якість векторів

```bash
bash scripts/compare-embeddings.sh "kubernetes pod crashloopbackoff"
```

```
llama-cpp dimensions : 768
ollama    dimensions : 768
cosine similarity    : 0.998025

Vectors are nearly identical (same model weights)
```

Cosine similarity **0.998** — обидва рантайми дають практично ідентичні вектори для однієї моделі.

### Latency та throughput (20 запитів, sequential)

| Метрика        | llama-cpp | ollama          |
|----------------|-----------|-----------------|
| avg latency    | 92 ms     | 178 ms *        |
| throughput     | 10.35 req/s | 5.53 req/s    |
| cold start     | —         | 1675 ms (req #1)|
| errors         | 0/20      | 0/20            |

\* ollama avg включає cold start (1675 ms на першому запиті — модель завантажується в RAM).  
Без cold start: ollama avg ≈ 99 ms, throughput ≈ 9.5 req/s — порівнянно з llama-cpp.

## Рішення

Обрано **llama.cpp** як основний runtime для dev та кластерного deployment.  
Ollama розгорнуто як другий backend для порівняння та weighted routing через agentgateway.

## Наслідки

- Embedding-сервіс (llama.cpp): namespace `llama-cpp`, endpoint `/v1/embeddings`
- Ollama: namespace `ollama`, endpoint `/v1/embeddings`
- Weighted routing через HTTPRoute: llama-cpp 80% / ollama 20%
- Розмірність векторів у Qdrant: **768**
- При переході на інший runtime з тією ж моделлю — переіндексування не потрібне (cosine similarity ≈ 1.0)
