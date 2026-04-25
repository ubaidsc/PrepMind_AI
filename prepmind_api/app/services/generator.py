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
    count: int = 10,
    query: str = None,
    use_cache: bool = True,
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

    # Step 1: Check cache
    if use_cache:
        cached = (
            supabase.table("ai_generations")
            .select("content")
            .eq("subject_id", subject_id)
            .eq("user_id", user_id)
            .eq("generation_type", generation_type)
            .order("created_at", desc=True)
            .limit(1)
            .execute()
        )
        if cached.data:
            return cached.data[0]["content"]

    # Step 2: RAG — retrieve representative content
    rag_query = query or f"{subject_name} key concepts topics overview exam"
    chunks = await retrieve_relevant_chunks(
        query=rag_query,
        subject_id=subject_id,
        user_id=user_id,
        top_k=8,
        similarity_threshold=0.3,
    )
    context = build_context_block(chunks)
    chunk_doc_ids = list({c["document_id"] for c in chunks if c.get("document_id")})

    # Step 3: Build prompt
    prompt_config = GENERATION_PROMPTS[generation_type]
    user_prompt = prompt_config["user_template"].format(
        subject_name=subject_name,
        context=context,
        count=count,
    )

    # Step 4: Call Gemini
    contents = [
        {"role": "user", "parts": [prompt_config["system"]]},
        {"role": "model", "parts": ["Understood. I will respond with valid JSON only."]},
        {"role": "user", "parts": [user_prompt]},
    ]
    response = await gemini.generate_content(
        model_name="gemini-2.5-flash",
        contents=contents,
        generation_config={
            "temperature": 0.4,
            "max_output_tokens": 8192,
        },
    )

    # Step 5: Parse JSON response
    raw_text = response.text.strip()
    raw_text = re.sub(r'^```(?:json)?\s*', '', raw_text)
    raw_text = re.sub(r'\s*```$', '', raw_text)

    try:
        result = json.loads(raw_text)
    except json.JSONDecodeError:
        # Attempt to extract JSON from wrapped response
        json_match = re.search(r'\{.*\}', raw_text, re.DOTALL)
        if json_match:
            result = json.loads(json_match.group())
        else:
            result = {"type": generation_type, "raw": raw_text, "note": "Could not parse structured JSON"}

    # Step 6: Cache result
    try:
        usage = response.usage_metadata
        prompt_tokens = getattr(usage, "prompt_token_count", 0) or 0
        completion_tokens = getattr(usage, "candidates_token_count", 0) or 0
    except Exception:
        prompt_tokens = completion_tokens = 0

    supabase.table("ai_generations").insert({
        "subject_id": subject_id,
        "user_id": user_id,
        "generation_type": generation_type,
        "content": result,
        "document_ids": chunk_doc_ids,
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "model_used": "gemini-2.5-flash",
    }).execute()

    return result


async def chat_with_subject(
    message: str,
    subject_id: str,
    subject_name: str,
    user_id: str,
    session_id: str,
    chat_history: list[dict],
    max_history_messages: int = 6,
) -> dict:
    """
    Chat pipeline:
    1. RAG retrieval based on user message
    2. Build context-aware prompt with trimmed history
    3. Generate response
    4. Store message pair
    5. Return response
    """
    supabase = get_supabase_client()
    gemini = get_gemini()

    # Step 1: Retrieve relevant chunks for this message
    chunks = await retrieve_relevant_chunks(
        query=message,
        subject_id=subject_id,
        user_id=user_id,
        top_k=6,
        similarity_threshold=0.45,
    )
    context = build_context_block(chunks)
    chunk_ids = [c["id"] for c in chunks]

    # Step 2: Build conversation with trimmed history
    system_prompt = CHAT_SYSTEM_PROMPT.format(subject_name=subject_name)
    recent_history = chat_history[-(max_history_messages):]

    contents = [
        {"role": "user", "parts": [system_prompt]},
        {"role": "model", "parts": [f"Understood. I am PrepMind AI for {subject_name}. I will only answer based on the provided documents."]},
    ]

    for msg in recent_history:
        role = "user" if msg["role"] == "user" else "model"
        contents.append({"role": role, "parts": [msg["content"]]})

    # Current message with RAG context
    current_message = f"""RELEVANT CONTEXT FROM YOUR DOCUMENTS:
{context}

---

STUDENT QUESTION:
{message}"""

    contents.append({"role": "user", "parts": [current_message]})

    # Step 3: Generate
    response = await gemini.generate_content(
        model_name="gemini-2.5-flash",
        contents=contents,
        generation_config={
            "temperature": 0.3,
            "max_output_tokens": 2048,
        },
    )

    assistant_message = response.text.strip()

    try:
        usage = response.usage_metadata
        prompt_tokens = getattr(usage, "prompt_token_count", 0) or 0
        completion_tokens = getattr(usage, "candidates_token_count", 0) or 0
    except Exception:
        prompt_tokens = completion_tokens = 0

    # Step 4: Store both messages
    supabase.table("chat_messages").insert([
        {
            "session_id": session_id,
            "subject_id": subject_id,
            "user_id": user_id,
            "role": "user",
            "content": message,
            "retrieved_chunk_ids": None,
            "prompt_tokens": 0,
            "completion_tokens": 0,
        },
        {
            "session_id": session_id,
            "subject_id": subject_id,
            "user_id": user_id,
            "role": "assistant",
            "content": assistant_message,
            "retrieved_chunk_ids": chunk_ids if chunk_ids else None,
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
        },
    ]).execute()

    return {
        "message": assistant_message,
        "session_id": session_id,
        "sources_used": len(chunks),
    }
