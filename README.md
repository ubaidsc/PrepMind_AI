# PrepMind AI — Intelligent Study Assistant

> **Full-stack AI-powered study platform** built with Flutter, FastAPI, Supabase, and Google Gemini. Upload your lecture notes, textbooks, or slides and let AI generate MCQs, flashcards, summaries, mind maps, and more — or chat directly with your documents.

---

## What it does

Students upload their study material (PDFs, DOCX, PPTX). The backend extracts text, chunks it, generates vector embeddings via Gemini, and stores them in Supabase with `pgvector`. From there:

- **AI Notes** — generate 8 types of study content from your documents (MCQs, flashcards, Q&A, summaries, mind maps, revision sheets, mnemonics, key concepts)
- **AI Chat** — ask questions and get context-aware answers grounded in your own documents via RAG (Retrieval-Augmented Generation)
- **Document management** — upload, view status, delete. Background processing pipeline updates document status in real-time
- **Usage tracking** — per-user AI request and document quotas with live progress bars

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter App (Dart)                        │
│   Riverpod · GoRouter · Dio · Freezed · Supabase Flutter SDK    │
└──────────────────────┬──────────────────────────────────────────┘
                       │  REST (JWT-authenticated)
┌──────────────────────▼──────────────────────────────────────────┐
│                    FastAPI Backend (Python)                       │
│                                                                   │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────┐    │
│  │  /auth      │  │  /documents  │  │  /ai  ·  /chat      │    │
│  └─────────────┘  └──────┬───────┘  └──────────┬──────────┘    │
│                           │                      │               │
│            ┌──────────────▼──────────────────────▼────────────┐ │
│            │           Core Services                           │ │
│            │  DocumentProcessor · Chunker · GeminiKeyRotator  │ │
│            │  DocumentPipeline · RAG · Generator              │ │
│            └──────────────────────────┬───────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                         │
┌────────────────────────────────────────▼────────────────────────┐
│                        Supabase                                   │
│  PostgreSQL · pgvector · Auth · Storage · Row Level Security    │
│                                                                   │
│  subjects · documents · document_chunks · ai_generations        │
│  chat_sessions · chat_messages · profiles · subject_context     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Tech Stack

### Mobile (Flutter)

| Concern            | Library                                   |
| ------------------ | ----------------------------------------- |
| State management   | `flutter_riverpod` + `riverpod_generator` |
| Navigation         | `go_router`                               |
| HTTP client        | `dio` with JWT interceptor                |
| Models             | `freezed` + `json_serializable`           |
| Database / Auth    | `supabase_flutter`                        |
| Markdown rendering | `flutter_markdown`                        |
| File picking       | `file_picker`                             |

### Backend (Python / FastAPI)

| Concern         | Library                                                  |
| --------------- | -------------------------------------------------------- |
| API framework   | `FastAPI` 0.115 + `uvicorn`                              |
| AI / Embeddings | `google-genai` (Gemini 2.5 Flash + gemini-embedding-001) |
| Database client | `supabase-py` 2.29                                       |
| PDF extraction  | `PyMuPDF`                                                |
| DOCX / PPTX     | `python-docx`, `python-pptx`                             |
| Token counting  | `tiktoken`                                               |
| Config          | `pydantic-settings`                                      |

### Infrastructure

| Concern       | Tool                                 |
| ------------- | ------------------------------------ |
| Database      | Supabase PostgreSQL with `pgvector`  |
| Auth          | Supabase Auth (JWT / JWKS)           |
| File storage  | Supabase Storage                     |
| Vector search | `pgvector` cosine similarity via RPC |
| RLS           | Row Level Security on all tables     |

---

## Key Engineering Highlights

**RAG Pipeline**
Documents are chunked at 600 tokens with 100-token overlap using `tiktoken`. Each chunk is embedded with `gemini-embedding-001` (768 dims) and stored in `document_chunks` with `pgvector`. At query time, the query is embedded with `retrieval_query` task type and matched via `match_chunks` Supabase RPC — returning the top-k most semantically relevant chunks to ground the LLM response.

