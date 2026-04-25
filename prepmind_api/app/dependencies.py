import httpx
from functools import lru_cache
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, jwk, JWTError
from app.config import settings

bearer_scheme = HTTPBearer()


@lru_cache(maxsize=1)
def _fetch_jwks() -> list[dict]:
    """
    Fetches JWKS from Supabase once and caches for the process lifetime.
    Supabase ECC (P-256) keys are long-lived; restart the server if keys rotate.
    """
    response = httpx.get(settings.supabase_jwks_url, timeout=10)
    response.raise_for_status()
    return response.json()["keys"]


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> dict:
    """
    Validates the Supabase JWT (ES256) using the project's public JWKS.
    Returns the decoded user payload.
    """
    token = credentials.credentials
    try:
        keys = _fetch_jwks()
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Could not fetch auth keys",
        )

    last_error: Exception | None = None
    for key_data in keys:
        try:
            public_key = jwk.construct(key_data)
            payload = jwt.decode(
                token,
                public_key,
                algorithms=[key_data.get("alg", "ES256")],
                options={"verify_aud": False},
            )
            user_id: str = payload.get("sub")
            if not user_id:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid token",
                )
            return {"id": user_id, "email": payload.get("email")}
        except JWTError as e:
            last_error = e
            continue

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired token",
    )
