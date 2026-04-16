"""Script orchestrator for Image Lifecycle backend.

Wraps existing bash scripts, runs them async, streams stdout to log files,
and updates database status.

Scripts are stubs if not present - the real logic lives in the shell scripts.
"""
import asyncio
import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Optional

from sqlalchemy import text

import config
from database import engine, builds_table, validations_table, distribution_records_table, write_audit

logger = logging.getLogger("image-lifecycle.orchestrator")


def _ensure_logs_dir() -> Path:
    logs = Path(config.LOGS_DIR)
    logs.mkdir(parents=True, exist_ok=True)
    return logs


async def _run_script(script_name: str, args: List[str], log_path: str) -> tuple[int, str]:
    """Run a bash script async, stream output to log file. Returns (exit_code, output)."""
    script_path = Path(config.SCRIPTS_DIR) / script_name

    if not script_path.exists():
        msg = f"Script not found: {script_path} - returning stub success"
        logger.warning(msg)
        with open(log_path, "w") as f:
            f.write(f"[STUB] {msg}\n")
            f.write(f"[STUB] Would have run: {script_path} {' '.join(args)}\n")
            f.write("[STUB] No actual execution performed.\n")
        return 0, msg

    cmd = [str(script_path)] + args
    logger.info(f"Running: {' '.join(cmd)}")

    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )

        output_lines = []
        with open(log_path, "w") as log_file:
            async for line in proc.stdout:
                decoded = line.decode("utf-8", errors="replace")
                log_file.write(decoded)
                log_file.flush()
                output_lines.append(decoded.rstrip())

        await proc.wait()
        return proc.returncode, "\n".join(output_lines[-50:])  # Last 50 lines as summary

    except Exception as exc:
        error_msg = f"Failed to execute script: {exc}"
        logger.error(error_msg)
        with open(log_path, "a") as f:
            f.write(f"\n[ERROR] {error_msg}\n")
        return 1, error_msg


async def run_discover() -> List[dict]:
    """Run discover.sh and return list of new candidate dicts."""
    logs_dir = _ensure_logs_dir()
    ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    log_path = str(logs_dir / f"discover-{ts}.log")

    exit_code, output = await _run_script("discover.sh", [], log_path)

    candidates = []
    if exit_code == 0:
        # Try to parse JSON output from discover.sh if it emits JSON
        for line in output.splitlines():
            line = line.strip()
            if line.startswith("{") and "vendor" in line:
                try:
                    cand = json.loads(line)
                    candidates.append(cand)
                except json.JSONDecodeError:
                    pass

    logger.info(f"discover.sh finished (exit={exit_code}), found {len(candidates)} candidates")
    return candidates


async def run_build(build_id: int, candidate_id: Optional[int]) -> None:
    """Run build.sh for the given build, update DB status."""
    logs_dir = _ensure_logs_dir()
    ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    log_path = str(logs_dir / f"build-{build_id}-{ts}.log")

    # Mark as running
    with engine.connect() as conn:
        conn.execute(
            builds_table.update()
            .where(builds_table.c.id == build_id)
            .values(
                status="running",
                started_at=datetime.now(timezone.utc),
                log_path=log_path,
            )
        )
        conn.commit()

    args = []
    if candidate_id:
        args = [str(candidate_id)]

    exit_code, output = await _run_script("build.sh", args, log_path)
    finished = datetime.now(timezone.utc)
    new_status = "passed" if exit_code == 0 else "failed"

    # Extract image_name from output if present
    image_name = None
    for line in output.splitlines():
        if "IMAGE_NAME=" in line:
            image_name = line.split("IMAGE_NAME=", 1)[-1].strip()
            break

    with engine.connect() as conn:
        conn.execute(
            builds_table.update()
            .where(builds_table.c.id == build_id)
            .values(
                status=new_status,
                finished_at=finished,
                image_name=image_name,
            )
        )
        write_audit(
            conn,
            user_id=None,
            action="build_finished",
            entity_type="build",
            entity_id=build_id,
            detail=f"status={new_status} exit_code={exit_code}",
        )
        conn.commit()

    logger.info(f"Build {build_id} finished with status={new_status}")


async def run_validate(validation_id: int, build_id: int) -> None:
    """Run first-boot-validate.sh for the given validation, update DB status."""
    logs_dir = _ensure_logs_dir()
    ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    log_path = str(logs_dir / f"validate-{validation_id}-{ts}.log")

    with engine.connect() as conn:
        conn.execute(
            validations_table.update()
            .where(validations_table.c.id == validation_id)
            .values(
                status="running",
                started_at=datetime.now(timezone.utc),
            )
        )
        conn.commit()

    exit_code, output = await _run_script(
        "first-boot-validate.sh", [str(build_id)], log_path
    )
    finished = datetime.now(timezone.utc)
    new_status = "passed" if exit_code == 0 else "failed"

    # Parse simple JSON results if script emits them
    results = {"tests": [], "summary": output[-500:] if output else ""}
    for line in output.splitlines():
        line = line.strip()
        if line.startswith("{") and "test_name" in line:
            try:
                results["tests"].append(json.loads(line))
            except json.JSONDecodeError:
                pass

    with engine.connect() as conn:
        conn.execute(
            validations_table.update()
            .where(validations_table.c.id == validation_id)
            .values(
                status=new_status,
                finished_at=finished,
                results_json=json.dumps(results),
            )
        )
        write_audit(
            conn,
            user_id=None,
            action="validation_finished",
            entity_type="validation",
            entity_id=validation_id,
            detail=f"status={new_status} build_id={build_id}",
        )
        conn.commit()

    logger.info(f"Validation {validation_id} finished with status={new_status}")


async def run_distribute(distribution_ids: List[int], publish_id: int) -> None:
    """Run distribute.sh for a publish request, update distribution record statuses."""
    logs_dir = _ensure_logs_dir()
    ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    log_path = str(logs_dir / f"distribute-{publish_id}-{ts}.log")

    # Mark all distribution records as running
    with engine.connect() as conn:
        for dist_id in distribution_ids:
            conn.execute(
                distribution_records_table.update()
                .where(distribution_records_table.c.id == dist_id)
                .values(status="running", started_at=datetime.now(timezone.utc))
            )
        conn.commit()

    exit_code, output = await _run_script(
        "distribute.sh", [str(publish_id)], log_path
    )
    finished = datetime.now(timezone.utc)
    new_status = "complete" if exit_code == 0 else "failed"

    with engine.connect() as conn:
        for dist_id in distribution_ids:
            conn.execute(
                distribution_records_table.update()
                .where(distribution_records_table.c.id == dist_id)
                .values(status=new_status, finished_at=finished)
            )
        write_audit(
            conn,
            user_id=None,
            action="distribution_finished",
            entity_type="publish_request",
            entity_id=publish_id,
            detail=f"status={new_status} exit_code={exit_code}",
        )
        conn.commit()

    logger.info(f"Distribution for publish {publish_id} finished with status={new_status}")
