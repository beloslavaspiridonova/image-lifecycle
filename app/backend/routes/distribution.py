"""Distribution routes."""
import asyncio
from datetime import datetime, timezone
from typing import List

from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy import text

import orchestrator
from auth import require_auth, require_role
from database import engine, distribution_records_table, write_audit
from models import DistributionRecordOut

router = APIRouter(prefix="/api/distribution", tags=["distribution"])

REGIONS = ["ZRH", "FRA", "SJC", "MNL", "TYO"]


@router.get("", response_model=List[DistributionRecordOut])
async def list_distribution(user=Depends(require_auth)):
    with engine.connect() as conn:
        rows = conn.execute(
            text("SELECT * FROM distribution_records ORDER BY id DESC")
        ).mappings().fetchall()
    return [dict(r) for r in rows]


@router.post("/{publish_id}/start", response_model=List[DistributionRecordOut])
async def start_distribution(
    publish_id: int,
    user=Depends(require_role("service_admin")),
):
    now = datetime.now(timezone.utc)

    with engine.connect() as conn:
        pr = conn.execute(
            text("SELECT id, status FROM publish_requests WHERE id = :id"),
            {"id": publish_id},
        ).mappings().fetchone()
        if not pr:
            raise HTTPException(status_code=404, detail="Publish request not found")
        if pr["status"] != "published":
            raise HTTPException(
                status_code=400,
                detail="Publish request must be in published status before distribution",
            )

        dist_ids = []
        for region in REGIONS:
            result = conn.execute(
                distribution_records_table.insert().values(
                    publish_id=publish_id,
                    region=region,
                    status="pending",
                    started_at=now,
                )
            )
            dist_ids.append(result.inserted_primary_key[0])

        write_audit(
            conn,
            user_id=user["id"],
            action="distribution_started",
            entity_type="publish_request",
            entity_id=publish_id,
            detail=f"regions={','.join(REGIONS)}",
        )
        conn.commit()

        # Fetch the newly created records
        rows = []
        for dist_id in dist_ids:
            row = conn.execute(
                text("SELECT * FROM distribution_records WHERE id = :id"),
                {"id": dist_id},
            ).mappings().fetchone()
            if row:
                rows.append(dict(row))

    asyncio.create_task(orchestrator.run_distribute(dist_ids, publish_id))

    return rows
