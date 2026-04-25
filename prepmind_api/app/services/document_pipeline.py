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
    3. Generate embeddings for each chunk (batched)
    4. Store chunks + embeddings in Supabase
    5. Update document status to 'ready'
    6. Update subject_context

    Returns: {"chunks_created": int, "total_tokens": int}
    """
    supabase = get_supabase_client()
    gemini = get_gemini()

    try:
        # Step 1: Mark document as processing
        supabase.table("documents").update(
            {"status": "processing"}
        ).eq("id", document_id).execute()

        # Step 2: Extract text
        raw_text = DocumentProcessor.extract(file_bytes, file_type)
        if not raw_text.strip():
            raise ValueError("No extractable text found in document")

        # Step 3: Chunk text
        chunks = chunk_text(raw_text, document_name=file_name)
        if not chunks:
            raise ValueError("Document could not be chunked")

        # Step 4: Generate embeddings and store chunks
        total_tokens = 0
        batch_size = 5  # Avoid rate limits

        for i in range(0, len(chunks), batch_size):
            batch = chunks[i:i + batch_size]
            embedding_tasks = [gemini.get_embedding(chunk["content"]) for chunk in batch]
            embeddings = await asyncio.gather(*embedding_tasks)

            rows = []
            for chunk, embedding in zip(batch, embeddings):
                rows.append({
                    "document_id": document_id,
                    "subject_id": subject_id,
                    "user_id": user_id,
                    "content": chunk["content"],
                    "chunk_index": chunk["chunk_index"],
                    "token_count": chunk["token_count"],
                    "embedding": embedding,
                    "metadata": {**chunk["metadata"], "document_name": file_name},
                })
                total_tokens += chunk["token_count"]

            supabase.table("document_chunks").insert(rows).execute()

        # Step 5: Mark document as ready
        supabase.table("documents").update({
            "status": "ready",
        }).eq("id", document_id).execute()

        # Step 6: Update subject_context
        existing = supabase.table("subject_context").select("*").eq(
            "subject_id", subject_id
        ).execute()

        if existing.data:
            ctx = existing.data[0]
            supabase.table("subject_context").update({
                "total_chunks": ctx["total_chunks"] + len(chunks),
                "total_tokens_indexed": ctx["total_tokens_indexed"] + total_tokens,
                "last_indexed_at": "now()",
                "updated_at": "now()",
            }).eq("subject_id", subject_id).execute()
        else:
            supabase.table("subject_context").insert({
                "subject_id": subject_id,
                "user_id": user_id,
                "total_chunks": len(chunks),
                "total_tokens_indexed": total_tokens,
                "last_indexed_at": "now()",
            }).execute()

        # Step 7: Increment document count on subject
        supabase.rpc("increment_subject_doc_count", {
            "p_subject_id": subject_id
        }).execute()

        return {"chunks_created": len(chunks), "total_tokens": total_tokens}

    except Exception as e:
        # Mark document as failed
        supabase.table("documents").update({
            "status": "failed",
            "error_message": str(e)[:500],
        }).eq("id", document_id).execute()
        raise
