"""Database setup and access for Image Lifecycle backend.

Uses SQLAlchemy Core with SQLite (dev) and Postgres (prod).
Pattern mirrors taas-chat database.py - context manager, init_db, seed_owner.
"""
import logging
from contextlib import contextmanager
from datetime import datetime, timezone

from sqlalchemy import (
    create_engine, text, MetaData, Table, Column,
    Integer, String, Boolean, DateTime, Text, ForeignKey, JSON,
    inspect as sa_inspect,
)
from sqlalchemy.pool import StaticPool

import config

logger = logging.getLogger("image-lifecycle.db")

# SQLAlchemy engine - SQLite dev / Postgres prod
_engine_kwargs = {}
if config.DATABASE_URL.startswith("sqlite"):
    _engine_kwargs = {
        "connect_args": {"check_same_thread": False},
        "poolclass": StaticPool,
    }

engine = create_engine(config.DATABASE_URL, **_engine_kwargs)
metadata = MetaData()

# ---- Table definitions ----

users_table = Table(
    "users", metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("email", String(255), unique=True, nullable=False),
    Column("name", String(255), nullable=True),
    Column("password_hash", Text, nullable=True),
    Column("created_at", DateTime, default=lambda: datetime.now(timezone.utc)),
    Column("is_active", Boolean, default=True),
)

roles_table = Table(
    "roles", metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("user_id", Integer, ForeignKey("users.id"), nullable=False),
    # owner=5, service_admin=4, reviewer=3, maintainer=2, viewer=1
    Column("role", String(50), nullable=False),
    Column("created_at", DateTime, default=lambda: datetime.now(timezone.utc)),
)

candidates_table = Table(
    "candidates", metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("vendor", String(100), nullable=False),
    Column("os_name", String(100), nullable=False),
    Column("version", String(100), nullable=False),
    Column("source_url", Text, nullable=True),
    Column("status", String(50), default="pending"),
    Column("discovered_at", DateTime, default=lambda: datetime.now(timezone.utc)),
    Column("notes", Text, nullable=True),
)

builds_table = Table(
    "builds", metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("candidate_id", Integer, ForeignKey("candidates.id"), nullable=True),
    Column("triggered_by", Integer, ForeignKey("users.id"), nullable=True),
    Column("status", String(50), default="pending"),
    Column("started_at", DateTime, nullable=True),
    Column("finished_at", DateTime, nullable=True),
    Column("log_path", Text, nullable=True),
    Column("image_name", String(255), nullable=True),
)

validations_table = Table(
    "validations", metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("build_id", Integer, ForeignKey("builds.id"), nullable=False),
    Column("status", String(50), default="pending"),
    Column("started_at", DateTime, nullable=True),
    Column("finished_at", DateTime, nullable=True),
    Column("results_json", Text, nullable=True),
)

publish_requests_table = Table(
    "publish_requests", metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("build_id", Integer, ForeignKey("builds.id"), nullable=False),
    Column("requested_by", Integer, ForeignKey("users.id"), nullable=True),
    Column("status", String(50), default="pending"),
    Column("approved_by", Integer, ForeignKey("users.id"), nullable=True),
    Column("approved_at", DateTime, nullable=True),
    Column("mi_confirmed_at", DateTime, nullable=True),
    Column("notes", Text, nullable=True),
    Column("created_at", DateTime, default=lambda: datetime.now(timezone.utc)),
)

distribution_records_table = Table(
    "distribution_records", metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("publish_id", Integer, ForeignKey("publish_requests.id"), nullable=False),
    Column("region", String(20), nullable=False),
    Column("status", String(50), default="pending"),
    Column("started_at", DateTime, nullable=True),
    Column("finished_at", DateTime, nullable=True),
)

audit_log_table = Table(
    "audit_log", metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("user_id", Integer, ForeignKey("users.id"), nullable=True),
    Column("action", String(100), nullable=False),
    Column("entity_type", String(50), nullable=True),
    Column("entity_id", Integer, nullable=True),
    Column("detail", Text, nullable=True),
    Column("created_at", DateTime, default=lambda: datetime.now(timezone.utc)),
)


def init_db():
    """Create all tables if they do not exist."""
    metadata.create_all(engine)
    logger.info("Database tables initialised")


def seed_owner():
    """Create the initial owner user if no users exist yet."""
    import config as cfg
    from passlib.context import CryptContext

    pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")

    with engine.connect() as conn:
        result = conn.execute(text("SELECT COUNT(*) AS cnt FROM users"))
        row = result.mappings().fetchone()
        if row and row["cnt"] > 0:
            return  # Already have users - skip seeding

        # Create owner user with a default temporary password
        default_password = "ChangeMe123!"
        pw_hash = pwd_ctx.hash(default_password)
        now = datetime.now(timezone.utc)

        result = conn.execute(
            users_table.insert().values(
                email=cfg.INITIAL_OWNER_EMAIL,
                name=cfg.INITIAL_OWNER_NAME,
                password_hash=pw_hash,
                created_at=now,
                is_active=True,
            )
        )
        user_id = result.inserted_primary_key[0]

        conn.execute(
            roles_table.insert().values(
                user_id=user_id,
                role="owner",
                created_at=now,
            )
        )

        conn.execute(
            audit_log_table.insert().values(
                user_id=user_id,
                action="seed_owner",
                entity_type="user",
                entity_id=user_id,
                detail=f"Initial owner account created for {cfg.INITIAL_OWNER_EMAIL}",
                created_at=now,
            )
        )

        conn.commit()
        logger.info(f"Seeded initial owner: {cfg.INITIAL_OWNER_EMAIL} (password: {default_password})")


@contextmanager
def get_db():
    """Context manager yielding a SQLAlchemy connection with commit/rollback."""
    conn = engine.connect()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def write_audit(conn, user_id, action, entity_type=None, entity_id=None, detail=None):
    """Helper to write an audit log entry inside an existing connection."""
    conn.execute(
        audit_log_table.insert().values(
            user_id=user_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            detail=detail,
            created_at=datetime.now(timezone.utc),
        )
    )
