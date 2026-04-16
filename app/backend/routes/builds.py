"""Build routes."""
import asyncio
import os
from datetime import datetime, timezone
from typing import List

from fastapi import APIRouter, HTTPException, Depends
from fastapi.responses import StreamingResponse, PlainTextResponse
from sqlalchemy import text

import orchestrator
from auth import require_auth, require_role
from database import engine, builds_table, write_audit
from models import BuildOut, BuildCreate

router = APIRouter(prefix="/api/builds", tags=["builds"])


@router.get("", response_model=List[BuildOut])
async def list_builds(user=Depends(require_auth)):
    with engine.connect() as conn:
        rows = conn.execute(
            text("SELECT * FROM builds ORDER BY id DESC")
        ).mappings().fetchall()
    return [dict(r) for r in rows]


@router.post("", response_model=BuildOut)
async def create_build(body: BuildCreate, user=Depends(require_role("maintainer"))):
    now = datetime.now(timezone.utc)

    with engine.connect() as conn:
        # Verify candidate exists
        candidate = conn.execute(
            text("SELECT id FROM candidates WHERE id = :id"),
            {"id": body.candidate_id},
        ).mappings().fetchone()
        if not candidate:
            raise HTTPException(status_code=404, detail="Candidate not found")

        result = conn.execute(
            builds_table.insert().values(
                candidate_id=body.candidate_id,
                triggered_by=user["id"],
                status="pending",
                started_at=now,
            )
        )
        build_id = result.inserted_primary_key[0]
        write_audit(
            conn,
            user_id=user["id"],
            action="build_triggered",
            entity_type="build",
            entity_id=build_id,
            detail=f"candidate_id={body.candidate_id}",
        )
        conn.commit()

        row = conn.execute(
            text("SELECT * FROM builds WHERE id = :id"),
            {"id": build_id},
        ).mappings().fetchone()

    # Run build async in background
    asyncio.create_task(orchestrator.run_build(build_id, body.candidate_id))

    return dict(row)


@router.get("/{build_id}", response_model=BuildOut)
async def get_build(build_id: int, user=Depends(require_auth)):
    with engine.connect() as conn:
        row = conn.execute(
            text("SELECT * FROM builds WHERE id = :id"),
            {"id": build_id},
        ).mappings().fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Build not found")
    return dict(row)


@router.get("/{build_id}/logs")
async def get_build_logs(build_id: int, user=Depends(require_auth)):
    with engine.connect() as conn:
        row = conn.execute(
            text("SELECT log_path FROM builds WHERE id = :id"),
            {"id": build_id},
        ).mappings().fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Build not found")

    log_path = row["log_path"]
    if not log_path or not os.path.exists(log_path):
        return PlainTextResponse("No log file available yet.")

    def _iter_log():
        with open(log_path, "r", errors="replace") as f:
            yield f.read()

    return StreamingResponse(_iter_log(), media_type="text/plain")
