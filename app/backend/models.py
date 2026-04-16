"""Pydantic v2 models for Image Lifecycle API.

Request and response models for all entities.
"""
from __future__ import annotations

from datetime import datetime
from typing import Optional, List, Any
from pydantic import BaseModel, EmailStr, ConfigDict


# ---- Auth ----

class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    email: str
    name: Optional[str] = None
    created_at: Optional[datetime] = None
    is_active: bool = True


class MeResponse(BaseModel):
    user: UserOut
    roles: List[str]
    is_owner: bool
    capabilities: List[str]


# ---- Candidates ----

class CandidateOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    vendor: str
    os_name: str
    version: str
    source_url: Optional[str] = None
    status: str
    discovered_at: Optional[datetime] = None
    notes: Optional[str] = None


class CandidatePatch(BaseModel):
    status: Optional[str] = None
    notes: Optional[str] = None
    vendor: Optional[str] = None
    os_name: Optional[str] = None
    version: Optional[str] = None
    source_url: Optional[str] = None


class CandidateCreate(BaseModel):
    vendor: str
    os_name: str
    version: str
    source_url: Optional[str] = None
    notes: Optional[str] = None


# ---- Builds ----

class BuildOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    candidate_id: Optional[int] = None
    triggered_by: Optional[int] = None
    status: str
    started_at: Optional[datetime] = None
    finished_at: Optional[datetime] = None
    log_path: Optional[str] = None
    image_name: Optional[str] = None


class BuildCreate(BaseModel):
    candidate_id: int


# ---- Validations ----

class ValidationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    build_id: int
    status: str
    started_at: Optional[datetime] = None
    finished_at: Optional[datetime] = None
    results_json: Optional[str] = None


# ---- Publish Requests ----

class PublishRequestOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    build_id: int
    requested_by: Optional[int] = None
    status: str
    approved_by: Optional[int] = None
    approved_at: Optional[datetime] = None
    mi_confirmed_at: Optional[datetime] = None
    notes: Optional[str] = None
    created_at: Optional[datetime] = None


class PublishRequestCreate(BaseModel):
    build_id: int
    notes: Optional[str] = None


class PublishActionRequest(BaseModel):
    notes: Optional[str] = None


# ---- Distribution ----

class DistributionRecordOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    publish_id: int
    region: str
    status: str
    started_at: Optional[datetime] = None
    finished_at: Optional[datetime] = None


# ---- Audit ----

class AuditLogEntry(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: Optional[int] = None
    action: str
    entity_type: Optional[str] = None
    entity_id: Optional[int] = None
    detail: Optional[str] = None
    created_at: Optional[datetime] = None


# ---- System ----

class HealthResponse(BaseModel):
    status: str


class SystemStatusResponse(BaseModel):
    status: str
    scripts_dir: str
    cs_api_base: str
    version: str
    db_stats: dict
    recent_activity: List[AuditLogEntry]


# ---- Users / Settings ----

class UserCreate(BaseModel):
    email: EmailStr
    name: Optional[str] = None
    password: str
    role: str = "viewer"


class UserRoleUpdate(BaseModel):
    role: str
