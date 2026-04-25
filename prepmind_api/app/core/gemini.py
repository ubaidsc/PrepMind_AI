import asyncio
from google import genai
from google.genai import types
from app.core.supabase import get_supabase_client
from app.config import settings


class GeminiKeyRotator:
    """
    Manages a pool of Gemini API keys.
    Rotates automatically on 429 errors.
    Tracks usage in Supabase.
    """

    def __init__(self):
        self._keys: dict[str, str] = {}
        self._current_index: int = 0
        self._load_keys()

    def _load_keys(self):
        # Load from pydantic settings (which reads .env file)
        candidates = [
            ("key_1", settings.gemini_key_1),
            ("key_2", settings.gemini_key_2),
            ("key_3", settings.gemini_key_3),
        ]
        for alias, key in candidates:
            if key:
                self._keys[alias] = key
        if not self._keys:
            raise ValueError("No Gemini API keys found. Set GEMINI_KEY_1 in .env")

    @property
    def _key_list(self) -> list[tuple[str, str]]:
        return list(self._keys.items())

    def _get_current(self) -> tuple[str, str]:
        return self._key_list[self._current_index % len(self._key_list)]

    def _rotate(self):
        self._current_index = (self._current_index + 1) % len(self._key_list)

    def _make_client(self, api_key: str) -> genai.Client:
        return genai.Client(api_key=api_key)

    async def _log_usage(self, key_alias: str, tokens: int):
        """Update usage counter in Supabase asynchronously."""
        try:
            supabase = get_supabase_client()
            supabase.rpc("increment_key_usage", {
                "p_key_alias": key_alias,
                "p_tokens": tokens,
            }).execute()
        except Exception:
            pass  # Non-critical

    async def generate_content(
        self,
        model_name: str,
        contents: list,
        generation_config: dict = None,
        max_retries: int = None,
    ):
        """
        Generate content with automatic key rotation on 429.
        contents format: [{"role": "user", "parts": ["text"]}]
        """
        if max_retries is None:
            max_retries = len(self._key_list)

        # Convert our dict format to google.genai Content objects
        genai_contents = []
        for msg in contents:
            role = msg.get("role", "user")
            parts = msg.get("parts", [])
            genai_contents.append(
                types.Content(
                    role=role,
                    parts=[types.Part(text=p) if isinstance(p, str) else p for p in parts],
                )
            )

        config = types.GenerateContentConfig(**(generation_config or {})) if generation_config else None

        last_error = None
        for _ in range(max_retries):
            key_alias, api_key = self._get_current()
            try:
                client = self._make_client(api_key)
                response = client.models.generate_content(
                    model=model_name,
                    contents=genai_contents,
                    config=config,
                )
                tokens = 0
                try:
                    tokens = (response.usage_metadata.total_token_count or 0)
                except Exception:
                    pass
                try:
                    asyncio.create_task(self._log_usage(key_alias, tokens))
                except RuntimeError:
                    pass
                return response
            except Exception as e:
                last_error = e
                err_str = str(e).lower()
                if "429" in err_str or "quota" in err_str or "resource_exhausted" in err_str:
                    self._rotate()
                    continue
                raise e

        raise last_error

    async def get_embedding(self, text: str) -> list[float]:
        """Generate document embedding using gemini-embedding-001 (768 dims)."""
        last_error = None
        for _ in range(len(self._key_list)):
            key_alias, api_key = self._get_current()
            try:
                client = self._make_client(api_key)
                result = client.models.embed_content(
                    model="models/gemini-embedding-001",
                    contents=text,
                    config=types.EmbedContentConfig(
                        task_type="retrieval_document",
                        output_dimensionality=768,
                    ),
                )
                try:
                    asyncio.create_task(self._log_usage(key_alias, len(text) // 4))
                except RuntimeError:
                    pass
                return result.embeddings[0].values
            except Exception as e:
                last_error = e
                err_str = str(e).lower()
                if "429" in err_str or "quota" in err_str or "resource_exhausted" in err_str:
                    self._rotate()
                    continue
                raise e
        raise last_error

    async def get_query_embedding(self, text: str) -> list[float]:
        """Generate query embedding (retrieval_query task type gives better retrieval)."""
        last_error = None
        for _ in range(len(self._key_list)):
            key_alias, api_key = self._get_current()
            try:
                client = self._make_client(api_key)
                result = client.models.embed_content(
                    model="models/gemini-embedding-001",
                    contents=text,
                    config=types.EmbedContentConfig(
                        task_type="retrieval_query",
                        output_dimensionality=768,
                    ),
                )
                return result.embeddings[0].values
            except Exception as e:
                last_error = e
                err_str = str(e).lower()
                if "429" in err_str or "quota" in err_str or "resource_exhausted" in err_str:
                    self._rotate()
                    continue
                raise e
        raise last_error


# Singleton instance
_rotator: GeminiKeyRotator | None = None


def get_gemini() -> GeminiKeyRotator:
    global _rotator
    if _rotator is None:
        _rotator = GeminiKeyRotator()
    return _rotator

