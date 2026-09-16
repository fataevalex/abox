# ToDo: Запуск nomic-embed-text-v1.5 у кластері

Два способи запуску embedding-моделі у KinD-кластері abox.  
Модель: `nomic-ai/nomic-embed-text-v1.5` (GGUF), runtime: llama.cpp.

---

## Спосіб 1: Standalone Deployment (llama-cpp)

Окремий Deployment у namespace `llama-cpp`. Модель запакована в OCI-образ і монтується як volume — завантаження ваг відбувається при старті поди без звернення до HuggingFace.

**Файл:** `releases/llama-cpp-embeddings.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: llama-cpp
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llama-cpp
  namespace: llama-cpp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: llama-cpp
  template:
    metadata:
      labels:
        app: llama-cpp
    spec:
      initContainers:
        - name: model
          image: ghcr.io/den-vasyliev/abox/nomic-embed:v1.18.1-4ccc0ff
          command: ["cp", "/model/nomic-embed-text-v1.5.Q4_K_M.gguf", "/mnt/model/"]
          volumeMounts:
            - name: model
              mountPath: /mnt/model
      containers:
        - name: llama-cpp
          image: ghcr.io/ggerganov/llama.cpp:server
          args:
            - --model
            - /mnt/model/nomic-embed-text-v1.5.Q4_K_M.gguf
            - --port
            - "8090"
            - --ctx-size
            - "16384"
            - --parallel
            - "8"
            - --embeddings
          ports:
            - containerPort: 8090
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: "2"
              memory: 1Gi
          readinessProbe:
            httpGet:
              path: /health
              port: 8090
            initialDelaySeconds: 5
            periodSeconds: 5
          volumeMounts:
            - name: model
              mountPath: /mnt/model
      volumes:
        - name: model
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: llama-cpp
  namespace: llama-cpp
spec:
  selector:
    app: llama-cpp
  ports:
    - port: 80
      targetPort: 8090
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: llama-cpp
  namespace: llama-cpp
spec:
  parentRefs:
    - name: agentgateway-external
      namespace: agentgateway-system
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /llamacpp
      backendRefs:
        - name: llama-cpp
          port: 80
```

**Endpoint у кластері:** `http://llama-cpp.llama-cpp.svc/v1/embeddings`  
**Endpoint зовні (через Gateway):** `http://<gateway-ip>/llamacpp/v1/embeddings`

**Перевірка:**
```bash
kubectl run test --rm -it --image=curlimages/curl --restart=Never -- \
  curl http://llama-cpp.llama-cpp.svc/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"input": "test", "model": "nomic-embed-text-v1.5"}'
```

---

## Спосіб 2: llm-d (InferencePool)

llm-d — Kubernetes-нативний inference-оркестратор. Використовує CRD `InferenceModel` / `InferencePool` + EndpointPicker для маршрутизації запитів до модельних pod'ів.

**Файл:** `releases/llmd.yaml`

Ключові компоненти:
- `HelmRelease` чарту `llm-d-modelservice` — розгортає llama.cpp як inference backend
- `InferencePool` — пул ендпоінтів для моделі
- `HTTPRoute` з `ExtensionRef` до EndpointPicker — AI-aware маршрутизація через agentgateway

```yaml
# Фрагмент — InferencePool
apiVersion: inference.networking.x-k8s.io/v1alpha2
kind: InferencePool
metadata:
  name: llmd-embeddings
  namespace: llm-d
spec:
  targetPortNumber: 8000
  selector:
    matchLabels:
      app: llmd-embeddings
  extensionRef:
    name: llmd-epp
```

**Endpoint у кластері:** `http://llmd-embeddings.llm-d.svc:8000/v1/embeddings`  
**Endpoint зовні (через Gateway):** `http://<gateway-ip>/llmd/v1/embeddings`

**Переваги llm-d над standalone:**
| | Standalone llama-cpp | llm-d |
|---|---|---|
| Масштабування | вручну (replicas) | автоматично через InferencePool |
| Маршрутизація | звичайний Service | AI-aware (per-request routing) |
| Метрики | немає | Prometheus через `/metrics` |
| Складність | мінімальна | вища (CRD + EPP) |

---

## Sidecar-варіант

Модель запускається як sidecar-контейнер поруч з агентом — корисно коли потрібна embedding без окремого сервісу.

```yaml
# Додати до spec.template.spec.containers агента:
- name: embeddings
  image: ghcr.io/ggerganov/llama.cpp:server
  args:
    - --model
    - /mnt/model/nomic-embed-text-v1.5.Q4_K_M.gguf
    - --port
    - "8090"
    - --embeddings
    - --ctx-size
    - "8192"
  ports:
    - containerPort: 8090
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
  volumeMounts:
    - name: model
      mountPath: /mnt/model
```

Агент звертається до моделі через `localhost:8090/v1/embeddings`.

**Недолік:** при масштабуванні агента кожна репліка несе власну копію моделі у RAM — витратно. Рекомендується для single-replica deployments або dev-середовищ.
