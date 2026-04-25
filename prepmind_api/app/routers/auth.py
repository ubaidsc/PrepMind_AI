from fastapi import APIRouter, HTTPException, status
from app.core.supabase import get_supabase_anon_client
from app.models.auth import SignUpRequest, SignInRequest
from app.models.common import APIResponse

router = APIRouter()


@router.post("/signup", response_model=APIResponse, status_code=status.HTTP_201_CREATED)
async def sign_up(payload: SignUpRequest):
    """
    Registers a new user. Supabase sends a confirmation email.
    Profile is auto-created via DB trigger.
    """
    supabase = get_supabase_anon_client()
    try:
        result = supabase.auth.sign_up({
            "email": payload.email,
            "password": payload.password,
            "options": {"data": {"full_name": payload.full_name}},
        })
        return APIResponse(
            data={"user_id": result.user.id if result.user else None},
            message="Confirmation email sent. Please verify your email.",
        )
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.post("/signin", response_model=APIResponse)
async def sign_in(payload: SignInRequest):
    supabase = get_supabase_anon_client()
    try:
        result = supabase.auth.sign_in_with_password({
            "email": payload.email,
            "password": payload.password,
        })
        return APIResponse(data={
            "access_token": result.session.access_token,
            "refresh_token": result.session.refresh_token,
            "user": {"id": result.user.id, "email": result.user.email},
        })
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(e))


@router.post("/signout", response_model=APIResponse)
async def sign_out():
    """Client should discard tokens. Supabase JWT is stateless."""
    return APIResponse(message="Signed out successfully")
