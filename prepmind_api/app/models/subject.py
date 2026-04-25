from pydantic import BaseModel, Field
from uuid import UUID
from datetime import datetime
from typing import Optional


class SubjectCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    exam_type: Optional[str] = None
    semester: Optional[str] = None
    color: str = "#6366F1"


class SubjectUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    exam_type: Optional[str] = None
    semester: Optional[str] = None
    color: Optional[str] = None


class SubjectResponse(BaseModel):
    id: UUID
    user_id: UUID
    name: str
    exam_type: Optional[str]
    semester: Optional[str]
    color: str
    document_count: int
    ai_note_count: int
    created_at: datetime
    updated_at: datetime
