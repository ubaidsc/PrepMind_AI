# PrepMind AI — Phase 2 Build Guide

> **For AI Agent Use** | Agentic AI Pipeline + RAG + Document Processing | Token-Optimized Architecture

---

## What This Phase Delivers

After Phase 2, a user can:

1. Upload up to 5 files (PDF, DOCX, PPTX) to a subject
2. See documents processed in the background (chunked + embedded)
3. Tap any generation button → receive structured AI output (summary, MCQs, flashcards, etc.)
4. Chat with AI about their subject using persistent context
5. All of this on free Gemini API keys with a multi-key rotation strategy

**Phase 2 builds on top of Phase 1.** All auth, navigation, subjects, and Supabase schema from Phase 1 are assumed to be working.

---

## Critical Architecture Decisions (Read Before Building)

### Why RAG over Full-Context for This App

Given free tier limits of Gemini 2.5 Flash (10 RPM, 250 RPD, 250K TPM):

- A single 5-file subject could contain 50,000–150,000 tokens of raw text
- Sending all that on every chat message would exhaust the daily quota in ~2 requests
- RAG retrieves only the top 5–8 relevant chunks (~3,000–6,000 tokens) per query
- **Result: 10–30x more requests per day on the same free quota**

### Model Routing Strategy (Token-Optimized)

Use two Gemini models with different purposes:

| Task                                                 | Model                                   | Why                                         |
| ---------------------------------------------------- | --------------------------------------- | ------------------------------------------- |
| Embeddings                                           | `text-embedding-004`                    | Free, 2048 dimensions, zero generation cost |
| Chat + Generation                                    | `gemini-2.5-flash`                      | 250 RPD free, fast, good quality            |
| Complex generation (summaries, full revision sheets) | `gemini-2.5-flash` with thinking budget | Same model, better output                   |

**Never use Gemini 2.5 Pro on free tier** — only 100 RPD, not worth it.

### Multi-Key Rotation Architecture

Since limits are per Google Cloud **project** (not per API key), you need multiple Google accounts, each with its own project and API key:

```
KEY_POOL = [KEY_1, KEY_2, KEY_3, ...]

On every API call:
1. Try current key
2. If 429 received → rotate to next key → retry immediately
3. Track daily usage per key in Supabase
4. At midnight PT, reset usage counters
```

This is the single most impactful optimization for free tier sustainability.

### Chunking Strategy

```
Chunk size: 600 tokens (~450 words)
Overlap: 100 tokens (~75 words)
Reason: Small enough to be semantically focused, large enough for context.
For RAG retrieval: top_k = 6 chunks = ~3,600 tokens of context
```

---

## Part 1: Supabase Schema Additions

Execute this SQL in Supabase SQL Editor (adds to Phase 1 schema):

```sql
-- =============================================
-- ENABLE PGVECTOR
-- =============================================
create extension if not exists vector;

-- =============================================
-- DOCUMENT CHUNKS TABLE (RAG backbone)
-- =============================================
create table public.document_chunks (
  id uuid primary key default uuid_generate_v4(),
  document_id uuid not null references public.documents(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  content text not null,
  chunk_index integer not null,
  token_count integer not null default 0,
  embedding vector(768),         -- Gemini text-embedding-004 outputs 768 dims
  metadata jsonb default '{}',   -- page_number, section_title, etc.
  created_at timestamptz not null default now()
);

-- HNSW index for fast approximate nearest neighbor search
create index on public.document_chunks
  using hnsw (embedding vector_cosine_ops)
  with (m = 16, ef_construction = 64);

-- Index for fast subject/user filtering
create index on public.document_chunks (subject_id, user_id);
create index on public.document_chunks (document_id);

-- =============================================
-- AI GENERATIONS TABLE (cache outputs)
-- =============================================
create table public.ai_generations (
  id uuid primary key default uuid_generate_v4(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  generation_type text not null check (generation_type in (
    'summary', 'key_points', 'mcq', 'flashcards',
    'five_mark_qa', 'ten_mark_qa', 'revision_sheet', 'mind_map'
  )),
  content jsonb not null,         -- Structured JSON output (see System Prompts section)
  document_ids uuid[] not null,   -- Which documents were used
  prompt_tokens integer default 0,
  completion_tokens integer default 0,
  model_used text default 'gemini-2.5-flash',
  created_at timestamptz not null default now()
);

create index on public.ai_generations (subject_id, generation_type);

-- =============================================
-- CHAT SESSIONS TABLE
-- =============================================
create table public.chat_sessions (
  id uuid primary key default uuid_generate_v4(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- =============================================
-- CHAT MESSAGES TABLE
-- =============================================
create table public.chat_messages (
  id uuid primary key default uuid_generate_v4(),
  session_id uuid not null references public.chat_sessions(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null,
  retrieved_chunk_ids uuid[],    -- Which chunks were used for RAG (for transparency)
  prompt_tokens integer default 0,
  completion_tokens integer default 0,
  created_at timestamptz not null default now()
);

create index on public.chat_messages (session_id, created_at);

-- =============================================
-- API KEY ROTATION TRACKER
-- =============================================
create table public.api_key_usage (
  id uuid primary key default uuid_generate_v4(),
  key_alias text not null unique,   -- 'key_1', 'key_2', etc (NOT the actual key)
  requests_today integer not null default 0,
  tokens_today integer not null default 0,
  last_reset_at timestamptz not null default now(),
  is_active boolean not null default true,
  last_used_at timestamptz
);

-- Pre-insert your key aliases (actual keys stay in .env)
insert into public.api_key_usage (key_alias) values ('key_1'), ('key_2'), ('key_3');

-- =============================================
-- SUBJECT AI CONTEXT (compressed memory)
-- =============================================
create table public.subject_context (
  subject_id uuid primary key references public.subjects(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  compressed_summary text,       -- AI-compressed overview of ALL uploaded docs
  topics_covered text[],         -- Extracted topic list
  total_chunks integer default 0,
  total_tokens_indexed integer default 0,
  last_indexed_at timestamptz,
  updated_at timestamptz not null default now()
);

-- =============================================
-- RLS POLICIES FOR NEW TABLES
-- =============================================

alter table public.document_chunks enable row level security;
create policy "chunks_select_own" on public.document_chunks for select using (auth.uid() = user_id);

alter table public.ai_generations enable row level security;
create policy "generations_select_own" on public.ai_generations for select using (auth.uid() = user_id);
create policy "generations_insert_own" on public.ai_generations for insert with check (auth.uid() = user_id);

alter table public.chat_sessions enable row level security;
create policy "chat_sessions_all_own" on public.chat_sessions for all using (auth.uid() = user_id);

alter table public.chat_messages enable row level security;
create policy "chat_messages_all_own" on public.chat_messages for all using (auth.uid() = user_id);

alter table public.subject_context enable row level security;
create policy "subject_context_all_own" on public.subject_context for all using (auth.uid() = user_id);

-- =============================================
-- VECTOR SIMILARITY SEARCH FUNCTION
-- (called from FastAPI for RAG retrieval)
-- =============================================
create or replace function match_chunks(
  query_embedding vector(768),
  filter_subject_id uuid,
  filter_user_id uuid,
  match_count integer default 6,
  similarity_threshold float default 0.5
)
returns table (
  id uuid,
  content text,
  metadata jsonb,
  document_id uuid,
  similarity float
)
language plpgsql
as $$
begin
  return query
  select
    dc.id,
    dc.content,
    dc.metadata,
    dc.document_id,
    1 - (dc.embedding <=> query_embedding) as similarity
  from public.document_chunks dc
  where
    dc.subject_id = filter_subject_id
    and dc.user_id = filter_user_id
    and dc.embedding is not null
    and 1 - (dc.embedding <=> query_embedding) > similarity_threshold
  order by dc.embedding <=> query_embedding
  limit match_count;
end;
$$;
```

