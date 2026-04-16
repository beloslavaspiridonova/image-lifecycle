"""Validation routes."""
import asyncio
from datetime import datetime, timezone
from typing import List

from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy import text

import orchestrator
from auth import require_auth, require_role
from database import engine, validations_table, builds_table, write_audit
from models import ValidationOut

router = APIRouter(prefix="/api/validations", tags=["validations"])


@router.get("", response_model=List[ValidationOut])
async def list_validations(user=Depends(require_auth)):
    with engine.connect() as conn:
        rows = conn.execute(
            text("SELECT * FROM validations ORDER BY id DESC")
        ).mappings().fetchall()
    return [dict(r) for r in rows]


@router.post("/{build_id}/start", response_model=ValidationOut)
async def start_validation(build_id: int, user=Depends(require_role("maintainer"))):
    now = datetime.now(timezone.utc)

    with engine.connect() as conn:
        build = conn.execute(
            text("SELECT id FROM builds WHERE id = :id"),
            {"id": build_id},
        ).mappings().fetchone()
        if not build:
            raise HTTPException(status_code=404, detail="Build not found")

        result = conn.execute(
            validations_table.insert().values(
                build_id=build_id,
                status="pending",
                started_at=now,
            )
        )
        validation_id = result.inserted_primary_key[0]
        write_audit(
            conn,
            user_id=user["id"],
            action="validation_triggered",
            entity_type="validation",
            entity_id=validation_id,
            detail=f"build_id={build_id}",
        )
        conn.commit()

        row = conn.execute(
            text("SELECT * FROM validations WHERE id = :id"),
            {"id": validation_id},
        ).mappings().fetchone()

    asyncio.create_task(orchestrator.run_validate(validation_id, build_id))

    return dict(row)


@router.get("/{validation_id}", response_model=ValidationOut)
async def get_validation(validation_id: int, user=Depends(require_auth)):
    with engine.connect() as conn:
        row = conn.execute(
            text("SELECT * FROM validations WHERE id = :id"),
            {"id": validation_id},
        ).mappings().fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Validation not found")
    return dict(row)
