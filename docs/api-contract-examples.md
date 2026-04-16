# API Contract Examples

**Date:** 2026-04-16  
**Status:** Draft v1.0  
**Author:** Ellie

---

## 1. Purpose

These examples make the backend API spec easier to implement by showing realistic request/response payloads for the highest-priority endpoints.

---

## 2. Auth

### POST `/api/auth/login`

#### Request
```json
{
  "email": "beloslava.spiridonova@cloudsigma.com",
  "password": "********"
}
```

#### Response
```json
{
  "session": {
    "id": "sess_123",
    "expires_at": "2026-04-17T08:00:00Z"
  },
  "user": {
    "id": "u_1",
    "email": "beloslava.spiridonova@cloudsigma.com",
    "display_name": "Bela"
  },
  "role": "owner",
  "is_owner": true,
  "capabilities": [
    "transfer_ownership",
    "approve_publish",
    "trigger_build",
    "view_audit"
  ]
}
```

### GET `/api/auth/me`

#### Response
```json
{
  "user": {
    "id": "u_2",
    "email": "ellie-ai@internal",
    "display_name": "Ellie"
  },
  "role": "service_admin",
  "is_owner": false,
  "capabilities": [
    "manage_roles",
    "manage_policy",
    "approve_publish",
    "trigger_build",
    "view_audit"
  ]
}
```

---

## 3. Owner and roles

### GET `/api/owner`

#### Response
```json
{
  "owner": {
    "user_id": "u_1",
    "email": "beloslava.spiridonova@cloudsigma.com",
    "display_name": "Bela"
  },
  "assigned_at": "2026-04-16T19:54:00Z",
  "assigned_by": "bootstrap"
}
```

### POST `/api/owner/transfer`

#### Request
```json
{
  "target_user_id": "u_7",
  "reason": "handover to jOPS lead"
}
```

#### Response
```json
{
  "status": "success",
  "previous_owner": "u_1",
  "new_owner": "u_7",
  "transferred_at": "2026-04-20T09:00:00Z",
  "audit_event_id": "ae_9001"
}
```

### GET `/api/roles`

#### Response
```json
{
  "roles": [
    {
      "role": "owner",
      "assigned_users": [
        {
          "user_id": "u_1",
          "email": "beloslava.spiridonova@cloudsigma.com"
        }
      ]
    },
    {
      "role": "maintainer",
      "assigned_users": [
        {
          "user_id": "u_2",
          "email": "ellie-ai@internal"
        },
        {
          "user_id": "u_1",
          "email": "beloslava.spiridonova@cloudsigma.com"
        }
      ]
    }
  ]
}
```

---

## 4. Candidates

### GET `/api/candidates`

#### Response
```json
{
  "items": [
    {
      "id": "cand_ubuntu_24_04_20260416",
      "vendor": "ubuntu",
      "family": "ubuntu-lts",
      "version": "24.04",
      "serial": "20260416",
      "classification": "brand-new",
      "intake_mode": "automatic",
      "status": "proposed",
      "discovered_at": "2026-04-16T18:10:00Z",
      "reviewer": null
    }
  ],
  "total": 1
}
```

### POST `/api/candidates/{id}/approve`

#### Request
```json
{
  "reason": "Approved for onboarding trial"
}
```

#### Response
```json
{
  "id": "cand_ubuntu_24_04_20260416",
  "status": "approved",
  "approved_by": "beloslava.spiridonova@cloudsigma.com",
  "approved_at": "2026-04-16T20:00:00Z"
}
```

---

## 5. Build runs

### POST `/api/builds`

#### Request
```json
{
  "candidate_id": "cand_ubuntu_22_04_refresh",
  "source_drive_uuid": "12345678-1234-1234-1234-123456789abc",
  "image_version": "22.04",
  "run_type": "refresh"
}
```

#### Response
```json
{
  "id": "build_20260416_001",
  "status": "starting",
  "started_at": "2026-04-16T20:05:00Z",
  "started_by": "ellie-ai@internal"
}
```

### GET `/api/builds/{id}`

#### Response
```json
{
  "id": "build_20260416_001",
  "status": "success",
  "candidate_id": "cand_ubuntu_22_04_refresh",
  "source_drive_uuid": "12345678-1234-1234-1234-123456789abc",
  "build_drive_uuid": "22345678-1234-1234-1234-123456789abc",
  "build_server_uuid": "32345678-1234-1234-1234-123456789abc",
  "build_server_ip": "198.51.100.42",
  "snapshot_name": "openclaw-ubuntu-22.04-2026-04-16-staging",
  "snapshot_uuid": "42345678-1234-1234-1234-123456789abc",
  "image_version": "22.04",
  "started_at": "2026-04-16T20:05:00Z",
  "completed_at": "2026-04-16T20:23:00Z",
  "duration_ms": 1080000,
  "artifacts": [
    {
      "type": "log",
      "path": "logs/build-2026-04-16-200500.log"
    },
    {
      "type": "test-log",
      "path": "logs/test-results-vm-2026-04-16-200500.txt"
    }
  ]
}
```

