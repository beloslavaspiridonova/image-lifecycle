"""Publish request routes."""
from datetime import datetime, timezone
from typing import List

from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy import text

from auth import require_auth, require_role
from database import engine, publish_requests_table, write_audit
from models import PublishRequestOut, PublishRequestCreate, PublishActionRequest

router = APIRouter(prefix="/api/publish-requests", tags=["publish"])


@router.get("", response_model=List[PublishRequestOut])
async def list_publish_requests(user=Depends(require_auth)):
    with engine.connect() as conn:
        rows = conn.execute(
            text("SELECT * FROM publish_requests ORDER BY id DESC")
        ).mappings().fetchall()
    return [dict(r) for r in rows]


@router.post("", response_model=PublishRequestOut)
async def create_publish_request(
    body: PublishRequestCreate,
    user=Depends(require_role("maintainer")),
):
    now = datetime.now(timezone.utc)

    with engine.connect() as conn:
        build = conn.execute(
            text("SELECT id FROM builds WHERE id = :id"),
            {"id": body.build_id},
        ).mappings().fetchone()
        if not build:
            raise HTTPException(status_code=404, detail="Build not found")

        result = conn.execute(
            publish_requests_table.insert().values(
                build_id=body.build_id,
                requested_by=user["id"],
                status="pending",
                notes=body.notes,
                created_at=now,
            )
        )
        pr_id = result.inserted_primary_key[0]
        write_audit(
            conn,
            user_id=user["id"],
            action="publish_request_created",
            entity_type="publish_request",
            entity_id=pr_id,
            detail=f"build_id={body.build_id}",
        )
        conn.commit()

        row = conn.execute(
            text("SELECT * FROM publish_requests WHERE id = :id"),
            {"id": pr_id},
        ).mappings().fetchone()

    return dict(row)


@router.put("/{pr_id}/approve", response_model=PublishRequestOut)
async def approve_publish_request(
    pr_id: int,
    body: PublishActionRequest = PublishActionRequest(),
    user=Depends(require_role("reviewer")),
):
    now = datetime.now(timezone.utc)

    with engine.connect() as conn:
        row = conn.execute(
            text("SELECT * FROM publish_requests WHERE id = :id"),
            {"id": pr_id},
        ).mappings().fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Publish request not found")
        if row["status"] != "pending":
            raise HTTPException(status_code=400, detail="Publish request is not pending")

        conn.execute(
            publish_requests_table.update()
            .where(publish_requests_table.c.id == pr_id)
            .values(
                status="approved",
                approved_by=user["id"],
                approved_at=now,
            )
        )
        write_audit(
            conn,
            user_id=user["id"],
            action="publish_request_approved",
            entity_type="publish_request",
            entity_id=pr_id,
        )
        conn.commit()

        updated = conn.execute(
            text("SELECT * FROM publish_requests WHERE id = :id"),
            {"id": pr_id},
        ).mappings().fetchone()

    return dict(updated)


@router.put("/{pr_id}/reject", response_model=PublishRequestOut)
async def reject_publish_request(
    pr_id: int,
    body: PublishActionRequest = PublishActionRequest(),
    user=Depends(require_role("reviewer")),
):
    with engine.connect() as conn:
        row = conn.execute(
            text("SELECT * FROM publish_requests WHERE id = :id"),
            {"id": pr_id},
        ).mappings().fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Publish request not found")
        if row["status"] not in ("pending", "approved"):
            raise HTTPException(status_code=400, detail="Cannot reject in current status")

        conn.execute(
            publish_requests_table.update()
            .where(publish_requests_table.c.id == pr_id)
            .values(status="rejected")
        )
        write_audit(
            conn,
            user_id=user["id"],
            action="publish_request_rejected",
            entity_type="publish_request",
            entity_id=pr_id,
        )
        conn.commit()

        updated = conn.execute(
            text("SELECT * FROM publish_requests WHERE id = :id"),
            {"id": pr_id},
        ).mappings().fetchone()

    return dict(updated)


@router.put("/{pr_id}/confirm-mi", response_model=PublishRequestOut)
async def confirm_mi(
    pr_id: int,
    user=Depends(require_role("owner")),
):
    now = datetime.now(timezone.utc)

    # owner-only: must be exactly owner role
    from auth import ROLE_LEVELS
    user_max_level = max((ROLE_LEVELS.get(r, 0) for r in user.get("roles", [])), default=0)
    if user_max_level < ROLE_LEVELS["owner"]:
        raise HTTPException(status_code=403, detail="Only owners can confirm MI")

    with engine.connect() as conn:
        row = conn.execute(
            text("SELECT * FROM publish_requests WHERE id = :id"),
            {"id": pr_id},
        ).mappings().fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Publish request not found")
        if row["status"] != "approved":
            raise HTTPException(status_code=400, detail="Publish request must be approved first")

        conn.execute(
            publish_requests_table.update()
            .where(publish_requests_table.c.id == pr_id)
            .values(
                mi_confirmed_at=now,
                status="published",
            )
        )
        write_audit(
            conn,
            user_id=user["id"],
            action="publish_mi_confirmed",
            entity_type="publish_request",
            entity_id=pr_id,
        )
        conn.commit()

        updated = conn.execute(
            text("SELECT * FROM publish_requests WHERE id = :id"),
            {"id": pr_id},
        ).mappings().fetchone()

    return dict(updated)