**Gemini Key Rotation**
`GeminiKeyRotator` manages a pool of API keys, rotating automatically on `429 / RESOURCE_EXHAUSTED` errors. Usage is tracked per-key via `increment_key_usage` DB function. Supports up to N keys with zero downtime on quota exhaustion.

**Background Document Processing**
Upload returns immediately. Processing (text extraction → chunking → embedding → storage) runs as a FastAPI `BackgroundTask`. The Flutter app polls `GET /documents/{subject_id}` until status flips from `uploaded` → `processing` → `ready` (or `failed` with error detail).

**Security**

- All API endpoints require a Supabase JWT validated via JWKS
- Service role key never leaves the backend
- All Supabase tables have Row Level Security — users can only read/write their own data
- Secrets are loaded via `pydantic-settings` from `.env`, never from `os.environ` directly

---

## Project Structure

```
PrepMind/
├── prepmind_api/              # FastAPI backend
│   ├── app/
│   │   ├── core/              # supabase.py · gemini.py · document_processor.py
│   │   ├── services/          # chunker · rag · generator · document_pipeline
│   │   ├── routers/           # auth · subjects · documents · ai · chat
│   │   └── models/            # Pydantic request/response models
│   ├── tests/
│   └── requirements.txt
│
├── prepmind_app/              # Flutter mobile app
│   └── lib/
│       ├── core/              # router · providers · constants
│       ├── features/
│       │   ├── auth/          # login · signup · forgot password
│       │   ├── subjects/      # subject list · detail (3-tab) · create
│       │   ├── documents/     # upload · status polling · delete
│       │   ├── ai_notes/      # generate options · result renderer (8 types)
│       │   ├── chat/          # RAG chat with typing indicator
│       │   └── profile/       # usage stats · plan · sign out
│       └── shared/            # reusable widgets
│
└── supabase_schema.sql        # Full DB schema with RLS policies
```

---

## Getting Started

### Prerequisites

- Flutter SDK ≥ 3.4.0
- Python 3.11+
- Supabase project with `pgvector` enabled
- Google AI Studio API key(s)

### Backend

```bash
cd prepmind_api
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
# Fill in SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY, GEMINI_KEY_1

uvicorn app.main:app --reload --port 8000
```

### Flutter App

```bash
cd prepmind_app
cp .env.example .env
# Set API_BASE_URL=http://10.0.2.2:8000  (Android emulator)
# or   API_BASE_URL=http://localhost:8000 (iOS simulator)

flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

### Database

Run `supabase_schema.sql` in your Supabase SQL editor to create all tables, functions, triggers, and RLS policies.

---

## Environment Variables

**`prepmind_api/.env`**

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...
GEMINI_KEY_1=...
GEMINI_KEY_2=...   # optional — for key rotation
GEMINI_KEY_3=...   # optional
MAX_FILE_SIZE_MB=20
FREE_PLAN_FILE_LIMIT=5
```

**`prepmind_app/.env`**

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=...
API_BASE_URL=http://10.0.2.2:8000
```

---

## AI Generation Types

| Type             | Description                                                 |
| ---------------- | ----------------------------------------------------------- |
| `mcq`            | Multiple-choice questions with distractors and explanations |
| `flashcards`     | Front/back flashcard decks                                  |
| `qa`             | Short-answer Q&A pairs                                      |
| `summary`        | Structured topic summary                                    |
| `mind_map`       | Hierarchical concept map                                    |
| `revision_sheet` | Condensed revision notes                                    |
| `mnemonics`      | Memory aids for key terms                                   |
| `key_concepts`   | Extracted key concepts with definitions                     |

All types are grounded in the user's uploaded documents via RAG when documents are available, falling back to Gemini's knowledge for the subject topic.

---

## License

MIT — open source, free to use and modify.
