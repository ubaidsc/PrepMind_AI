from fastapi import APIRouter, Depends, HTTPException
from app.dependencies import get_current_user
from app.core.supabase import get_supabase_client
from app.services.generator import generate_ai_content
from app.models.ai import GenerateRequest
from app.models.common import APIResponse

router = APIRouter()

VALID_TYPES = [
    "summary", "key_points", "mcq", "flashcards",
    "five_mark_qa", "ten_mark_qa", "revision_sheet", "mind_map",
]


@router.post("/generate", response_model=APIResponse)
async def generate(
    payload: GenerateRequest,
    current_user: dict = Depends(get_current_user),
):
    if payload.generation_type not in VALID_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid generation_type. Must be one of: {', '.join(VALID_TYPES)}",
        )

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

    # Check that subject has ready documents
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
            detail="No processed documents found. Upload and wait for processing to complete.",
        )

    result = await generate_ai_content(
        generation_type=payload.generation_type,
        subject_id=payload.subject_id,
        subject_name=subject_name,
        user_id=user_id,
        count=payload.count,
        query=payload.query,
        use_cache=not payload.force_regenerate,
    )

    return APIResponse(data=result)


@router.get("/history/{subject_id}", response_model=APIResponse)
async def get_generation_history(
    subject_id: str,
    generation_type: str | None = None,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    query = (
        supabase.table("ai_generations")
        .select("id, generation_type, model_used, prompt_tokens, completion_tokens, created_at")
        .eq("subject_id", subject_id)
        .eq("user_id", current_user["id"])
        .order("created_at", desc=True)
    )
    if generation_type:
        query = query.eq("generation_type", generation_type)
    result = query.limit(20).execute()
    return APIResponse(data=result.data)


@router.get("/result/{generation_id}", response_model=APIResponse)
async def get_generation_result(
    generation_id: str,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    result = (
        supabase.table("ai_generations")
        .select("*")
        .eq("id", generation_id)
        .eq("user_id", current_user["id"])
        .execute()
    )
    if not result.data:
        raise HTTPException(status_code=404, detail="Generation not found")
    return APIResponse(data=result.data[0])
