# Lab04 — Звіт

## Мета
Розгорнути Agentic Retrieval стек: векторна база + граф + два embedding бекенди, порівняти якість retrieval між моделями.

---

## Що зроблено

### 1. Інфраструктура (з upstream feat/llmd-embeddings)
- **Qdrant** — векторна БД, namespace `qdrant`
- **Neo4j** — граф БД, namespace `neo4j`
- **llm-d** — distributed inference runtime (CPU mode), namespace `llm-d`
- **Inference Extension CRDs** — InferencePool, InferenceModel

### 2. MCP сервери
- **qdrant-mcp** (кастомний Go, `ghcr.io/den-vasyliev/abox/qdrant-mcp:0.4.0`) — embeddings через llama-cpp, колекція `abox-nomic`, 768 dims
- **neo4j-mcp** (`neo4j/mcp:v1.6.0`) — граф через Bolt protocol
- **qdrant-mcp-official** (новий) — офіційний `qdrant/mcp-server-qdrant`, обгорнутий у власний Docker образ (`ghcr.io/fataevalex/abox/qdrant-mcp-official:0.1.0`), fastembed in-process, колекція `abox-miniLM`, 384 dims

### 3. Агенти
- **retrieval-agent** — індексує k8s маніфести в обидва vector stores + Neo4j граф паралельно, порівнює результати retrieval
- **embeddings-agent** — задокументований агент для embedding сервісу

### 4. ADR-003
Порівняння nomic-embed-text-v1.5 vs all-MiniLM-L6-v2 на корпусі з 8 kagent Agent CRD.

---

## Результати retrieval

Запит: *"Find agents that work with embeddings or vector stores"*

| Агент | Store A nomic 768d | Store B MiniLM 384d |
|---|---|---|
| embeddings-agent | ✓ | ✓ |
| **retrieval-agent** | **✗** | **✓** |
| observability-agent | ✓ | ✓ |
| helm-agent | ✗ | ✓ |
| kgateway-agent | ✗ | ✓ |
| k8s-agent | ✓ | ✓ |
| promql-agent | ✓ | ✓ |
| argo-rollouts-conversion-agent | ✓ | ✓ |

- Store A: 5 результатів, пропустив `retrieval-agent` (критичний false negative)
- Store B: 8 результатів, знайшов `retrieval-agent`, але більше false positives

**Висновок:** MiniLM показав вищий recall на малому корпусі. nomic-embed залишається основним для кластера через менший footprint пам'яті.

---

## Вирішені проблеми

| Проблема | Причина | Рішення |
|---|---|---|
| Codespace /tmp ACL ламає KinD | POSIX ACL strips execute bit | `fix-docker-acl.sh` перед `make run` |
| `make push` пушить в `releases` замість `releases-lab04` | CI визначає репо за гілкою тегу | Теги ставити з `lab04` гілки |
| RSIP бачив `releases` (main) замість `releases-lab04` | `releases_artifact` default = "releases" | Змінено на `releases-lab04` в bootstrap, `tofu apply` |
| `qdrant-mcp-official` — ImagePullBackOff | Немає публічного Docker образу для `qdrant/mcp-server-qdrant` | Збудували власний образ, CI workflow `qdrant-mcp-official-image.yaml` |
| `qdrant-mcp-official` — Internal Server Error | `cmd: ""` в конфігу kmcp (поле не вказано) | Додали `cmd: mcp-server-qdrant` в MCPServer spec |
| Embeddings URL не резолвиться | Сервіс мав назву `llama-cpp`, а MCP очікував `llama-cpp-embeddings` | Перейменовано Service + port 8090 |
| Gemini Secret відсутній при першому `make run` | Secret треба створити до reconcile | `kubectl create secret` одразу після `make run` |
| HelmRelease kagent у Failed після Secret | Helm timeout на першому install | `flux suspend/resume helmrelease` |
| retrieval-agent кешує відповіді k8s-agent | LLM пам'ятає попередні виклики в сесії | Нова сесія + явний запит YAML по одному об'єкту |

---

## Артефакти

- `releases/mcp-servers.yaml` — три MCPServer (neo4j, qdrant, qdrant-official)
- `releases/agent-retrieval.yaml` — retrieval-agent з трьома сховищами
- `mcp/qdrant-mcp-official/Dockerfile` — Python обгортка для офіційного MCP
- `.github/workflows/qdrant-mcp-official-image.yaml` — CI для збірки образу
- `docs/adr-003-agentic-retrieval.md` — порівняння embedding моделей
- `bootstrap/variables.tf` — `releases_artifact = "releases-lab04"`
