"""Authentication and authorization for Image Lifecycle backend.

- passlib bcrypt for password hashing
- itsdangerous for signed session cookies
- Role hierarchy: owner=5, service_admin=4, reviewer=3, maintainer=2, viewer=1
- FastAPI dependency: require_role(min_role)
"""
import logging
from typing import Optional

from fastapi import Request, HTTPException, Depends
from itsdangerous import URLSafeTimedSerializer, BadSignature, SignatureExpired
from passlib.context import CryptContext
from sqlalchemy import text

import config
from database import engine, users_table, roles_table

logger = logging.getLogger("image-lifecycle.auth")

pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")
serializer = URLSafeTimedSerializer(config.SECRET_KEY)

ROLE_LEVELS = {
    "owner": 5,
    "service_admin": 4,
    "reviewer": 3,
    "maintainer": 2,
    "viewer": 1,
}

COOKIE_NAME = "lifecycle_session"


def hash_password(pw: str) -> str:
    return pwd_ctx.hash(pw)


def verify_password(pw: str, hashed: str) -> bool:
    try:
        return pwd_ctx.verify(pw, hashed)
    except Exception:
        return False


def create_session(user_id: int) -> str:
    """Return a signed cookie value encoding user_id."""
    return serializer.dumps({"uid": user_id})


def decode_session(token: str) -> Optional[int]:
    """Decode and validate a session token. Returns user_id or None."""
    try:
        data = serializer.loads(token, max_age=config.SESSION_MAX_AGE)
        return data.get("uid")
    except (BadSignature, SignatureExpired):
        return None


def get_current_user(request: Request) -> Optional[dict]:
    """Read session cookie and return user dict with roles, or None."""
    token = request.cookies.get(COOKIE_NAME)
    if not token:
        return None

    user_id = decode_session(token)
    if not user_id:
        return None

    with engine.connect() as conn:
        row = conn.execute(
            text("SELECT id, email, name, is_active FROM users WHERE id = :uid"),
            {"uid": user_id},
        ).mappings().fetchone()

        if not row or not row["is_active"]:
            return None

        roles_rows = conn.execute(
            text("SELECT role FROM roles WHERE user_id = :uid"),
            {"uid": user_id},
        ).mappings().fetchall()

        roles = [r["role"] for r in roles_rows]

    return {
        "id": row["id"],
        "email": row["email"],
        "name": row["name"],
        "roles": roles,
        "is_active": row["is_active"],
    }


def get_capabilities(roles: list) -> list:
    """Return capability list for a set of roles."""
    caps = set()
    level = max((ROLE_LEVELS.get(r, 0) for r in roles), default=0)

    if level >= 1:
        caps |= {"view_dashboard", "view_candidates", "view_builds", "view_validations",
                 "view_publish", "view_distribution"}
    if level >= 2:
        caps |= {"trigger_build", "trigger_validation", "create_publish_request", "update_candidate"}
    if level >= 3:
        caps |= {"approve_publish", "reject_publish"}
    if level >= 4:
        caps |= {"run_discover", "start_distribution", "view_audit", "manage_users"}
    if level >= 5:
        caps |= {"transfer_ownership", "confirm_mi", "manage_roles"}

    return sorted(caps)


def require_role(min_role: str):
    """FastAPI dependency factory. Raises 401/403 if user lacks the required role level."""
    min_level = ROLE_LEVELS.get(min_role, 99)

    def _dep(request: Request) -> dict:
        user = get_current_user(request)
        if not user:
            raise HTTPException(status_code=401, detail="Not authenticated")

        user_level = max((ROLE_LEVELS.get(r, 0) for r in user.get("roles", [])), default=0)
        if user_level < min_level:
            raise HTTPException(
                status_code=403,
                detail=f"Role '{min_role}' or higher is required",
            )
        return user

    return _dep


def require_auth(request: Request) -> dict:
    """FastAPI dependency - just requires any valid session."""
    user = get_current_user(request)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return user