---

## Part 2: FastAPI Backend — New Structure

Add these to the existing Phase 1 structure:

```
prepmind_api/
├── app/
│   ├── ...existing Phase 1 files...
│   │
│   ├── core/
│   │   ├── ...existing...
│   │   ├── gemini.py            # Gemini client + key rotation
│   │   └── document_processor.py # PDF/DOCX/PPTX text extraction
│   │
│   ├── models/
│   │   ├── ...existing...
│   │   ├── ai.py                # AI generation request/response schemas
│   │   └── chat.py              # Chat schemas
│   │
│   ├── services/
│   │   ├── __init__.py
│   │   ├── chunker.py           # Text chunking logic
│   │   ├── embedder.py          # Embedding generation
│   │   ├── rag.py               # RAG retrieval pipeline
│   │   ├── generator.py         # AI content generation
│   │   └── document_pipeline.py # Orchestrates full upload→embed flow
│   │
│   └── routers/
│       ├── ...existing...
│       ├── documents.py         # UPDATED with upload + processing
│       ├── ai.py                # /ai/* generation endpoints
│       └── chat.py              # /chat/* endpoints
│
├── requirements.txt             # Updated
└── .env
```

### Updated requirements.txt

```
fastapi==0.115.0
uvicorn[standard]==0.30.6
supabase==2.9.1
python-jose[cryptography]==3.3.0
python-multipart==0.0.9
pydantic==2.9.2
pydantic-settings==2.5.2
httpx==0.27.2
python-dotenv==1.0.1

# Document processing
pymupdf==1.24.10          # PDF extraction (fitz) — fast and accurate
python-docx==1.1.2        # DOCX extraction
python-pptx==1.0.2        # PPTX extraction

# Gemini
google-generativeai==0.8.3

# Text processing
tiktoken==0.7.0           # Token counting
nltk==3.9.1               # Sentence tokenization for smart chunking

# Async
asyncio==3.4.3

# Testing
pytest==8.3.3
pytest-asyncio==0.24.0
```

### Updated .env

```
# Supabase (from Phase 1)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
SUPABASE_JWT_SECRET=your_jwt_secret

# Gemini API Key Pool (add more keys as you get them)
GEMINI_KEY_1=AIza...
GEMINI_KEY_2=AIza...
GEMINI_KEY_3=AIza...

# App
APP_ENV=development
ALLOWED_ORIGINS=http://localhost:3000
MAX_FILE_SIZE_MB=20
FREE_PLAN_FILE_LIMIT=5
```

---

## Part 3: Core AI Services

### `app/core/gemini.py` — Key Rotation Client

```python
import os
import asyncio
import google.generativeai as genai
from datetime import datetime, timezone
from app.core.supabase import get_supabase_client

class GeminiKeyRotator:
    """
    Manages a pool of Gemini API keys.
    Rotates automatically on 429 errors.
    Tracks usage in Supabase.
    """

    def __init__(self):
        self._keys: dict[str, str] = {}
        self._current_index = 0
        self._load_keys()

    def _load_keys(self):
        i = 1
        while True:
            key = os.getenv(f"GEMINI_KEY_{i}")
            if not key:
                break
            self._keys[f"key_{i}"] = key
            i += 1
        if not self._keys:
            raise ValueError("No GEMINI_KEY_* environment variables found")

    @property
    def _key_list(self) -> list[tuple[str, str]]:
        return list(self._keys.items())

    def _get_current(self) -> tuple[str, str]:
        return self._key_list[self._current_index % len(self._key_list)]

    def _rotate(self):
        self._current_index = (self._current_index + 1) % len(self._key_list)

    async def _log_usage(self, key_alias: str, tokens: int):
        """Update usage counter in Supabase asynchronously."""
        try:
            supabase = get_supabase_client()
            supabase.rpc("increment_key_usage", {
                "p_key_alias": key_alias,
                "p_tokens": tokens
            }).execute()
        except Exception:
            pass  # Non-critical

    async def generate_content(
        self,
        model_name: str,
        contents: list,
        generation_config: dict = None,
        max_retries: int = None,
    ) -> any:
        """
        Generate content with automatic key rotation on 429.
        Returns the GenerateContentResponse.
        """
        max_retries = max_retries or len(self._keys)
        last_error = None

        for attempt in range(max_retries):
            alias, key = self._get_current()
            try:
                genai.configure(api_key=key)
                model = genai.GenerativeModel(model_name)
                config = genai.types.GenerationConfig(**(generation_config or {}))
                response = model.generate_content(contents, generation_config=config)
                # Log usage (fire and forget)
                total_tokens = getattr(response.usage_metadata, 'total_token_count', 0)
                asyncio.create_task(self._log_usage(alias, total_tokens))
                return response
            except Exception as e:
                last_error = e
                err_str = str(e).lower()
                if "429" in err_str or "quota" in err_str or "resource_exhausted" in err_str:
                    self._rotate()
                    await asyncio.sleep(0.5)
                    continue
                raise  # Non-quota errors re-raised immediately

        raise last_error

    async def get_embedding(self, text: str) -> list[float]:
        """Generate embedding using text-embedding-004."""
        max_retries = len(self._keys)
        last_error = None

        for attempt in range(max_retries):
            alias, key = self._get_current()
            try:
                genai.configure(api_key=key)
                result = genai.embed_content(
                    model="models/text-embedding-004",
                    content=text,
                    task_type="retrieval_document",
                )
                return result["embedding"]
            except Exception as e:
                last_error = e
                err_str = str(e).lower()
                if "429" in err_str or "quota" in err_str:
                    self._rotate()
                    await asyncio.sleep(0.5)
                    continue
                raise

        raise last_error

    async def get_query_embedding(self, text: str) -> list[float]:
        """Generate query embedding (different task_type for better retrieval)."""
        _, key = self._get_current()
        genai.configure(api_key=key)
        result = genai.embed_content(
            model="models/text-embedding-004",
            content=text,
            task_type="retrieval_query",
        )
        return result["embedding"]


# Singleton
_rotator: GeminiKeyRotator = None

def get_gemini() -> GeminiKeyRotator:
    global _rotator
    if _rotator is None:
        _rotator = GeminiKeyRotator()
    return _rotator
```

Add this SQL function to Supabase for the usage counter:

```sql
create or replace function increment_key_usage(p_key_alias text, p_tokens integer)
returns void language plpgsql as $$
begin
  -- Reset if it's a new day (midnight PT = UTC-8, so UTC 08:00)
  update public.api_key_usage
  set
    requests_today = case
      when date_trunc('day', now() at time zone 'America/Los_Angeles')
         > date_trunc('day', last_reset_at at time zone 'America/Los_Angeles')
      then 1
      else requests_today + 1
    end,
    tokens_today = case
      when date_trunc('day', now() at time zone 'America/Los_Angeles')
         > date_trunc('day', last_reset_at at time zone 'America/Los_Angeles')
      then p_tokens
      else tokens_today + p_tokens
    end,
    last_reset_at = case
      when date_trunc('day', now() at time zone 'America/Los_Angeles')
         > date_trunc('day', last_reset_at at time zone 'America/Los_Angeles')
      then now()
      else last_reset_at
    end,
    last_used_at = now()
  where key_alias = p_key_alias;
end;
$$;
```

