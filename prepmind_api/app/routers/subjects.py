from fastapi import APIRouter, Depends, status
from app.dependencies import get_current_user
from app.core.supabase import get_supabase_client
from app.models.subject import SubjectCreate, SubjectResponse
from app.models.common import APIResponse

router = APIRouter()


@router.get("/", response_model=APIResponse)
async def list_subjects(current_user: dict = Depends(get_current_user)):
    supabase = get_supabase_client()
    result = (
        supabase.table("subjects")
        .select("*")
        .eq("user_id", current_user["id"])
        .order("updated_at", desc=True)
        .execute()
    )
    return APIResponse(data=result.data)


@router.post("/", response_model=APIResponse, status_code=status.HTTP_201_CREATED)
async def create_subject(
    payload: SubjectCreate,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    result = (
        supabase.table("subjects")
        .insert({**payload.model_dump(), "user_id": current_user["id"]})
        .execute()
    )
    return APIResponse(data=result.data[0], message="Subject created")


@router.get("/{subject_id}", response_model=APIResponse)
async def get_subject(
    subject_id: str,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    result = (
        supabase.table("subjects")
        .select("*")
        .eq("id", subject_id)
        .eq("user_id", current_user["id"])
        .single()
        .execute()
    )
    if not result.data:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="Subject not found")
    return APIResponse(data=result.data)


@router.delete("/{subject_id}", response_model=APIResponse)
async def delete_subject(
    subject_id: str,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    supabase.table("subjects").delete().eq("id", subject_id).eq("user_id", current_user["id"]).execute()
    return APIResponse(message="Subject deleted")
