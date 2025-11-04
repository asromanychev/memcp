Окей, даю «боевое» ТЗ: системно, по делу, под твой стек (Rails-легаси + Cursor IDE + MCP + общая память команды).

# ТЗ: Коллективная «долгосрочная память» для IDE Cursor в легаси-проекте

## 0) Цель и результат

**Цель:** ускорить работу с легаси-кодом за счёт автоматического обогащения промта релевантным опытом команды (решения, факты, ADR, вики) и сохранения новых «воспоминаний» после каждого шага.
**Результат:** самонастраивающийся AI-слой между Cursor IDE и проектом, поддерживающий задачную модель (issue ↔ PR ↔ диалоги), схемы рассуждений (SGR) и авто-оптимизацию промтов (AELP).

---

## 1) Область работ (Scope)

* Интеграция с **Cursor IDE** через **MCP-сервер** (tools: `recall`, `save`, `search`, `link_issue`, `open_doc`).
* **Саб-агент памяти** (Memory Copilot): `Recall → Judge → Distill → Save`.
* **SGR** (Schema-Guided Reasoning): стандартизированные схемы рассуждений (bugfix/refactor/migration/review).
* **AELP** (auto-оптимизация длинных системных промтов и few-shots) — ночной джоб.
* Хранилище знаний: **Postgres+pgvector** (векторный поиск) + **файловый индекс кода**; опция **Neo4j** для граф-связей.
* Коннекторы: **Git** (GitHub/GitLab), **трекер** (YouTrack/Jira/Redmine), **вики** (Confluence/GitHub Wiki/Obsidian-repo).
* Безопасность: санитайзинг секретов/ПДн, ACL по проектам/командам, аудит.

**Вне scope MVP:** сложная визуальная админка, локальные LLM (добавим позже), полнофункциональный граф-анализ (включаем частично).

---

## 2) Архитектура (High-Level)

### Слои

1. **IDE слой**: Cursor + MCP tools (TypeScript).
2. **Core API слой**: Rails API (JSON) — доменная логика, индексация, метаданные.
3. **Vector слой**: Python FastAPI сервис для эмбеддингов и ANN-поиска (pgvector).
4. **Workers**: Sidekiq (ingest, dedup, TTL, AELP).
5. **Connectors**: планировщики для Git/Трекера/Вики.
6. **Хранилища**: Postgres (pgvector), MinIO/S3 для сырья (если нужно), Neo4j (опционально).

### Компоненты

* **MCP-сервер** (Node/TypeScript, официальный mcp SDK):
  Тулы: `recall`, `save`, `search_code`, `link_issue`, `open_doc`. Коммуникация → Rails Core API.
* **Rails Core API**:
  Таблицы доменной модели, REST эндпоинты, RBAC, вебхуки, оркестрация воркеров.
* **Embeddings сервис (FastAPI, Python)**:
  Модели: `text-embedding-3-large` (облако) или локальная `bge-m3`/`gte-base` (SentenceTransformers).
  Хранение эмбеддингов — в pgvector (через Rails или напрямую).
* **Sidekiq воркеры**:
  ingestion (Git/Docs), chunking+embed, dedup/simhash, TTL, AELP optimizer, nightly re-index.
* **Connectors**:
  Git (webhooks + polling), YouTrack/Jira (API), Confluence/GitHub Wiki/Obsidian (git-репо).

---

## 3) Доменные сущности (схемы)

