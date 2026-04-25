from functools import lru_cache
from supabase import create_client, Client
from app.config import settings


@lru_cache(maxsize=1)
def get_supabase_client() -> Client:
    """Admin client with service role key — use only server-side."""
    return create_client(settings.supabase_url, settings.supabase_service_role_key)


@lru_cache(maxsize=1)
def get_supabase_anon_client() -> Client:
    """Anon client — respects RLS."""
    return create_client(settings.supabase_url, settings.supabase_anon_key)
