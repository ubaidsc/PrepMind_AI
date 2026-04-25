from fastapi import APIRouter, Depends, status
from app.dependencies import get_current_user
from app.core.supabase import get_supabase_client
from app.models.document import DocumentCreate
from app.models.common import APIResponse

router = APIRouter()


@router.get("/", response_model=APIResponse)
async def list_documents(
    subject_id: str | None = None,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    query = (
        supabase.table("documents")
        .select("*")
        .eq("user_id", current_user["id"])
        .order("created_at", desc=True)
    )
    if subject_id:
        query = query.eq("subject_id", subject_id)
    result = query.execute()
    return APIResponse(data=result.data)


@router.post("/", response_model=APIResponse, status_code=status.HTTP_201_CREATED)
async def create_document(
    payload: DocumentCreate,
    current_user: dict = Depends(get_current_user),
):
    """Register a document record after the client has uploaded the file to Supabase Storage."""
    supabase = get_supabase_client()
    result = (
        supabase.table("documents")
        .insert({**payload.model_dump(mode="json"), "user_id": current_user["id"]})
        .execute()
    )
    return APIResponse(data=result.data[0], message="Document registered")


@router.delete("/{document_id}", response_model=APIResponse)
async def delete_document(
    document_id: str,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    supabase.table("documents").delete().eq("id", document_id).eq("user_id", current_user["id"]).execute()
    return APIResponse(message="Document deleted")