```sql
-- Postgres (с pgvector)
CREATE TABLE projects(
  id uuid pk, key text unique, name text, settings jsonb, created_at, updated_at
);

CREATE TABLE tasks( -- issue/тикет
  id uuid pk, project_id uuid fk, external_id text, title text, status text,
  assignee text, labels text[], links jsonb, created_at, updated_at
);

CREATE TABLE dialogs( -- диалог IDE↔AI
  id uuid pk, project_id uuid fk, task_id uuid fk null,
  developer text, messages jsonb, distilled text, created_at, updated_at
);

CREATE TABLE memory_records( -- факты/кейсы/few-shots
  id uuid pk, project_id uuid fk, task_id uuid fk null, kind text,  -- fact|fewshot|link
  content text, scope text[], tags text[], owner text null,
  ttl timestamptz, quality jsonb, meta jsonb, created_at, updated_at
);

-- Векторные индексы
CREATE EXTENSION IF NOT EXISTS vector;
ALTER TABLE dialogs         ADD COLUMN embedding vector(1536);
ALTER TABLE memory_records  ADD COLUMN embedding vector(1536);

-- Коды/символы/файлы
CREATE TABLE code_chunks(
  id uuid pk, project_id uuid fk, repo_path text, file_path text,
  symbol text null, lang text, content text, sha text, size int,
  embedding vector(1536), created_at, updated_at
);

-- Документация и ADR
CREATE TABLE docs(
  id uuid pk, project_id uuid fk, source text,  -- confluence|wiki|obsidian
  doc_id text, title text, url text, content text,
  embedding vector(1536), updated_at, created_at
);
```

**Типы `memory_records.kind`:** `fact`, `fewshot`, `pattern`, `adr_link`, `gotcha` (осторожность), `rule`.

---

## 4) API (Core, кратко)

### Auth

* `POST /auth/token` — JWT по OAuth (GitHub/Google) или SSO.
* Все запросы MCP → Core API с JWT.

### Recall/Save

* `POST /recall`

```json
{
  "project_key":"insales",
  "task_external_id":"CS-214",
  "repo_path":"app/services/cart_sessions",
  "symbols":["CartSessions::Setting#trigger_delay_time_in_minutes"],
  "signals":["nil-delay","unit-mismatch"],
  "limit_tokens":2000
}
```

**200 OK**

```json
{
  "facts":[{"text":"delay_unit должен совпадать с trigger_delay_unit","scope":["cart_sessions"]}],
  "few_shots":[{"title":"Fix nil delay","patch_ref":"sha1", "steps":["..."]}],
  "links":[{"title":"ADR Timing Rules","url":"..."}],
  "confidence":0.82
}
```

* `POST /save`

```json
{
  "project_key":"insales",
  "task_external_id":"CS-214",
  "kind":"fact",
  "content":"Причина nil: расхождение delay_unit/trigger_delay_unit",
  "scope":["cart_sessions","settings"],
  "tags":["bugfix","unit"],
  "quality":{"novelty":0.74,"dup":0.06,"usefulness":0.81},
  "ttl":"2026-06-01",
  "meta":{"patch_sha":"abc123","source_dialog_id":"dlg-..."}
}
```

### Ingest

* `POST /ingest/git` (webhook): коммиты, диффы, файлы → chunk+embed.
* `POST /ingest/docs` — батч статей/ADR.
* `POST /tasks/sync` — синк issues из YouTrack/Jira/Redmine.

### Search

* `POST /search` — гибрид (BM25 + pgvector) по: `code_chunks`, `memory_records`, `docs`, `dialogs`.

### Admin/Policy

* `PUT /projects/:key/policy` — ACL/TTL/санитайзинг правила.
* `GET /metrics` — метрики Recall/Save/AELP.

---

## 5) MCP-сервер (tools) — контракты

* `recall(params)` → дергает Core `/recall`, возвращает bundle (вставляет в промт перед генерацией).
* `save(payload)` → Core `/save` (после ответа, уже после Judge/Distill).
* `search_code(query)` → подсветка релевантных файлов/символов.
* `link_issue(issue_id)` → фиксирует связь диалога с задачей.
* `open_doc(title|url)` → открывает ADR/док-страницу.

**Технологии:** Node 20+, TypeScript, mcp-sdk. Транспорт: stdio или WebSocket (возможности Cursor). Логика саб-агента памяти может жить здесь (тонкий агент) или в Core (толстый сервер).

---

## 6) Саб-агент памяти (Memory Copilot) — логика

**Перед генерацией (Recall):**

1. Из параметров запроса строим **query**: `task_id + repo path + symbols + signals`.
2. Гибридный поиск:

   * pgvector (cosine) по `memory_records`, `docs`, `dialogs`, `code_chunks`.
   * фильтры: `scope`, `ttl > now()`, `project_id`.
