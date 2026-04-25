from pydantic import BaseModel
from typing import Optional


class ChatMessageRequest(BaseModel):
    subject_id: str
    message: str
    session_id: Optional[str] = None  # None = start new session
