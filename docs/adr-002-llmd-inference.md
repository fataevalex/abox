# ADR-002: Запуск embedding-моделі в кластері через llm-d

## Контекст

ADR-001 визначив llama.cpp як основний runtime для CPU-оточень (Codespaces/dev).
Для production-кластерів з GPU або high-concurrency потрібна інша стратегія:
llama.cpp однопотоковий, не підтримує batching, не масштабується горизонтально.

llm-d (https://llm-d.ai) — open-source проект від Red Hat для distributed LLM inference
на Kubernetes. Реалізує:
- **vLLM** як inference engine (GPU-оптимізований, continuous batching)
- **Kubernetes Inference Extension** — офіційний Kubernetes проект для intelligent routing
- **InferencePool / InferenceModel** CRDs для декларативного управління моделями
- Prefill/decode disaggregation для оптимізації KV-cache

## Порівняння рантаймів

| Характеристика       | llama.cpp       | ollama          | llm-d / vLLM         |
|----------------------|-----------------|-----------------|----------------------|
| Цільове оточення     | dev / CPU       | laptop / dev    | production / GPU     |
| Cold start           | немає           | ~1675 ms        | немає (постійний pod)|
| avg latency (CPU)    | 92 ms           | 178 ms          | н/д (потребує GPU)   |
| Throughput (CPU)     | 10.35 req/s     | 5.53 req/s      | 100+ req/s (GPU)     |
| Continuous batching  | ні              | ні              | так                  |
| Горизонтальне масш.  | ні              | ні              | так (InferencePool)  |
| GPU підтримка        | ні              | обмежено        | так (основний шлях)  |
| Розмір образу        | ~476 MB         | ~1.5 GB         | ~10 GB               |
| Kubernetes-native    | Deployment      | Deployment      | InferencePool CRD    |

## Обмеження CPU

vLLM має експериментальну підтримку CPU (`--device cpu`), але:
- Потребує окремого `vllm-cpu` wheel (~5 GB залежностей)
- Продуктивність значно нижча ніж llama.cpp на CPU
- Не рекомендовано для production навіть на CPU-кластерах

Перевірити на Codespaces неможливо через обмеження диску (~4 GB вільно, потрібно >6 GB).

## ToDo: Розгортання nomic-embed-text через llm-d

### Передумови

- Kubernetes кластер з GPU-вузлами (NVIDIA, мінімум T4 або A10G)
- Gateway API v1.2+ встановлений у кластері
- Helm 3.x, kubectl

### Кроки

**1. Встановити llm-d**

```bash
helm repo add llmd https://llm-d.github.io/llm-d
helm install llmd llmd/llmd -n llmd --create-namespace
```

**2. Встановити Kubernetes Inference Extension**

```bash
helm install gateway-api-inference-extension \
  oci://registry.k8s.io/gateway-api-inference-extension/charts/inferencepool \
  -n llmd
```

**3. Розгорнути vLLM з nomic-embed-text-v1.5**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-embed
  namespace: llmd
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vllm-embed
  template:
    metadata:
      labels:
        app: vllm-embed
    spec:
      containers:
        - name: vllm
          image: vllm/vllm-openai:latest
          args:
            - --model=nomic-ai/nomic-embed-text-v1.5
            - --task=embed
            - --port=8000
            - --trust-remote-code
          resources:
            limits:
              nvidia.com/gpu: "1"
          readinessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 30
```

**4. Створити InferenceModel та InferencePool**

```yaml
apiVersion: inference.networking.x-k8s.io/v1alpha2
kind: InferenceModel
metadata:
  name: nomic-embed
  namespace: llmd
spec:
  modelName: nomic-ai/nomic-embed-text-v1.5
  criticality: Sheddable
  poolRef:
    name: embed-pool
---
apiVersion: inference.networking.x-k8s.io/v1alpha2
kind: InferencePool
metadata:
  name: embed-pool
  namespace: llmd
spec:
  targetPortNumber: 8000
  selector:
    app: vllm-embed
```

**5. Додати до weighted routing в agentgateway**

```yaml
# releases/embeddings-route.yaml
backendRefs:
  - name: llama-cpp
    namespace: llama-cpp
    port: 80
    weight: 60
  - name: ollama
    namespace: ollama
    port: 80
    weight: 20
  - name: embed-pool   # llm-d InferencePool
    namespace: llmd
    port: 80
    weight: 20
```

**6. Перевірити endpoint**

```bash
curl http://<gateway>/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"input": "kubernetes pod", "model": "nomic-ai/nomic-embed-text-v1.5"}'
```

## Наслідки

- llm-d потребує GPU — не запускається в Codespaces KinD
- Endpoint сумісний з OpenAI `/v1/embeddings` API — заміна llama.cpp без змін у клієнтах
- Розмірність векторів 768 — колекцію Qdrant перебудовувати не потрібно (та сама модель)
- Поступовий перехід через weighted routing: llama-cpp → llm-d без даунтайму