---

### `app/core/document_processor.py` — Text Extraction

```python
import io
import fitz          # PyMuPDF
import docx
from pptx import Presentation
from pptx.util import Inches

class DocumentProcessor:
    """Extracts clean text from PDF, DOCX, PPTX files."""

    @staticmethod
    def extract_from_pdf(file_bytes: bytes) -> str:
        doc = fitz.open(stream=file_bytes, filetype="pdf")
        pages = []
        for page_num, page in enumerate(doc):
            text = page.get_text("text")
            if text.strip():
                pages.append(f"[Page {page_num + 1}]\n{text.strip()}")
        return "\n\n".join(pages)

    @staticmethod
    def extract_from_docx(file_bytes: bytes) -> str:
        doc = docx.Document(io.BytesIO(file_bytes))
        paragraphs = []
        for para in doc.paragraphs:
            if para.text.strip():
                # Detect headings
                if para.style.name.startswith("Heading"):
                    paragraphs.append(f"\n## {para.text.strip()}")
                else:
                    paragraphs.append(para.text.strip())
        return "\n\n".join(paragraphs)

    @staticmethod
    def extract_from_pptx(file_bytes: bytes) -> str:
        prs = Presentation(io.BytesIO(file_bytes))
        slides = []
        for i, slide in enumerate(prs.slides):
            slide_text = []
            for shape in slide.shapes:
                if hasattr(shape, "text") and shape.text.strip():
                    slide_text.append(shape.text.strip())
            if slide_text:
                slides.append(f"[Slide {i + 1}]\n" + "\n".join(slide_text))
        return "\n\n".join(slides)

    @classmethod
    def extract(cls, file_bytes: bytes, file_type: str) -> str:
        """Route to correct extractor based on file type."""
        if file_type == "pdf":
            return cls.extract_from_pdf(file_bytes)
        elif file_type == "docx":
            return cls.extract_from_docx(file_bytes)
        elif file_type == "pptx":
            return cls.extract_from_pptx(file_bytes)
        else:
            raise ValueError(f"Unsupported file type: {file_type}")
```

---

### `app/services/chunker.py` — Smart Text Chunking

```python
import re
import tiktoken

CHUNK_SIZE_TOKENS = 600
OVERLAP_TOKENS = 100

_enc = tiktoken.get_encoding("cl100k_base")  # Close to Gemini tokenization

def count_tokens(text: str) -> int:
    return len(_enc.encode(text))

def chunk_text(text: str, document_name: str = "") -> list[dict]:
    """
    Splits text into overlapping chunks of ~600 tokens.
    Respects sentence boundaries — never cuts mid-sentence.
    Returns list of {content, chunk_index, token_count, metadata}
    """
    # Split into sentences first
    sentences = _split_sentences(text)

    chunks = []
    current_chunk_sentences = []
    current_tokens = 0
    chunk_index = 0

    for sentence in sentences:
        sentence_tokens = count_tokens(sentence)

        # If adding this sentence exceeds limit, flush current chunk
        if current_tokens + sentence_tokens > CHUNK_SIZE_TOKENS and current_chunk_sentences:
            chunk_text_str = " ".join(current_chunk_sentences)
            chunks.append({
                "content": chunk_text_str,
                "chunk_index": chunk_index,
                "token_count": current_tokens,
                "metadata": {"document_name": document_name, "chunk_index": chunk_index}
            })
            chunk_index += 1

            # Overlap: keep last ~OVERLAP_TOKENS worth of sentences
            overlap_sentences = []
            overlap_tokens = 0
            for s in reversed(current_chunk_sentences):
                t = count_tokens(s)
                if overlap_tokens + t > OVERLAP_TOKENS:
                    break
                overlap_sentences.insert(0, s)
                overlap_tokens += t

            current_chunk_sentences = overlap_sentences
            current_tokens = overlap_tokens

        current_chunk_sentences.append(sentence)
        current_tokens += sentence_tokens

    # Flush remaining
    if current_chunk_sentences:
        chunk_text_str = " ".join(current_chunk_sentences)
        chunks.append({
            "content": chunk_text_str,
            "chunk_index": chunk_index,
            "token_count": current_tokens,
            "metadata": {"document_name": document_name, "chunk_index": chunk_index}
        })

    return chunks


def _split_sentences(text: str) -> list[str]:
    """Simple sentence splitter that handles academic text."""
    # Normalize whitespace
    text = re.sub(r'\s+', ' ', text).strip()
    # Split on sentence boundaries
    sentences = re.split(r'(?<=[.!?])\s+(?=[A-Z])', text)
    # Filter empty
    return [s.strip() for s in sentences if s.strip() and len(s.strip()) > 10]
```

---

### `app/services/document_pipeline.py` — Full Processing Orchestrator

```python
import asyncio
from app.core.document_processor import DocumentProcessor
from app.core.gemini import get_gemini
from app.core.supabase import get_supabase_client
from app.services.chunker import chunk_text

async def process_document(
    document_id: str,
    subject_id: str,
    user_id: str,
    file_bytes: bytes,
    file_type: str,
    file_name: str,
) -> dict:
    """
    Full pipeline:
    1. Extract text from file
    2. Chunk into ~600 token pieces
    3. Generate embeddings for each chunk
    4. Store chunks + embeddings in Supabase
    5. Update document status
    6. Update subject_context

    Returns: {"chunks_created": int, "total_tokens": int}
    """
    supabase = get_supabase_client()
    gemini = get_gemini()

    try:
        # Step 1: Mark document as processing
        supabase.table("documents").update({"status": "processing"}).eq("id", document_id).execute()

        # Step 2: Extract text
        text = DocumentProcessor.extract(file_bytes, file_type)
        if not text.strip():
            raise ValueError("No text could be extracted from document")

        # Step 3: Chunk text
        chunks = chunk_text(text, document_name=file_name)
        if not chunks:
            raise ValueError("No chunks generated")

        # Step 4: Generate embeddings in batches of 5
        # (to avoid TPM limits and be safe with free tier)
        batch_size = 5
        all_chunk_records = []

        for i in range(0, len(chunks), batch_size):
            batch = chunks[i:i + batch_size]
            # Generate embeddings sequentially within batch (free tier is RPM limited)
            for chunk in batch:
                embedding = await gemini.get_embedding(chunk["content"])
                all_chunk_records.append({
                    "document_id": document_id,
                    "subject_id": subject_id,
                    "user_id": user_id,
                    "content": chunk["content"],
                    "chunk_index": chunk["chunk_index"],
                    "token_count": chunk["token_count"],
                    "embedding": embedding,
                    "metadata": chunk["metadata"],
                })
                # Small delay to respect rate limits
                await asyncio.sleep(0.3)

        # Step 5: Bulk insert chunks (Supabase handles this efficiently)
        supabase.table("document_chunks").insert(all_chunk_records).execute()

        total_tokens = sum(c["token_count"] for c in chunks)

        # Step 6: Mark document as ready
        supabase.table("documents").update({
            "status": "ready",
            "page_count": len([c for c in chunks])
        }).eq("id", document_id).execute()

        # Step 7: Update subject document count
        supabase.rpc("increment_subject_doc_count", {"p_subject_id": subject_id}).execute()

        # Step 8: Update subject_context (upsert)
        supabase.table("subject_context").upsert({
            "subject_id": subject_id,
            "user_id": user_id,
            "total_chunks": len(all_chunk_records),
            "total_tokens_indexed": total_tokens,
            "last_indexed_at": "now()",
        }).execute()

        return {"chunks_created": len(chunks), "total_tokens": total_tokens}

    except Exception as e:
        # Mark document as failed
        supabase.table("documents").update({
            "status": "failed",
            "error_message": str(e)[:500]
        }).eq("id", document_id).execute()
        raise
```

