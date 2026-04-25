from pydantic import BaseModel, Field
from uuid import UUID
from datetime import datetime
from typing import Optional, Literal


class DocumentCreate(BaseModel):
    subject_id: UUID
    name: str = Field(..., min_length=1, max_length=255)
    file_type: Literal["pdf", "docx", "pptx"]
    file_size_bytes: int = Field(..., gt=0)
    storage_path: str


class DocumentResponse(BaseModel):
    id: UUID
    subject_id: UUID
    user_id: UUID
    name: str
    file_type: str
    file_size_bytes: int
    storage_path: str
    status: str
    page_count: Optional[int]
    error_message: Optional[str]
    created_at: datetime
    updated_at: datetime