---

## 6. Validation

### GET `/api/validations/{id}`

#### Response
```json
{
  "id": "val_20260416_001",
  "build_run_id": "build_20260416_001",
  "status": "passed",
  "pass_count": 19,
  "fail_count": 0,
  "high_risk_fail_count": 0,
  "started_at": "2026-04-16T20:18:00Z",
  "completed_at": "2026-04-16T20:22:00Z",
  "summary": "All validation checks passed"
}
```

### GET `/api/validations/{id}/results`

#### Response
```json
{
  "items": [
    {
      "test_name": "openclaw_service_running",
      "result": "passed",
      "risk_level": "high",
      "message": "openclaw.service is active"
    },
    {
      "test_name": "cloud_init_datasource",
      "result": "passed",
      "risk_level": "high",
      "message": "CloudSigma datasource present"
    }
  ]
}
```

---

## 7. Publish queue

### POST `/api/publish-requests`

#### Request
```json
{
  "build_run_id": "build_20260416_001",
  "validation_run_id": "val_20260416_001",
  "snapshot_uuid": "42345678-1234-1234-1234-123456789abc",
  "snapshot_name": "openclaw-ubuntu-22.04-2026-04-16-staging",
  "reviewer_user_id": "u_1",
  "notes": "Ready for Bela review and manual MI publish"
}
```

#### Response
```json
{
  "id": "publish_20260416_001",
  "status": "publish-pending",
  "mi_state": "pending",
  "requires_manual_mi": true,
  "created_at": "2026-04-16T20:24:00Z"
}
```

### POST `/api/publish-requests/{id}/approve`

#### Request
```json
{
  "reason": "Validation clean, ready for manual MI publish"
}
```

#### Response
```json
{
  "id": "publish_20260416_001",
  "status": "approved",
  "approved_by": "beloslava.spiridonova@cloudsigma.com",
  "approved_at": "2026-04-16T20:30:00Z"
}
```

### POST `/api/publish-requests/{id}/promote`

#### Request
```json
{
  "mi_ref": "MI-published manually by Bela",
  "notes": "Promotion confirmed"
}
```

#### Response
```json
{
  "id": "publish_20260416_001",
  "status": "published",
  "mi_state": "completed",
  "mi_ref": "MI-published manually by Bela",
  "updated_at": "2026-04-16T20:37:00Z"
}
```

---

## 8. Distribution

### POST `/api/distributions`

#### Request
```json
{
  "publish_request_id": "publish_20260416_001",
  "snapshot_uuid": "42345678-1234-1234-1234-123456789abc",
  "target_regions": ["ZRH", "FRA", "SJC", "MNL", "TYO"]
}
```

#### Response
```json
{
  "id": "dist_20260416_001",
  "status": "running",
  "started_at": "2026-04-16T20:40:00Z"
}
```

### GET `/api/distributions/{id}`

#### Response
```json
{
  "id": "dist_20260416_001",
  "status": "partial",
  "regions": [
    {"region_code": "ZRH", "status": "success", "attempt_count": 1},
    {"region_code": "FRA", "status": "success", "attempt_count": 1},
    {"region_code": "SJC", "status": "running", "attempt_count": 1},
    {"region_code": "MNL", "status": "failed", "attempt_count": 2, "last_error": "remote clone timeout"},
    {"region_code": "TYO", "status": "pending", "attempt_count": 0}
  ]
}
```

---

## 9. Audit

### GET `/api/audit-events`

#### Response
```json
{
  "items": [
    {
      "id": "ae_1001",
      "event_type": "publish-request-created",
      "actor_type": "service-account",
      "actor_name": "image-automation",
      "actor_role": "service-account",
      "object_type": "publish-request",
      "object_id": "publish_20260416_001",
      "result": "success",
      "created_at": "2026-04-16T20:24:00Z"
    },
    {
      "id": "ae_1002",
      "event_type": "publish-request-approved",
      "actor_type": "user",
      "actor_name": "beloslava.spiridonova@cloudsigma.com",
      "actor_role": "owner",
      "object_type": "publish-request",
      "object_id": "publish_20260416_001",
      "result": "success",
      "created_at": "2026-04-16T20:30:00Z"
    }
  ]
}
```

---

## 10. Error shape

Recommended standard error shape:

```json
{
  "error": {
    "code": "permission_denied",
    "message": "Reviewer or above required to approve publish requests",
    "details": {
      "required_capability": "approve_publish"
    }
  }
}
```

---

## 11. Notes

These examples are intentionally close to the current repo implementation and queue files so that the first backend version can wrap existing scripts instead of fighting them.
