# ADR-003: Agentic Retrieval — порівняння embedding моделей

## Контекст

Lab04 додає до стеку два MCP-сервери для векторного пошуку:

- **qdrant-mcp** (кастомний Go сервер) — embeddings через llama-cpp в кластері,
  модель `nomic-embed-text-v1.5`, колекція `abox-nomic`, 768 dims
- **qdrant-mcp-official** (офіційний `qdrant/mcp-server-qdrant`) — embeddings через
  fastembed in-process, модель `sentence-transformers/all-MiniLM-L6-v2`,
  колекція `abox-miniLM`, 384 dims

`retrieval-agent` індексує Kubernetes custom resources з кластеру через `k8s-agent`
і зберігає їх в обидва сховища паралельно для порівняння якості retrieval.

## Конфігурація

| Параметр | Store A (nomic) | Store B (MiniLM) |
|---|---|---|
| MCP сервер | `qdrant-mcp` | `qdrant-mcp-official` |
| Інструменти | `vector_store` / `vector_find` | `qdrant-store` / `qdrant-find` |
| Модель | nomic-embed-text-v1.5 | all-MiniLM-L6-v2 |
| Dims | 768 | 384 |
| Embeddings | llama-cpp (окремий pod) | fastembed in-process |
| Колекція Qdrant | `abox-nomic` | `abox-miniLM` |

## Експеримент

Індексовано 8 kagent `Agent` CRD з namespace `kagent` через `retrieval-agent`.
Запит для порівняння:

> Find agents that work with embeddings or vector stores. Search both vector stores and compare results.

## Результати

| Агент | Store A (nomic) | Store B (MiniLM) |
|---|---|---|
| embeddings-agent | ✓ | ✓ |
| retrieval-agent | ✗ | ✓ |
| observability-agent | ✓ | ✓ |
| helm-agent | ✗ | ✓ |
| kgateway-agent | ✗ | ✓ |
| k8s-agent | ✓ | ✓ |
| promql-agent | ✓ | ✓ |
| argo-rollouts-conversion-agent | ✓ | ✓ |

Store A повернув **5 результатів**, Store B — **8 результатів**.

## Аналіз

**Store B (MiniLM) точніший для цього запиту:**
- `retrieval-agent` — єдиний агент що реально працює з vector stores — знайдений
  тільки в Store B. Store A пропустив його (false negative).
- Store B повернув `helm-agent` і `kgateway-agent` — це false positives,
  вони не пов'язані з embeddings.

**Store A (nomic) більш вибірковий:**
- Менше результатів, але `retrieval-agent` відсутній — критичний miss.
- `promql-agent` і `argo-rollouts-conversion-agent` у результатах — false positives
  для обох сховищ.

**Причина різниці:**
- MiniLM (384 dims) — загальна sentence similarity модель, натренована на широкому
  корпусі, добре розуміє семантику "retrieval" та "vector".
- nomic-embed (768 dims) — сильніша модель для технічних текстів, але при малому
  корпусі (8 документів) різниця в recall може бути непередбачуваною.
- Обсяг індексу замалий для статистично значущих висновків.

## Висновки

1. **Для малого корпусу** (десятки документів) різниця між моделями незначна —
   обидві повертають релевантні результати з подібними false positive/negative.
2. **MiniLM** показав вищий recall на цьому запиті, але fastembed in-process
   потребує більше пам'яті (512Mi–1Gi) порівняно з Go сервером (32Mi).
3. **nomic-embed** через зовнішній llama-cpp — кращий вибір для кластера
   з обмеженими ресурсами: менше пам'яті, детермінований старт.
4. Для production-якості retrieval потрібен більший корпус (сотні документів)
   і eval набір з ground truth для об'єктивного порівняння.

## Рішення

Обидва сховища залишаються активними для подальших експериментів.
`retrieval-agent` індексує в обидва паралельно і порівнює результати при пошуку.

Основний backend для продакшн — **nomic-embed через llama-cpp** (ADR-001):
менше ресурсів, передбачуваний старт, та сама модель що й у weighted routing.
