"""System health and status routes."""
from fastapi import APIRouter, Depends
from sqlalchemy import text

import config
from auth import require_role
from database import engine
from models import HealthResponse, SystemStatusResponse, AuditLogEntry

router = APIRouter(prefix="/api/system", tags=["system"])

TABLES = [
    "users",
    "roles",
    "candidates",
    "builds",
    "validations",
    "publish_requests",
    "distribution_records",
    "audit_log",
]


@router.get("/health", response_model=HealthResponse)
async def health():
    return {"status": "ok"}


@router.get("/status", response_model=SystemStatusResponse)
async def system_status(user=Depends(require_role("service_admin"))):
    db_stats = {}
    recent_activity = []

    with engine.connect() as conn:
        for table in TABLES:
            try:
                row = conn.execute(
                    text(f"SELECT COUNT(*) AS cnt FROM {table}")
                ).mappings().fetchone()
                db_stats[table] = row["cnt"] if row else 0
            except Exception:
                db_stats[table] = -1

        rows = conn.execute(
            text("SELECT * FROM audit_log ORDER BY id DESC LIMIT 5")
        ).mappings().fetchall()
        recent_activity = [dict(r) for r in rows]

    return {
        "status": "ok",
        "scripts_dir": config.SCRIPTS_DIR,
        "cs_api_base": config.CS_API_BASE,
        "version": config.VERSION,
        "db_stats": db_stats,
        "recent_activity": recent_activity,
    }
