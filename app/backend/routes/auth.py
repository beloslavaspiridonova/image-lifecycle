"""Auth routes: login, logout, me."""
from fastapi import APIRouter, HTTPException, Request, Response

from auth import (
    verify_password, create_session, get_current_user, get_capabilities, COOKIE_NAME
)
from database import engine, users_table, roles_table
from models import LoginRequest, MeResponse, UserOut
from sqlalchemy import text

router = APIRouter(prefix="/api/auth", tags=["auth"])


@router.post("/login")
async def login(body: LoginRequest, response: Response):
    with engine.connect() as conn:
        row = conn.execute(
            text("SELECT id, email, name, password_hash, is_active FROM users WHERE email = :email"),
            {"email": body.email},
        ).mappings().fetchone()

    if not row:
        raise HTTPException(status_code=401, detail="Invalid credentials")

    if not row["is_active"]:
        raise HTTPException(status_code=403, detail="Account is inactive")

    if not row["password_hash"] or not verify_password(body.password, row["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    token = create_session(row["id"])
    response.set_cookie(
        key=COOKIE_NAME,
        value=token,
        httponly=True,
        samesite="lax",
        secure=False,  # Set True behind HTTPS in production
        max_age=86400,
    )

    # Fetch roles
    with engine.connect() as conn:
        roles_rows = conn.execute(
            text("SELECT role FROM roles WHERE user_id = :uid"),
            {"uid": row["id"]},
        ).mappings().fetchall()
    roles = [r["role"] for r in roles_rows]

    return {
        "ok": True,
        "user": {
            "id": row["id"],
            "email": row["email"],
            "name": row["name"],
        },
        "roles": roles,
    }


@router.post("/logout")
async def logout(response: Response):
    response.delete_cookie(key=COOKIE_NAME)
    return {"ok": True}


@router.get("/me", response_model=MeResponse)
async def me(request: Request):
    user = get_current_user(request)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    roles = user.get("roles", [])
    caps = get_capabilities(roles)
    is_owner = "owner" in roles

    return MeResponse(
        user=UserOut(
            id=user["id"],
            email=user["email"],
            name=user.get("name"),
            is_active=user.get("is_active", True),
        ),
        roles=roles,
        is_owner=is_owner,
        capabilities=caps,
    )