Add this helper SQL function:

```sql
create or replace function increment_subject_doc_count(p_subject_id uuid)
returns void language plpgsql as $$
begin
  update public.subjects
  set document_count = document_count + 1,
      updated_at = now()
  where id = p_subject_id;
end;
$$;
```

---

### `app/services/rag.py` — Retrieval Pipeline

```python
from app.core.gemini import get_gemini
from app.core.supabase import get_supabase_client

async def retrieve_relevant_chunks(
    query: str,
    subject_id: str,
    user_id: str,
    top_k: int = 6,
    similarity_threshold: float = 0.5,
) -> list[dict]:
    """
    1. Embed the query (using retrieval_query task type)
    2. Vector similarity search in Supabase
    3. Return top_k most relevant chunks
    """
    gemini = get_gemini()
    supabase = get_supabase_client()

    query_embedding = await gemini.get_query_embedding(query)

    result = supabase.rpc("match_chunks", {
        "query_embedding": query_embedding,
        "filter_subject_id": subject_id,
        "filter_user_id": user_id,
        "match_count": top_k,
        "similarity_threshold": similarity_threshold,
    }).execute()

    return result.data or []


def build_context_block(chunks: list[dict]) -> str:
    """Format retrieved chunks into a clean context block for the prompt."""
    if not chunks:
        return "No relevant context found."
    parts = []
    for i, chunk in enumerate(chunks):
        doc_name = chunk.get("metadata", {}).get("document_name", "Unknown Document")
        parts.append(f"[Source {i+1} — {doc_name}]\n{chunk['content']}")
    return "\n\n---\n\n".join(parts)
```

---

## Part 4: System Prompts (The Core Intelligence)

These are the engineered prompts. They are embedded in `app/services/generator.py`.

### Master Academic System Prompt

```python
ACADEMIC_SYSTEM_PROMPT = """You are PrepMind AI — a specialized academic assistant designed exclusively for exam preparation.

YOUR ROLE:
- Help students understand, summarize, and practice their course material
- Generate exam-focused, structured outputs
- Always base responses on the provided academic context
- Be concise, accurate, and exam-ready in your outputs

RESPONSE RULES:
- Always respond in valid JSON matching the schema requested
- Never add conversational filler or preamble before the JSON
- If context is insufficient, say so in the JSON's "note" field
- Prioritize exam-relevant information over background knowledge
- Use simple, clear academic language suitable for university students"""
```

### Generation Prompt Templates

```python
GENERATION_PROMPTS = {

    "summary": {
        "system": ACADEMIC_SYSTEM_PROMPT,
        "user_template": """Based on the following academic content from the subject "{subject_name}", generate a comprehensive bullet-point summary.

ACADEMIC CONTENT:
{context}

Return ONLY this JSON:
{{
  "type": "summary",
  "subject": "{subject_name}",
  "sections": [
    {{
      "title": "Section/Topic Title",
      "bullets": ["Key point 1", "Key point 2", "..."]
    }}
  ],
  "total_points": <integer>,
  "note": "<optional: any limitation or missing context>"
}}"""
    },

    "key_points": {
        "system": ACADEMIC_SYSTEM_PROMPT,
        "user_template": """From the following academic content for "{subject_name}", extract the most important exam-relevant key points.

ACADEMIC CONTENT:
{context}

Return ONLY this JSON:
{{
  "type": "key_points",
  "subject": "{subject_name}",
  "points": [
    {{
      "point": "Key fact or concept",
      "importance": "high|medium",
      "category": "definition|formula|concept|process|example"
    }}
  ],
  "note": "<optional>"
}}"""
    },

    "mcq": {
        "system": ACADEMIC_SYSTEM_PROMPT,
        "user_template": """Generate {count} multiple choice questions (MCQs) for exam practice based on "{subject_name}".

ACADEMIC CONTENT:
{context}

Rules:
- Each question must be directly answerable from the content
- One clearly correct answer, three plausible distractors
- Include brief explanation for the correct answer
- Difficulty: mix of easy (30%), medium (50%), hard (20%)

Return ONLY this JSON:
{{
  "type": "mcq",
  "subject": "{subject_name}",
  "questions": [
    {{
      "id": 1,
      "question": "Question text?",
      "options": {{
        "A": "Option A",
        "B": "Option B",
        "C": "Option C",
        "D": "Option D"
      }},
      "correct": "B",
      "explanation": "Brief explanation of why B is correct",
      "difficulty": "easy|medium|hard",
      "topic": "Topic name"
    }}
  ],
  "note": "<optional>"
}}"""
    },

    "flashcards": {
        "system": ACADEMIC_SYSTEM_PROMPT,
        "user_template": """Create {count} flashcards for studying "{subject_name}". Focus on definitions, formulas, concepts, and key facts.

ACADEMIC CONTENT:
{context}

Return ONLY this JSON:
{{
  "type": "flashcards",
  "subject": "{subject_name}",
  "cards": [
    {{
      "id": 1,
      "front": "Question or term",
      "back": "Answer or definition (concise, max 3 sentences)",
      "category": "definition|formula|concept|date|person|process",
      "difficulty": "easy|medium|hard"
    }}
  ],
  "note": "<optional>"
}}"""
    },

    "five_mark_qa": {
        "system": ACADEMIC_SYSTEM_PROMPT,
        "user_template": """Generate {count} five-mark exam questions with model answers for "{subject_name}".

ACADEMIC CONTENT:
{context}

A 5-mark answer should be 150-200 words with 3-5 clear points.

Return ONLY this JSON:
{{
  "type": "five_mark_qa",
  "subject": "{subject_name}",
  "questions": [
    {{
      "id": 1,
      "question": "Question text",
      "answer": "Model answer text (150-200 words)",
      "key_points": ["Point 1", "Point 2", "Point 3"],
      "topic": "Topic name"
    }}
  ],
  "note": "<optional>"
}}"""
    },

    "ten_mark_qa": {
        "system": ACADEMIC_SYSTEM_PROMPT,
        "user_template": """Generate {count} ten-mark exam questions with detailed model answers for "{subject_name}".

ACADEMIC CONTENT:
{context}

A 10-mark answer should be 300-400 words with introduction, main points, and conclusion.

Return ONLY this JSON:
{{
  "type": "ten_mark_qa",
  "subject": "{subject_name}",
  "questions": [
    {{
      "id": 1,
      "question": "Question text",
      "answer": "Detailed model answer (300-400 words)",
      "key_points": ["Point 1", "Point 2", "..."],
      "subtopics": ["Subtopic covered 1", "Subtopic covered 2"],
      "topic": "Topic name"
    }}
  ],
  "note": "<optional>"
}}"""
    },

    "revision_sheet": {
        "system": ACADEMIC_SYSTEM_PROMPT,
        "user_template": """Create a comprehensive revision sheet for "{subject_name}" covering all uploaded material.

ACADEMIC CONTENT:
{context}

Return ONLY this JSON:
{{
  "type": "revision_sheet",
  "subject": "{subject_name}",
  "sections": [
    {{
      "title": "Topic/Chapter Title",
      "overview": "2-3 sentence overview",
      "key_concepts": [
        {{"term": "Term", "definition": "Definition"}}
      ],
      "important_facts": ["Fact 1", "Fact 2"],
      "remember": "One critical thing to remember for exam"
    }}
  ],
  "quick_reference": ["One-liner 1", "One-liner 2"],
  "note": "<optional>"
}}"""
    },

    "mind_map": {
        "system": ACADEMIC_SYSTEM_PROMPT,
        "user_template": """Create a mind map structure for "{subject_name}" that shows how topics are connected.

ACADEMIC CONTENT:
{context}

Return ONLY this JSON:
{{
  "type": "mind_map",
  "subject": "{subject_name}",
  "central_topic": "{subject_name}",
  "branches": [
    {{
      "topic": "Main Branch Topic",
      "subtopics": [
        {{
          "name": "Subtopic",
          "details": ["Detail 1", "Detail 2"]
        }}
      ]
    }}
  ],
  "note": "<optional>"
}}"""
    },
}

# Chat system prompt (for ongoing conversation)
CHAT_SYSTEM_PROMPT = """You are PrepMind AI, an academic study assistant for the subject "{subject_name}".

You help students understand their uploaded course material. You have access to relevant excerpts from their documents.

RULES:
- Answer only based on the provided context excerpts
- If something is not in the context, say: "I don't have information about that in your uploaded documents"
- Keep answers concise and exam-focused
- You can explain concepts, answer questions, and help students understand material
- Never make up facts not present in the context
- Format responses in clean, readable text (not JSON)
- Use bullet points and numbered lists where helpful"""
```

