"""Candidate routes."""
import asyncio
from datetime import datetime, timezone
from typing import List

from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy import text

import orchestrator
from auth import require_auth, require_role
from database import engine, candidates_table, write_audit
from models import CandidateOut, CandidatePatch, CandidateCreate

router = APIRouter(prefix="/api/candidates", tags=["candidates"])


@router.get("", response_model=List[CandidateOut])
async def list_candidates(user=Depends(require_auth)):
    with engine.connect() as conn:
        rows = conn.execute(
            text("SELECT * FROM candidates ORDER BY discovered_at DESC")
        ).mappings().fetchall()
    return [dict(r) for r in rows]


@router.post("/discover")
async def discover(user=Depends(require_role("service_admin"))):
    """Trigger discover.sh in the background and return immediately."""
    asyncio.create_task(orchestrator.run_discover())
    with engine.connect() as conn:
        write_audit(
            conn,
            user_id=user["id"],
            action="discover_triggered",
            entity_type="candidate",
            entity_id=None,
            detail="Discovery script triggered",
        )
        conn.commit()
    return {"ok": True, "message": "Discovery started"}


@router.get("/{candidate_id}", response_model=CandidateOut)
async def get_candidate(candidate_id: int, user=Depends(require_auth)):
    with engine.connect() as conn:
        row = conn.execute(
            text("SELECT * FROM candidates WHERE id = :id"),
            {"id": candidate_id},
        ).mappings().fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Candidate not found")
    return dict(row)


@router.patch("/{candidate_id}", response_model=CandidateOut)
async def update_candidate(candidate_id: int, body: CandidatePatch, user=Depends(require_role("maintainer"))):
    updates = body.model_dump(exclude_none=True)
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")

    set_clause = ", ".join(f"{k} = :{k}" for k in updates)
    updates["id"] = candidate_id

    with engine.connect() as conn:
        result = conn.execute(
            text(f"UPDATE candidates SET {set_clause} WHERE id = :id"),
            updates,
        )
        if result.rowcount == 0:
            raise HTTPException(status_code=404, detail="Candidate not found")
        write_audit(
            conn,
            user_id=user["id"],
            action="candidate_updated",
            entity_type="candidate",
            entity_id=candidate_id,
            detail=str(updates),
        )
        conn.commit()

        row = conn.execute(
            text("SELECT * FROM candidates WHERE id = :id"),
            {"id": candidate_id},
        ).mappings().fetchone()

    return dict(row)
