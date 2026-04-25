from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    supabase_url: str
    supabase_anon_key: str
    supabase_service_role_key: str
    app_env: str = "development"
    allowed_origins: list[str] = ["http://localhost:3000"]
    gemini_key_1: str = ""
    gemini_key_2: str = ""
    gemini_key_3: str = ""
    max_file_size_mb: int = 20
    free_plan_file_limit: int = 5

    @property
    def supabase_jwks_url(self) -> str:
        return f"{self.supabase_url}/auth/v1/.well-known/jwks.json"


settings = Settings()