---

### `app/services/generator.py` — AI Generation Service

````python
import json
import re
from app.core.gemini import get_gemini
from app.services.rag import retrieve_relevant_chunks, build_context_block
from app.services.generator_prompts import GENERATION_PROMPTS, CHAT_SYSTEM_PROMPT
from app.core.supabase import get_supabase_client

async def generate_ai_content(
    generation_type: str,
    subject_id: str,
    subject_name: str,
    user_id: str,
    count: int = 10,           # For MCQs, flashcards, Q&As
    query: str = None,         # Optional: specific topic focus
    use_cache: bool = True,    # Return cached result if exists
) -> dict:
    """
    Main generation pipeline:
    1. Check cache
    2. RAG retrieval
    3. Build prompt
    4. Call Gemini
    5. Parse + store result
    6. Return structured output
    """
    supabase = get_supabase_client()
    gemini = get_gemini()

    # Step 1: Check cache (avoid regenerating same content)
    if use_cache:
        cached = supabase.table("ai_generations") \
            .select("content") \
            .eq("subject_id", subject_id) \
            .eq("generation_type", generation_type) \
            .order("created_at", desc=True) \
            .limit(1) \
            .execute()
        if cached.data:
            return cached.data[0]["content"]

    # Step 2: RAG - retrieve relevant chunks
    # For generation, use a broad query to get representative content
    rag_query = query or f"{subject_name} key concepts topics overview exam"
    chunks = await retrieve_relevant_chunks(
        query=rag_query,
        subject_id=subject_id,
        user_id=user_id,
        top_k=8,  # More chunks for generation tasks
    )
    context = build_context_block(chunks)

    # Step 3: Build prompt
    prompt_config = GENERATION_PROMPTS[generation_type]
    user_prompt = prompt_config["user_template"].format(
        subject_name=subject_name,
        context=context,
        count=count,
    )

    # Step 4: Call Gemini
    response = await gemini.generate_content(
        model_name="gemini-2.5-flash",
        contents=[
            {"role": "user", "parts": [prompt_config["system"] + "\n\n" + user_prompt]}
        ],
        generation_config={
            "temperature": 0.3,        # Low temp for consistent, accurate outputs
            "max_output_tokens": 4096,
        },
    )

    # Step 5: Parse JSON response
    raw_text = response.text.strip()
    # Strip markdown code fences if present
    raw_text = re.sub(r'^```(?:json)?\s*', '', raw_text)
    raw_text = re.sub(r'\s*```$', '', raw_text)

    try:
        result = json.loads(raw_text)
    except json.JSONDecodeError:
        # Attempt to extract JSON from response
        match = re.search(r'\{.*\}', raw_text, re.DOTALL)
        if match:
            result = json.loads(match.group())
        else:
            raise ValueError(f"Could not parse AI response as JSON: {raw_text[:200]}")

    # Step 6: Cache the result
    usage = response.usage_metadata
    supabase.table("ai_generations").insert({
        "subject_id": subject_id,
        "user_id": user_id,
        "generation_type": generation_type,
        "content": result,
        "document_ids": [c["document_id"] for c in chunks],
        "prompt_tokens": getattr(usage, 'prompt_token_count', 0),
        "completion_tokens": getattr(usage, 'candidates_token_count', 0),
        "model_used": "gemini-2.5-flash",
    }).execute()

    return result


async def chat_with_subject(
    message: str,
    subject_id: str,
    subject_name: str,
    user_id: str,
    session_id: str,
    chat_history: list[dict],   # [{"role": "user/assistant", "content": "..."}]
    max_history_messages: int = 6,
) -> dict:
    """
    Chat pipeline:
    1. RAG retrieval based on user message
    2. Build context-aware prompt with trimmed history
    3. Generate response
    4. Store message pair
    5. Return response

    Token optimization: Only send last 6 messages of history + retrieved context.
    """
    supabase = get_supabase_client()
    gemini = get_gemini()

    # Step 1: Retrieve relevant chunks for this specific message
    chunks = await retrieve_relevant_chunks(
        query=message,
        subject_id=subject_id,
        user_id=user_id,
        top_k=5,               # Fewer for chat (token budget)
        similarity_threshold=0.45,
    )
    context = build_context_block(chunks)
    chunk_ids = [c["id"] for c in chunks]

    # Step 2: Build conversation
    system_prompt = CHAT_SYSTEM_PROMPT.format(subject_name=subject_name)

    # Trim history to last N messages to control token usage
    recent_history = chat_history[-(max_history_messages):]

    # Build contents for Gemini multi-turn
    contents = []
    for msg in recent_history:
        contents.append({
            "role": msg["role"],
            "parts": [msg["content"]]
        })

    # Add current message with context
    current_message = f"""RELEVANT CONTEXT FROM YOUR DOCUMENTS:
{context}

---

STUDENT QUESTION:
{message}"""

    contents.append({"role": "user", "parts": [current_message]})

    # Step 3: Generate
    full_prompt = [{"role": "user", "parts": [system_prompt]}] + contents
    response = await gemini.generate_content(
        model_name="gemini-2.5-flash",
        contents=full_prompt,
        generation_config={
            "temperature": 0.5,
            "max_output_tokens": 1024,  # Keep chat responses concise
        },
    )

    assistant_message = response.text.strip()
    usage = response.usage_metadata

    # Step 4: Store both messages
    supabase.table("chat_messages").insert([
        {
            "session_id": session_id,
            "subject_id": subject_id,
            "user_id": user_id,
            "role": "user",
            "content": message,
        },
        {
            "session_id": session_id,
            "subject_id": subject_id,
            "user_id": user_id,
            "role": "assistant",
            "content": assistant_message,
            "retrieved_chunk_ids": chunk_ids,
            "prompt_tokens": getattr(usage, 'prompt_token_count', 0),
            "completion_tokens": getattr(usage, 'candidates_token_count', 0),
        }
    ]).execute()

    return {
        "message": assistant_message,
        "session_id": session_id,
        "sources_used": len(chunks),
    }
