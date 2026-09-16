# ToDo: Запуск nomic-embed-text-v1.5 локально

Інструкція для агента або розробника по запуску embedding-моделі локально.  
Модель: `nomic-ai/nomic-embed-text-v1.5` у форматі GGUF.

---

## Варіант 1: llama.cpp (рекомендовано)

### 1. Встановити llama.cpp

```bash
# macOS
brew install llama.cpp

# або зібрати з джерел
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
cmake -B build && cmake --build build --config Release -j$(nproc)
```

### 2. Завантажити модель

```bash
# Завантажити GGUF Q4_K_M (~275 MB)
curl -L -o nomic-embed-text-v1.5.Q4_K_M.gguf \
  "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q4_K_M.gguf"
```

### 3. Запустити сервер

```bash
llama-server \
  --model nomic-embed-text-v1.5.Q4_K_M.gguf \
  --port 8090 \
  --ctx-size 8192 \
  --parallel 4 \
  --embeddings \
  --no-mmap false
```

Сервер слухає на `http://localhost:8090`.

### 4. Перевірити

```bash
curl http://localhost:8090/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"input": "test embedding", "model": "nomic-embed-text-v1.5"}'
```

Очікувана відповідь: JSON з полем `data[0].embedding` — масив із 768 чисел.

---

## Варіант 2: Ollama

### 1. Встановити Ollama

```bash
# macOS
brew install ollama

# або
curl -fsSL https://ollama.com/install.sh | sh
```

### 2. Завантажити та запустити модель

```bash
ollama pull nomic-embed-text
ollama serve  # якщо не запущено як сервіс
```

### 3. Перевірити

```bash
curl http://localhost:11434/api/embeddings \
  -d '{"model": "nomic-embed-text", "prompt": "test embedding"}'
```

> **Примітка:** Ollama використовує інший формат API (`/api/embeddings`, поле `prompt`).  
> Для сумісності з OpenAI-сумісними клієнтами (Qdrant MCP, llm-d) — використовуй llama.cpp.

---

## Перевірка розмірності

Обидва варіанти повертають вектор розмірністю **768**. При створенні колекції в Qdrant:

```bash
curl -X PUT http://localhost:6333/collections/abox-nomic \
  -H "Content-Type: application/json" \
  -d '{"vectors": {"size": 768, "distance": "Cosine"}}'
```
