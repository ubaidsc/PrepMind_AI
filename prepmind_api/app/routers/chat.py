from fastapi import APIRouter, Depends, HTTPException
from app.dependencies import get_current_user
from app.core.supabase import get_supabase_client
from app.services.generator import chat_with_subject
from app.models.chat import ChatMessageRequest
from app.models.common import APIResponse

router = APIRouter()


@router.post("/message", response_model=APIResponse)
async def send_message(
    payload: ChatMessageRequest,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    user_id = current_user["id"]

    # Fetch subject name
    subject = (
        supabase.table("subjects")
        .select("name")
        .eq("id", payload.subject_id)
        .eq("user_id", user_id)
        .execute()
    )
    if not subject.data:
        raise HTTPException(status_code=404, detail="Subject not found")
    subject_name = subject.data[0]["name"]

    # Check ready documents exist
    ready_docs = (
        supabase.table("documents")
        .select("id")
        .eq("subject_id", payload.subject_id)
        .eq("user_id", user_id)
        .eq("status", "ready")
        .execute()
    )
    if not ready_docs.data:
        raise HTTPException(
            status_code=422,
            detail="No processed documents found. Upload documents first.",
        )

    # Get or create session
    session_id = payload.session_id
    if not session_id:
        session_result = supabase.table("chat_sessions").insert({
            "subject_id": payload.subject_id,
            "user_id": user_id,
            "title": f"Chat — {subject_name}",
        }).execute()
        session_id = session_result.data[0]["id"]
    else:
        # Validate session ownership
        session = (
            supabase.table("chat_sessions")
            .select("id")
            .eq("id", session_id)
            .eq("user_id", user_id)
            .execute()
        )
        if not session.data:
            raise HTTPException(status_code=404, detail="Session not found")

    # Load recent chat history for this session
    history_result = (
        supabase.table("chat_messages")
        .select("role, content")
        .eq("session_id", session_id)
        .order("created_at", desc=False)
        .limit(12)
        .execute()
    )
    chat_history = history_result.data or []

    result = await chat_with_subject(
        message=payload.message,
        subject_id=payload.subject_id,
        subject_name=subject_name,
        user_id=user_id,
        session_id=session_id,
        chat_history=chat_history,
    )

    return APIResponse(data=result)


@router.get("/sessions/{subject_id}", response_model=APIResponse)
async def get_sessions(
    subject_id: str,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    result = (
        supabase.table("chat_sessions")
        .select("*")
        .eq("subject_id", subject_id)
        .eq("user_id", current_user["id"])
        .order("updated_at", desc=True)
        .execute()
    )
    return APIResponse(data=result.data)


@router.get("/messages/{session_id}", response_model=APIResponse)
async def get_messages(
    session_id: str,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    # Validate session ownership before returning messages
    session = (
        supabase.table("chat_sessions")
        .select("id")
        .eq("id", session_id)
        .eq("user_id", current_user["id"])
        .execute()
    )
    if not session.data:
        raise HTTPException(status_code=404, detail="Session not found")

    result = (
        supabase.table("chat_messages")
        .select("id, role, content, created_at, sources_used:retrieved_chunk_ids")
        .eq("session_id", session_id)
        .order("created_at", desc=False)
        .execute()
    )
    return APIResponse(data=result.data)


@router.delete("/sessions/{session_id}", response_model=APIResponse)
async def delete_session(
    session_id: str,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    supabase.table("chat_sessions").delete().eq("id", session_id).eq(
        "user_id", current_user["id"]
    ).execute()
    return APIResponse(message="Session deleted")
