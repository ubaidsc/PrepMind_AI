import os
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, status, BackgroundTasks
from app.dependencies import get_current_user
from app.core.supabase import get_supabase_client
from app.services.document_pipeline import process_document
from app.models.common import APIResponse

router = APIRouter()

ALLOWED_TYPES = {
    "application/pdf": "pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation": "pptx",
}
MAX_FILE_SIZE = int(os.getenv("MAX_FILE_SIZE_MB", "20")) * 1024 * 1024
FREE_PLAN_LIMIT = int(os.getenv("FREE_PLAN_FILE_LIMIT", "5"))


@router.post(
    "/upload/{subject_id}",
    response_model=APIResponse,
    status_code=status.HTTP_201_CREATED,
)
async def upload_document(
    subject_id: str,
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
):
    """
    Upload a document to a subject.
    Validates type/size, stores in Supabase Storage, creates DB record,
    and kicks off background processing (chunking + embedding).
    """
    supabase = get_supabase_client()
    user_id = current_user["id"]

    # Validate file type
    file_type = ALLOWED_TYPES.get(file.content_type)
    if not file_type:
        raise HTTPException(
            status_code=400,
            detail="Only PDF, DOCX, and PPTX files are allowed",
        )

    # Read file bytes
    file_bytes = await file.read()
    if not file_bytes:
        raise HTTPException(status_code=400, detail="Empty file")
    if len(file_bytes) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=400,
            detail=f"File too large. Maximum size is {MAX_FILE_SIZE // (1024 * 1024)}MB",
        )

    # Check plan limits
    existing = (
        supabase.table("documents")
        .select("id")
        .eq("subject_id", subject_id)
        .eq("user_id", user_id)
        .neq("status", "failed")
        .execute()
    )
    if len(existing.data) >= FREE_PLAN_LIMIT:
        raise HTTPException(
            status_code=403,
            detail=f"Free plan allows {FREE_PLAN_LIMIT} files per subject",
        )

    # Verify subject ownership
    subject = (
        supabase.table("subjects")
        .select("id, name")
        .eq("id", subject_id)
        .eq("user_id", user_id)
        .execute()
    )
    if not subject.data:
        raise HTTPException(status_code=404, detail="Subject not found")

    # Store file in Supabase Storage
    safe_filename = os.path.basename(file.filename or "document")
    storage_path = f"{user_id}/{subject_id}/{safe_filename}"
    try:
        supabase.storage.from_("documents").upload(
            path=storage_path,
            file=file_bytes,
            file_options={"content-type": file.content_type, "upsert": "true"},
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Storage upload failed: {str(e)}")

    # Create document record with status 'uploaded'
    doc_result = supabase.table("documents").insert({
        "subject_id": subject_id,
        "user_id": user_id,
        "name": safe_filename,
        "file_type": file_type,
        "file_size_bytes": len(file_bytes),
        "storage_path": storage_path,
        "status": "uploaded",
    }).execute()

    document = doc_result.data[0]

    # Kick off background processing (chunking + embedding)
    background_tasks.add_task(
        process_document,
        document_id=document["id"],
        subject_id=subject_id,
        user_id=user_id,
        file_bytes=file_bytes,
        file_type=file_type,
        file_name=safe_filename,
    )

    return APIResponse(
        data=document,
        message="Document uploaded. Processing started in background.",
    )


@router.get("/{subject_id}", response_model=APIResponse)
async def list_documents(
    subject_id: str,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    result = (
        supabase.table("documents")
        .select("*")
        .eq("subject_id", subject_id)
        .eq("user_id", current_user["id"])
        .order("created_at", desc=True)
        .execute()
    )
    return APIResponse(data=result.data)


@router.delete("/{document_id}", response_model=APIResponse)
async def delete_document(
    document_id: str,
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase_client()
    # Fetch doc storage path before deletion
    doc = (
        supabase.table("documents")
        .select("storage_path")
        .eq("id", document_id)
        .eq("user_id", current_user["id"])
        .execute()
    )
    if doc.data:
        try:
            supabase.storage.from_("documents").remove([doc.data[0]["storage_path"]])
        except Exception:
            pass  # Storage deletion is best-effort
    supabase.table("documents").delete().eq("id", document_id).eq(
        "user_id", current_user["id"]
    ).execute()
    return APIResponse(message="Document deleted")
