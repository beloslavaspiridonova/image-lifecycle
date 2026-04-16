"""Audit log routes."""
from typing import List, Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy import text

from auth import require_role
from database import engine
from models import AuditLogEntry

router = APIRouter(prefix="/api/audit", tags=["audit"])


@router.get("", response_model=List[AuditLogEntry])
async def list_audit(
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    action: Optional[str] = Query(None),
    entity_type: Optional[str] = Query(None),
    user=Depends(require_role("service_admin")),
):
    conditions = []
    params: dict = {"limit": limit, "offset": offset}

    if action:
        conditions.append("action = :action")
        params["action"] = action
    if entity_type:
        conditions.append("entity_type = :entity_type")
        params["entity_type"] = entity_type

    where_clause = ("WHERE " + " AND ".join(conditions)) if conditions else ""
    query = text(
        f"SELECT * FROM audit_log {where_clause} ORDER BY id DESC LIMIT :limit OFFSET :offset"
    )

    with engine.connect() as conn:
        rows = conn.execute(query, params).mappings().fetchall()

    return [dict(r) for r in rows]
