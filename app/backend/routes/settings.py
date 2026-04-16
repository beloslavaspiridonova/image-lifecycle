"""Settings / user management routes."""
from datetime import datetime, timezone
from typing import List

from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy import text

from auth import require_role, hash_password
from database import engine, users_table, roles_table, write_audit
from models import UserOut, UserCreate, UserRoleUpdate

router = APIRouter(prefix="/api/settings", tags=["settings"])


class UserWithRole(UserOut):
    role: str = "viewer"


@router.get("/users")
async def list_users(user=Depends(require_role("service_admin"))):
    with engine.connect() as conn:
        rows = conn.execute(
            text(
                """
                SELECT u.id, u.email, u.name, u.created_at, u.is_active,
                       COALESCE(r.role, 'viewer') AS role
                FROM users u
                LEFT JOIN roles r ON r.user_id = u.id
                ORDER BY u.id
                """
            )
        ).mappings().fetchall()
    return [dict(r) for r in rows]


@router.post("/users", response_model=UserOut)
async def create_user(body: UserCreate, user=Depends(require_role("owner"))):
    now = datetime.now(timezone.utc)

    with engine.connect() as conn:
        existing = conn.execute(
            text("SELECT id FROM users WHERE email = :email"),
            {"email": body.email},
        ).mappings().fetchone()
        if existing:
            raise HTTPException(status_code=400, detail="Email already registered")

        pw_hash = hash_password(body.password)
        result = conn.execute(
            users_table.insert().values(
                email=body.email,
                name=body.name,
                password_hash=pw_hash,
                created_at=now,
                is_active=True,
            )
        )
        new_id = result.inserted_primary_key[0]

        conn.execute(
            roles_table.insert().values(
                user_id=new_id,
                role=body.role,
                created_at=now,
            )
        )
        write_audit(
            conn,
            user_id=user["id"],
            action="user_created",
            entity_type="user",
            entity_id=new_id,
            detail=f"email={body.email} role={body.role}",
        )
        conn.commit()

        row = conn.execute(
            text("SELECT * FROM users WHERE id = :id"),
            {"id": new_id},
        ).mappings().fetchone()

    return dict(row)


@router.put("/users/{target_id}/role")
async def update_user_role(
    target_id: int,
    body: UserRoleUpdate,
    user=Depends(require_role("owner")),
):
    from auth import ROLE_LEVELS
    if body.role not in ROLE_LEVELS:
        raise HTTPException(status_code=400, detail=f"Unknown role: {body.role}")

    with engine.connect() as conn:
        target = conn.execute(
            text("SELECT id FROM users WHERE id = :id"),
            {"id": target_id},
        ).mappings().fetchone()
        if not target:
            raise HTTPException(status_code=404, detail="User not found")

        existing_role = conn.execute(
            text("SELECT id FROM roles WHERE user_id = :uid"),
            {"uid": target_id},
        ).mappings().fetchone()

        if existing_role:
            conn.execute(
                roles_table.update()
                .where(roles_table.c.user_id == target_id)
                .values(role=body.role)
            )
        else:
            conn.execute(
                roles_table.insert().values(
                    user_id=target_id,
                    role=body.role,
                    created_at=datetime.now(timezone.utc),
                )
            )

        write_audit(
            conn,
            user_id=user["id"],
            action="user_role_updated",
            entity_type="user",
            entity_id=target_id,
            detail=f"role={body.role}",
        )
        conn.commit()

    return {"id": target_id, "role": body.role}


@router.delete("/users/{target_id}")
async def delete_user(target_id: int, user=Depends(require_role("owner"))):
    with engine.connect() as conn:
        target = conn.execute(
            text("SELECT id FROM users WHERE id = :id"),
            {"id": target_id},
        ).mappings().fetchone()
        if not target:
            raise HTTPException(status_code=404, detail="User not found")

        if target_id == user["id"]:
            raise HTTPException(status_code=400, detail="Cannot deactivate yourself")

        conn.execute(
            users_table.update()
            .where(users_table.c.id == target_id)
            .values(is_active=False)
        )
        write_audit(
            conn,
            user_id=user["id"],
            action="user_deactivated",
            entity_type="user",
            entity_id=target_id,
        )
        conn.commit()

    return {"id": target_id, "is_active": False}
