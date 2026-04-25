from pydantic import BaseModel
from typing import Optional


class GenerateRequest(BaseModel):
    subject_id: str
    generation_type: str
    count: int = 10
    query: Optional[str] = None
    force_regenerate: bool = False
