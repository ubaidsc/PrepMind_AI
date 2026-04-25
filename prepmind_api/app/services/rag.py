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
    1. Embed the query using retrieval_query task type
    2. Vector similarity search in Supabase via match_chunks RPC
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
        return "No relevant context found in uploaded documents."
    parts = []
    for i, chunk in enumerate(chunks):
        doc_name = chunk.get("metadata", {}).get("document_name", "Unknown Document")
        parts.append(f"[Source {i + 1} — {doc_name}]\n{chunk['content']}")
    return "\n\n---\n\n".join(parts)
