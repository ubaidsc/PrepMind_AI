from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.routers import auth, subjects, documents, ai, chat

app = FastAPI(
    title="PrepMind AI API",
    version="0.1.0",
    docs_url="/docs" if settings.app_env != "production" else None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/auth", tags=["auth"])
app.include_router(subjects.router, prefix="/subjects", tags=["subjects"])
app.include_router(documents.router, prefix="/documents", tags=["documents"])
app.include_router(ai.router, prefix="/ai", tags=["ai"])
app.include_router(chat.router, prefix="/chat", tags=["chat"])


@app.get("/health")
async def health_check():
    return {"status": "ok"}
