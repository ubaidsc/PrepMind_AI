import os
import asyncio
import google.generativeai as genai
from app.core.supabase import get_supabase_client


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
        i = 1
        while True:
            key = os.getenv(f"GEMINI_KEY_{i}")
            if not key:
                break
            self._keys[f"key_{i}"] = key
            i += 1
        if not self._keys:
            raise ValueError("No GEMINI_KEY_* environment variables found. Add GEMINI_KEY_1 to .env")

    @property
    def _key_list(self) -> list[tuple[str, str]]:
        return list(self._keys.items())

    def _get_current(self) -> tuple[str, str]:
        return self._key_list[self._current_index % len(self._key_list)]

    def _rotate(self):
        self._current_index = (self._current_index + 1) % len(self._key_list)

    async def _log_usage(self, key_alias: str, tokens: int):
        """Update usage counter in Supabase asynchronously."""
        try:
            supabase = get_supabase_client()
            supabase.rpc("increment_key_usage", {
                "p_key_alias": key_alias,
                "p_tokens": tokens,
            }).execute()
        except Exception:
            pass  # Non-critical — don't fail requests over tracking errors

    async def generate_content(
        self,
        model_name: str,
        contents: list,
        generation_config: dict = None,
        max_retries: int = None,
    ):
        """
        Generate content with automatic key rotation on 429.
        Retries across all available keys before raising.
        """
        if max_retries is None:
            max_retries = len(self._key_list)

        last_error = None
        for _ in range(max_retries):
            key_alias, api_key = self._get_current()
            try:
                genai.configure(api_key=api_key)
                model = genai.GenerativeModel(model_name)
                config = genai.types.GenerationConfig(**(generation_config or {}))
                response = model.generate_content(contents, generation_config=config)
                tokens = 0
                try:
                    tokens = response.usage_metadata.total_token_count or 0
                except Exception:
                    pass
                # Fire-and-forget usage tracking
                try:
                    asyncio.create_task(self._log_usage(key_alias, tokens))
                except RuntimeError:
                    pass  # No running event loop in some contexts
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
        """Generate document embedding using text-embedding-004 (768 dims)."""
        last_error = None
        for _ in range(len(self._key_list)):
            key_alias, api_key = self._get_current()
            try:
                genai.configure(api_key=api_key)
                result = genai.embed_content(
                    model="models/text-embedding-004",
                    content=text,
                    task_type="retrieval_document",
                    output_dimensionality=768,
                )
                try:
                    asyncio.create_task(self._log_usage(key_alias, len(text) // 4))
                except RuntimeError:
                    pass
                return result["embedding"]
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
                genai.configure(api_key=api_key)
                result = genai.embed_content(
                    model="models/text-embedding-004",
                    content=text,
                    task_type="retrieval_query",
                    output_dimensionality=768,
                )
                return result["embedding"]
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