````

---

## Part 5: API Routers

### `app/routers/documents.py` — Updated with Upload + Processing

```python
import asyncio
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, status, BackgroundTasks
from app.dependencies import get_current_user
from app.core.supabase import get_supabase_client
from app.services.document_pipeline import process_document
from app.models.common import APIResponse
import os

router = APIRouter()

ALLOWED_TYPES = {
    "application/pdf": "pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation": "pptx",
}
MAX_FILE_SIZE = int(os.getenv("MAX_FILE_SIZE_MB", 20)) * 1024 * 1024
FREE_PLAN_LIMIT = int(os.getenv("FREE_PLAN_FILE_LIMIT", 5))

@router.post("/upload/{subject_id}", response_model=APIResponse, status_code=status.HTTP_201_CREATED)
async def upload_document(
    subject_id: str,
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    user_id = current_user["id"]

    # Validate file type
    file_type = ALLOWED_TYPES.get(file.content_type)
    if not file_type:
        raise HTTPException(status_code=400, detail="Only PDF, DOCX, PPTX files are allowed")

    # Read file
    file_bytes = await file.read()
    if len(file_bytes) > MAX_FILE_SIZE:
        raise HTTPException(status_code=400, detail=f"File too large. Max {MAX_FILE_SIZE // (1024*1024)}MB")
    if not file_bytes:
        raise HTTPException(status_code=400, detail="Empty file")

    # Check plan limits
    existing = supabase.table("documents") \
        .select("id") \
        .eq("subject_id", subject_id) \
        .eq("user_id", user_id) \
        .neq("status", "failed") \
        .execute()
    if len(existing.data) >= FREE_PLAN_LIMIT:
        raise HTTPException(status_code=403, detail=f"Free plan allows {FREE_PLAN_LIMIT} files per subject")

    # Store file in Supabase Storage
    storage_path = f"{user_id}/{subject_id}/{file.filename}"
    supabase.storage.from_("documents").upload(storage_path, file_bytes, {"contentType": file.content_type})

    # Create document record
    doc = supabase.table("documents").insert({
        "subject_id": subject_id,
        "user_id": user_id,
        "name": file.filename,
        "file_type": file_type,
        "file_size_bytes": len(file_bytes),
        "storage_path": storage_path,
        "status": "uploaded",
    }).select().single().execute()

    document_id = doc.data["id"]

    # Process in background (chunking + embedding)
    background_tasks.add_task(
        process_document,
        document_id=document_id,
        subject_id=subject_id,
        user_id=user_id,
        file_bytes=file_bytes,
        file_type=file_type,
        file_name=file.filename,
    )

    return APIResponse(
        data=doc.data,
        message="Document uploaded. Processing in background..."
    )


@router.get("/{subject_id}", response_model=APIResponse)
async def list_documents(
    subject_id: str,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    result = supabase.table("documents") \
        .select("*") \
        .eq("subject_id", subject_id) \
        .eq("user_id", current_user["id"]) \
        .order("created_at", desc=True) \
        .execute()
    return APIResponse(data=result.data)
```

### `app/routers/ai.py` — AI Generation Endpoints

```python
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Optional
from app.dependencies import get_current_user
from app.core.supabase import get_supabase_client
from app.services.generator import generate_ai_content
from app.models.common import APIResponse

router = APIRouter()

VALID_TYPES = [
    "summary", "key_points", "mcq", "flashcards",
    "five_mark_qa", "ten_mark_qa", "revision_sheet", "mind_map"
]

class GenerateRequest(BaseModel):
    subject_id: str
    generation_type: str
    count: Optional[int] = 10        # For MCQ, flashcards, Q&A
    query: Optional[str] = None      # Topic focus (optional)
    force_regenerate: bool = False   # Skip cache

@router.post("/generate", response_model=APIResponse)
async def generate(
    payload: GenerateRequest,
    current_user: dict = Depends(get_current_user),
):
    if payload.generation_type not in VALID_TYPES:
        raise HTTPException(status_code=400, detail=f"Invalid generation_type. Choose from: {VALID_TYPES}")

    supabase = get_supabase_client()

    # Get subject name
    subject = supabase.table("subjects") \
        .select("name") \
        .eq("id", payload.subject_id) \
        .eq("user_id", current_user["id"]) \
        .single() \
        .execute()

    if not subject.data:
        raise HTTPException(status_code=404, detail="Subject not found")

    # Check documents are ready
    ready_docs = supabase.table("documents") \
        .select("id") \
        .eq("subject_id", payload.subject_id) \
        .eq("status", "ready") \
        .execute()

    if not ready_docs.data:
        raise HTTPException(status_code=400, detail="No processed documents found. Please wait for documents to finish processing.")

    try:
        result = await generate_ai_content(
            generation_type=payload.generation_type,
            subject_id=payload.subject_id,
            subject_name=subject.data["name"],
            user_id=current_user["id"],
            count=payload.count,
            query=payload.query,
            use_cache=not payload.force_regenerate,
        )
        return APIResponse(data=result)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Generation failed: {str(e)}")


@router.get("/history/{subject_id}", response_model=APIResponse)
async def get_generation_history(
    subject_id: str,
    generation_type: Optional[str] = None,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    query = supabase.table("ai_generations") \
        .select("id, generation_type, created_at, prompt_tokens, completion_tokens") \
        .eq("subject_id", subject_id) \
        .eq("user_id", current_user["id"]) \
        .order("created_at", desc=True)

    if generation_type:
        query = query.eq("generation_type", generation_type)

    result = query.limit(20).execute()
    return APIResponse(data=result.data)
```

### `app/routers/chat.py` — Chat Endpoints