3. Построение **memory-bundle**:

   * top-N `facts` (краткие, ≤200-300 симв.)
   * 1-3 `few-shots` (минимальные)
   * ссылки на ADR/доки (только заголовок+URL)
4. Лимит по токенам; ранжирование по `recency`, `usefulness`, `scope`-match.

**После генерации (Save):**

1. **LLM-as-a-judge** (локально/облако):

   * новизна (simhash/MinHash + cosine),
   * полезность (эвристика: были ли клики по ссылкам/патчу, прошел ли CI),
   * недублирование (порог сходства).
2. **Distill**: сжать до «факта» ≤ 2k sym + теги + scope + TTL.
3. **Upsert**: если близкий дубликат — обновляем существующую запись (bump recency, merge tags).
4. **Sanitize**: удаляем секреты (regex + detect-secrets/truffleHog), ПДн.
5. Сохранить `memory_record`, привязать к `task`, `patch_sha`, `dialog_id`.

**Гигиена (воркеры):**

* TTL-сборщик: `soft_delete` устаревших, архив.
* Dedup-пакет: периодический MinHash-кластеринг.
* Quality-scorer: пересчет полезности, «плохой шум» в quarantine.

---

## 7) SGR — схемы рассуждений (YAML)

### `bugfix.yaml`

```yaml
schema: bugfix
steps:
  - name: Understand
    output: problem_summary
    hints: ["Опиши плохое поведение", "Логи/условия"]
  - name: Locate
    output: suspected_components
    hints: ["Файлы/методы/символы", "Связанные коммиты/таски"]
  - name: Recall
    output: relevant_facts
    source: memory_bundle
  - name: Plan
    output: plan_steps
    hints: ["Минимальное правка", "Риски/границы"]
  - name: Patch
    output: code_diff
  - name: Verify
    output: checks
    hints: ["Юнит/интеграция", "Регрессия"]
  - name: Explain
    output: rationale
```

### `refactor.yaml`

(аналогично, с шагами: Identify Smells → Strategy → Patch → Safety Nets → Explain)

**Применение:** IDE-агент подставляет в промт схему + memory-bundle → LLM генерит ответы строго по полям схемы → удобно сохранять/аудитить.

---

## 8) AELP — авто-оптимизация промтов (ночной джоб)

* Источники: успешные диалоги, top-hit facts/few-shots, частотные ошибки.
* Алгоритм: **beam-перебор** вариантов формулировок системного промта/подсказок, offline-оценка (эвристики + мини-батарея задач из репозитория кейсов).
* Артефакт: `system_prompts/<project>.yaml` (версионируется в Git), с датой и меткой качества.
* Безопасность: «канареечный» rollout (10% разработчиков), метрики, затем full.

---

## 9) Интеграции (коннекторы)

* **Git**: webhook на push/PR; забираем diff, AST-chunking (tree-sitter), embed.
* **Трекер** (YouTrack/Jira/Redmine): синк title/status/assignee/labels; back-link на диалоги/воспоминания.
* **Вики**: Confluence API или Git-репо с Markdown (Obsidian/GitHub Wiki); парс front-matter (tags/scope).

---

## 10) Безопасность и соответствие

* **Санитайзинг** перед сохранением:
  regex-паттерны для ключей/токенов, банковские, ПДн; `detect-secrets`/`truffleHog`.
* **ACL** на уровне проектов и команд; JWT-скоупы.
* **Аудит-лог**: кто сохранил, что извлек, какие bundle-части попали в промт.
* **PII-политика**: запрещённые типы данных → quarantine + оповещение.

---

## 11) Деплой и DevOps

* **Docker Compose (MVP)**: `rails-core`, `fastapi-embed`, `postgres+pgvector`, `redis`, `sidekiq`, `mcp-server`.
* **K8s (позже)**: горизонтальное масштабирование embed-сервиса, воркеров.
* **Observability**: Prometheus/Grafana, OpenTelemetry (trace MCP→Core→Embed), Sentry.
* **Бэкапы**: Postgres (ежедневно), MinIO (версии), экспорт YAML фактов (еженедельно).

