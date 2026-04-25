from supabase import create_client, Client
from app.config import settings

_supabase_client: Client | None = None
_supabase_anon_client: Client | None = None


def get_supabase_client() -> Client:
    """Admin client with service role key — use only server-side."""
    global _supabase_client
    if _supabase_client is None:
        _supabase_client = create_client(settings.supabase_url, settings.supabase_service_role_key)
    return _supabase_client


def get_supabase_anon_client() -> Client:
    """Anon client — respects RLS."""
    global _supabase_anon_client
    if _supabase_anon_client is None:
        _supabase_anon_client = create_client(settings.supabase_url, settings.supabase_anon_key)
    return _supabase_anon_client