```python
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from app.dependencies import get_current_user
from app.core.supabase import get_supabase_client
from app.services.generator import chat_with_subject
from app.models.common import APIResponse

router = APIRouter()

class ChatRequest(BaseModel):
    subject_id: str
    message: str
    session_id: str | None = None    # None = start new session

@router.post("/message", response_model=APIResponse)
async def send_message(
    payload: ChatRequest,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    user_id = current_user["id"]

    # Get subject
    subject = supabase.table("subjects") \
        .select("name") \
        .eq("id", payload.subject_id) \
        .eq("user_id", user_id) \
        .single() \
        .execute()

    if not subject.data:
        raise HTTPException(status_code=404, detail="Subject not found")

    # Create session if not provided
    session_id = payload.session_id
    if not session_id:
        session = supabase.table("chat_sessions").insert({
            "subject_id": payload.subject_id,
            "user_id": user_id,
            "title": payload.message[:50] + "..." if len(payload.message) > 50 else payload.message,
        }).select().single().execute()
        session_id = session.data["id"]

    # Load chat history for this session (last 10 messages)
    history_result = supabase.table("chat_messages") \
        .select("role, content") \
        .eq("session_id", session_id) \
        .order("created_at", ascending=True) \
        .limit(10) \
        .execute()
    chat_history = history_result.data or []

    try:
        result = await chat_with_subject(
            message=payload.message,
            subject_id=payload.subject_id,
            subject_name=subject.data["name"],
            user_id=user_id,
            session_id=session_id,
            chat_history=chat_history,
        )
        return APIResponse(data=result)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/sessions/{subject_id}", response_model=APIResponse)
async def get_sessions(
    subject_id: str,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    result = supabase.table("chat_sessions") \
        .select("*") \
        .eq("subject_id", subject_id) \
        .eq("user_id", current_user["id"]) \
        .order("updated_at", desc=True) \
        .limit(10) \
        .execute()
    return APIResponse(data=result.data)


@router.get("/messages/{session_id}", response_model=APIResponse)
async def get_messages(
    session_id: str,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    result = supabase.table("chat_messages") \
        .select("role, content, created_at") \
        .eq("session_id", session_id) \
        .eq("user_id", current_user["id"]) \
        .order("created_at", ascending=True) \
        .execute()
    return APIResponse(data=result.data)
```

### Update `app/main.py`

```python
# Add these imports to existing main.py
from app.routers import ai, chat

# Add after existing routers:
app.include_router(ai.router, prefix="/ai", tags=["ai"])
app.include_router(chat.router, prefix="/chat", tags=["chat"])
```

---

## Part 6: Flutter App — Phase 2 Additions

### New Files to Add

```
lib/features/
├── documents/
│   ├── data/
│   │   ├── document_model.dart
│   │   └── document_repository.dart
│   ├── providers/
│   │   └── documents_provider.dart
│   └── screens/
│       └── upload_document_screen.dart
│
├── ai_notes/
│   ├── data/
│   │   └── ai_note_model.dart
│   ├── providers/
│   │   └── ai_notes_provider.dart
│   └── screens/
│       ├── ai_result_screen.dart
│       └── generate_options_screen.dart
│
└── chat/
    ├── data/
    │   └── chat_repository.dart
    ├── providers/
    │   └── chat_provider.dart
    └── screens/
        └── chat_screen.dart
```

### Add to `pubspec.yaml`

```yaml
file_picker: ^8.1.2 # Already added in Phase 1
dio: ^5.7.0 # Already added
flutter_markdown: ^0.7.3 # For rendering AI responses
lottie: ^3.1.2 # For processing animation
```

### `lib/features/documents/data/document_model.dart`

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'document_model.freezed.dart';
part 'document_model.g.dart';

@freezed
class DocumentModel with _$DocumentModel {
  const factory DocumentModel({
    required String id,
    required String subjectId,
    required String name,
    required String fileType,
    required int fileSizeBytes,
    required String status,    // uploaded | processing | ready | failed
    String? errorMessage,
    required DateTime createdAt,
  }) = _DocumentModel;

  factory DocumentModel.fromJson(Map<String, dynamic> json) => _$DocumentModelFromJson(json);
}
```

### `lib/features/documents/data/document_repository.dart`

```dart
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'document_model.dart';

class DocumentRepository {
  final Dio _dio;
  final String _baseUrl;

  DocumentRepository({required String baseUrl})
      : _dio = Dio(),
        _baseUrl = baseUrl {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          options.headers['Authorization'] = 'Bearer ${session.accessToken}';
        }
        handler.next(options);
      },
    ));
  }

  Future<DocumentModel> uploadDocument({
    required String subjectId,
    required String filePath,
    required String fileName,
    required String mimeType,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName,
          contentType: DioMediaType.parse(mimeType)),
    });

    final response = await _dio.post(
      '$_baseUrl/documents/upload/$subjectId',
      data: formData,
    );
    return DocumentModel.fromJson(response.data['data']);
  }

  Future<List<DocumentModel>> getDocuments(String subjectId) async {
    final response = await _dio.get('$_baseUrl/documents/$subjectId');
    return (response.data['data'] as List)
        .map((e) => DocumentModel.fromJson(e))
        .toList();
  }

  // Poll document status until ready or failed
  Stream<DocumentModel> pollDocumentStatus(String subjectId, String documentId) async* {
    while (true) {
      final docs = await getDocuments(subjectId);
      final doc = docs.firstWhere((d) => d.id == documentId);
      yield doc;
      if (doc.status == 'ready' || doc.status == 'failed') break;
      await Future.delayed(const Duration(seconds: 3));
    }
  }
}
```

### `lib/features/chat/screens/chat_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/app_button.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String subjectId;
  final String subjectName;

  const ChatScreen({
    super.key,
    required this.subjectId,
    required this.subjectName,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  String? _sessionId;
  bool _isLoading = false;

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final message = _controller.text.trim();
    if (message.isEmpty || _isLoading) return;

    _controller.clear();
    setState(() {
      _messages.add({'role': 'user', 'content': message});
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      // TODO: Call chat repository
      // final result = await ref.read(chatRepositoryProvider).sendMessage(...)
      // Simulate for now:
      await Future.delayed(const Duration(seconds: 2));
      setState(() {
        _messages.add({'role': 'assistant', 'content': 'This is a response about $_subjectName based on your documents.'});
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  String get _subjectName => widget.subjectName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI Chat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(_subjectName, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == _messages.length) return _buildTypingIndicator();
                      return _MessageBubble(message: _messages[i]);
                    },
                  ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.psychology, size: 64, color: AppColors.primaryLight),
          const SizedBox(height: 16),
          const Text('Ask anything about your documents', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Text('Based on $_subjectName material', style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          // Quick suggestion chips
          Wrap(
            spacing: 8,
            children: [
              _SuggestionChip(label: 'Summarize key concepts', onTap: () { _controller.text = 'Summarize the key concepts'; _sendMessage(); }),
              _SuggestionChip(label: 'What are the main topics?', onTap: () { _controller.text = 'What are the main topics?'; _sendMessage(); }),
              _SuggestionChip(label: 'Explain the most important formula', onTap: () { _controller.text = 'Explain the most important formula'; _sendMessage(); }),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
            child: const Row(
              children: [
                SizedBox(width: 4),
                _TypingDot(delay: Duration.zero),
                SizedBox(width: 4),
                _TypingDot(delay: Duration(milliseconds: 200)),
                SizedBox(width: 4),
                _TypingDot(delay: Duration(milliseconds: 400)),
                SizedBox(width: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Ask about your documents...',
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: (_) => _sendMessage(),
              maxLines: null,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, String> message;
  const _MessageBubble({required this.message});

  bool get isUser => message['role'] == 'user';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
              child: const Icon(Icons.psychology, size: 16, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: isUser ? const Radius.circular(4) : null,
                  bottomLeft: !isUser ? const Radius.circular(4) : null,
                ),
              ),
              child: isUser
                  ? Text(message['content']!, style: const TextStyle(color: Colors.white))
                  : MarkdownBody(data: message['content']!),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      backgroundColor: AppColors.primaryLight,
      side: const BorderSide(color: AppColors.primary, width: 0.5),
    );
  }
}

class _TypingDot extends StatefulWidget {
  final Duration delay;
  const _TypingDot({required this.delay});
  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _animation = Tween(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    Future.delayed(widget.delay, () { if (mounted) _controller.forward(); });
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.textSecondary, shape: BoxShape.circle)),
    );
  }
}
```

### Update `app_router.dart` — Add New Routes

Add these inside the `ShellRoute` (or as sub-routes of subjects):

```dart
// Add to subject routes:
GoRoute(
  path: '/subjects/:id/chat',
  builder: (c, s) => ChatScreen(
    subjectId: s.pathParameters['id']!,
    subjectName: s.uri.queryParameters['name'] ?? '',
  ),
),
GoRoute(
  path: '/subjects/:id/generate',
  builder: (c, s) => GenerateOptionsScreen(subjectId: s.pathParameters['id']!),
),
GoRoute(
  path: '/subjects/:id/result',
  builder: (c, s) => AiResultScreen(subjectId: s.pathParameters['id']!),
),
GoRoute(
  path: '/subjects/:id/upload',
  builder: (c, s) => UploadDocumentScreen(subjectId: s.pathParameters['id']!),
),
```

---

## Part 7: Subject Detail Screen (Connects Everything)

The `SubjectDetailScreen` is the hub. It shows tabs: Documents | AI Notes | AI Chat.

```dart
// lib/features/subjects/screens/subject_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';

class SubjectDetailScreen extends StatefulWidget {
  final String subjectId;
  const SubjectDetailScreen({super.key, required this.subjectId});

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Structures'),   // Load from provider
        actions: [IconButton(icon: const Icon(Icons.settings), onPressed: () {})],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Documents'),
            Tab(text: 'AI Notes'),
            Tab(text: 'AI Chat'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DocumentsTab(subjectId: widget.subjectId),
          _AINotesTab(subjectId: widget.subjectId),
          _AIChatTab(subjectId: widget.subjectId),
        ],
      ),
    );
  }
}

// Documents tab shows file list + upload button
class _DocumentsTab extends StatelessWidget {
  final String subjectId;
  const _DocumentsTab({required this.subjectId});

  @override
  Widget build(BuildContext context) {
    // TODO: Load documents from provider
    // Show status badge: Ready (green), Processing (orange), Failed (red)
    return Scaffold(
      body: const Center(child: Text('Documents list here')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/subjects/$subjectId/upload'),
        label: const Text('Upload File'),
        icon: const Icon(Icons.upload_file),
        backgroundColor: AppColors.primary,
      ),
    );
  }
}

// AI Notes tab shows generation buttons + cached results
class _AINotesTab extends StatelessWidget {
  final String subjectId;
  const _AINotesTab({required this.subjectId});

  @override
  Widget build(BuildContext context) {
    // Generation option grid
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(16),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        _GenerateCard(label: 'Summary', icon: Icons.summarize, type: 'summary', subjectId: subjectId),
        _GenerateCard(label: 'Key Points', icon: Icons.star, type: 'key_points', subjectId: subjectId),
        _GenerateCard(label: 'MCQs', icon: Icons.quiz, type: 'mcq', subjectId: subjectId),
        _GenerateCard(label: 'Flashcards', icon: Icons.style, type: 'flashcards', subjectId: subjectId),
        _GenerateCard(label: '5-Mark Q&A', icon: Icons.assignment, type: 'five_mark_qa', subjectId: subjectId),
        _GenerateCard(label: '10-Mark Q&A', icon: Icons.assignment_turned_in, type: 'ten_mark_qa', subjectId: subjectId),
        _GenerateCard(label: 'Revision Sheet', icon: Icons.description, type: 'revision_sheet', subjectId: subjectId),
        _GenerateCard(label: 'Mind Map', icon: Icons.account_tree, type: 'mind_map', subjectId: subjectId),
      ],
    );
  }
}