---

## 12) Метрики успеха (KPI)

* **Recall Hit-Rate**: % запросов, где bundle содержал реально использованные факты/ссылки.
* **Time-to-First-Relevant**: медиана времени до получения полезной подсказки.
* **Save Acceptance**: % фактов, прошедших Judge→Save.
* **Bugfix Lead-Time**: до/после (контрольная группа).
* **Onboarding Speed**: время до самостоятельного фикса у нового разработчика.

---

## 13) План поставки (итерации)

### Итер. 1 (2–3 недели)

* Rails Core API (минимум), Postgres+pgvector, Redis, Sidekiq.
* MCP tools: `recall`, `save`.
* Ingest Git (webhook), базовый chunk+embed.
* SGR: `bugfix.yaml`.
* Memory Copilot (базовый Judge эвристиками, без LLM).
* Базовые метрики.

### Итер. 2

* Коннектор трекера (YouTrack/Jira/Redmine), вики (Confluence/Git-wiki/Obsidian-репо).
* Judge с LLM (локально/облако), dedup (SimHash/MinHash).
* SGR: `refactor`, `migration`.
* Пакет политик (TTL, sanitize, ACL).

### Итер. 3

* AELP ночной оптимизатор + канареечный rollout.
* Расширенная аналитика, дешборд.
* Neo4j (опционально) для визуализации связей задач/диалогов/патчей.

---

## 14) Тестирование

* **Контракт-тесты API** (RSpec, Pact).
* **Релевантность Recall** — offline-набор кейсов + ручная валидация.
* **Load-тесты** embed-сервиса.
* **Безопасность**: тесты санитайзинга, E2E-прогон «секрет в промте → не попал в память».

---

## 15) Риски и меры

* **Шум в памяти** → жёсткая дистилляция и dedup, TTL по умолчанию 180 дней, hit-bump.
* **Задержки/стоимость** → лимит токенов в bundle, локальные эмбеддинги, кэширование.
* **Утечки** → строгий санитайзер + RBAC + аудит + запрет сохранения ответов внешних тулов целиком.
* **Сопротивление команды** → SGR-шаблоны как помощь, а не формальность; «быстрые победы» на знакомых болях.

---

## 16) Технологии (рекомендуемые)

* **Backend:** Ruby on Rails (API-only), Sidekiq, RSpec.
* **DB:** Postgres 15+, `pgvector`, Redis.
* **Embeddings:** Python FastAPI + SentenceTransformers (`bge-m3`/`gte-base`), или OpenAI `text-embedding-3-large`.
* **MCP:** Node.js 20+, TypeScript, mcp-sdk.
* **Парсинг кода:** tree-sitter (chunking/AST).
* **Секрет-скан:** detect-secrets / truffleHog.
* **Obs:** Prometheus, Grafana, Sentry, OpenTelemetry.

---

## 17) Примеры артефактов

### Пример `recall` → bundle (сжато)

```json
{
  "facts":[
    {"text":"delay_unit и trigger_delay_unit должны совпадать", "scope":["cart_sessions","settings"]},
    {"text":"в log длина строки ≤ 120 символов (линтер)", "scope":["logging"]}
  ],
  "few_shots":[
    {"title":"Fix nil delay mapping","steps":["найти nil","сверить units","тест"],"patch_ref":"sha:..."}
  ],
  "links":[{"title":"ADR: Timing Rules","url":"https://..."}],
  "confidence":0.84
}
```

### Пример сохранённого факта

```yaml
kind: fact
content: "При nil в trigger_delay_time_in_minutes проверь соответствие delay_unit ↔ trigger_delay_unit."
scope: ["cart_sessions","settings"]
tags: ["bugfix","unit","nil"]
ttl: 2026-06-01
quality: { novelty: 0.71, dup: 0.05, usefulness: 0.83 }
meta: { patch_sha: "abc123", source_dialog_id: "dlg-..." }
```