class _GenerateCard extends StatelessWidget {
  final String label, type, subjectId;
  final IconData icon;
  const _GenerateCard({required this.label, required this.icon, required this.type, required this.subjectId});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/subjects/$subjectId/result?type=$type'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8)],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// AI Chat tab — embed the chat widget
class _AIChatTab extends StatelessWidget {
  final String subjectId;
  const _AIChatTab({required this.subjectId});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton.icon(
        onPressed: () => context.push('/subjects/$subjectId/chat?name=Data Structures'),
        icon: const Icon(Icons.chat),
        label: const Text('Open AI Chat'),
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
      ),
    );
  }
}
```

---

## Part 8: Phase 2 Checklist

### Supabase

- [ ] `vector` extension enabled
- [ ] `document_chunks` table created with HNSW index
- [ ] `ai_generations` table created
- [ ] `chat_sessions` + `chat_messages` tables created
- [ ] `api_key_usage` table created with key aliases pre-inserted
- [ ] `subject_context` table created
- [ ] `match_chunks` RPC function created and tested
- [ ] `increment_key_usage` RPC function created
- [ ] `increment_subject_doc_count` RPC function created
- [ ] All RLS policies applied

### FastAPI Backend

- [ ] `google-generativeai`, `pymupdf`, `python-docx`, `python-pptx`, `tiktoken` installed
- [ ] All GEMINI*KEY*\* added to `.env`
- [ ] `GeminiKeyRotator` tested — rotates on 429
- [ ] `DocumentProcessor` tested on a PDF, DOCX, and PPTX
- [ ] `chunk_text()` tested — chunks are ~600 tokens with overlap
- [ ] `process_document()` pipeline tested end-to-end
- [ ] `match_chunks()` RPC tested — returns relevant chunks
- [ ] `POST /documents/upload/{subject_id}` works + background processing starts
- [ ] `POST /ai/generate` returns valid JSON for all 8 generation types
- [ ] `POST /chat/message` returns response using RAG context
- [ ] `GET /chat/sessions/{subject_id}` works
- [ ] `GET /chat/messages/{session_id}` works

### Flutter App

- [ ] `DocumentRepository` wired to upload endpoint
- [ ] Document status polling works (uploaded → processing → ready)
- [ ] `SubjectDetailScreen` tabs: Documents, AI Notes, AI Chat
- [ ] Upload screen functional (file picker + upload + progress)
- [ ] AI generation grid shows all 8 options
- [ ] `AiResultScreen` renders JSON output correctly per type
- [ ] `ChatScreen` sends messages + displays streaming responses
- [ ] Error states handled (no docs ready, API error, quota hit)

---

## Part 9: Token Budget Reference

| Action                                | Approx Tokens                | Free RPD Impact           |
| ------------------------------------- | ---------------------------- | ------------------------- |
| Embed 1 chunk (600 tokens)            | ~600 input                   | Minimal (embedding model) |
| Summary generation (8 chunks context) | ~6,000 input + ~1,500 output | 1 of 250 Flash RPD        |
| MCQ generation (10 questions)         | ~5,000 input + ~2,000 output | 1 of 250 RPD              |
| Chat message                          | ~4,000 input + ~500 output   | 1 of 250 RPD              |
| Full doc processing (20 chunks)       | ~12,000 embedding tokens     | Embedding API (free)      |

**With 250 RPD on Flash (1 key):** ~200 usable requests/day after overhead.
**With 3 keys × 250 RPD:** ~600-700 AI interactions/day across all users.

---

## Part 10: What's Deferred to Phase 3

- Flashcard flip UI (Practice module)
- MCQ timed practice UI
- Revision planner (weekly schedule generation)
- Subscription / Stripe payments
- Web platform
- Push notifications for processing complete
- Admin dashboard for API usage monitoring
