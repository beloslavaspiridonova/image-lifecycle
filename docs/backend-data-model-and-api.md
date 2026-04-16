# Backend Data Model and API

**Date:** 2026-04-16  
**Status:** Draft v1.0  
**Author:** Ellie

---

## 1. Purpose

This document defines the first practical backend design for the CloudSigma Image Lifecycle system.

It is meant to support:
- the role and ownership model
- the UI wireframes
- the review and approval flows
- the build/validation/publish/distribution pipeline
- future implementation as a web app and API

This is a system-internal operations product, so the model is optimized for:
- auditability
- operational clarity
- explicit approval steps
- service account support
- low ambiguity around ownership and permissions

---

## 2. System Scope

The backend needs to manage these major domains:
1. identity and access
2. vendors and version candidates
3. instructions and script bundles
4. build runs and artifacts
5. validation runs and results
6. publish requests
7. distribution runs
8. audit trail
9. policy and ownership

---

## 3. Core Design Principles

### 3.1 Explicit ownership
There is exactly one current system owner.
Ownership is tracked separately from normal role assignment.

### 3.2 Human roles and automation are different
Humans log in with user sessions.
Automation authenticates with service account credentials or API keys.

### 3.3 Approval is first-class
Approvals are not hidden comments on objects. They are explicit objects/events.

### 3.4 Audit every privileged action
Every meaningful privileged action should be attributable to actor, role, time, target, and result.

### 3.5 Objects should be traceable end-to-end
A candidate should be traceable to:
- build run
- validation run
- publish request
- distribution run
- approval history

---

## 4. Entity Overview

### Identity and access
- `users`
- `user_role_assignments`
- `system_owner`
- `service_accounts`
- `sessions`

### Release pipeline
- `vendor_sources`
- `version_candidates`
- `instruction_sets`
- `script_bundles`
- `build_runs`
- `build_artifacts`
- `validation_runs`
- `validation_results`
- `publish_requests`
- `distribution_runs`
- `distribution_regions`

### Governance and traceability
- `approval_records`
- `audit_events`
- `policy_settings`
- `location_exceptions`

---

## 5. Identity and Access Model

## 5.1 users
Represents a human operator.

### Fields
- `id`
- `email`
- `display_name`
- `password_hash` or external auth reference
- `is_active`
- `created_at`
- `updated_at`
- `last_login_at`

### Notes
- In v1, email-based internal auth is enough
- In v2, SSO can replace or supplement password auth

---

## 5.2 user_role_assignments
Assigns lifecycle roles to users.

### Fields
- `id`
- `user_id`
- `role` (`owner`, `service_admin`, `reviewer`, `maintainer`, `viewer`)
- `scope` (initially `system`)
- `assigned_by`
- `assigned_at`
- `is_active`
- `notes`

### Notes
- Although ownership is stored separately, owner role may still appear here for convenience
- The system owner record remains the final source of truth for transfer rights

---

## 5.3 system_owner
Tracks the singular current owner.

### Fields
- `id`
- `user_id`
- `assigned_at`
- `assigned_by`
- `reason`
- `is_current`

### Rules
- exactly one row with `is_current = true`
- ownership transfer creates audit event and owner-history continuity

---

## 5.4 service_accounts
Represents non-human actors.

### Fields
- `id`
- `name`
- `type` (`service-account`)
- `token_hash`
- `capabilities` (json or join table)
- `is_active`
- `created_at`
- `created_by`
- `last_used_at`

### Example
`image-automation`

---

## 5.5 sessions
Tracks UI login sessions.

### Fields
- `id`
- `user_id`
- `session_token_hash`
- `created_at`
- `expires_at`
- `last_seen_at`
- `ip_address`
- `user_agent`
- `is_active`

---

## 6. Vendor and Intake Model

## 6.1 vendor_sources
Defines approved upstream sources.

### Fields
- `id`
- `name`
- `family`
- `description`
- `metadata_url`
- `checksum_url`
- `supported_versions` (json)
- `supported_architectures` (json)
- `supported_firmware` (json)
- `discovery_mode` (`manual`, `automatic`, `hybrid`)
- `default_version`
- `is_active`
- `created_at`
- `updated_at`

---

## 6.2 version_candidates
Represents discovered or manually-added image candidates.

### Fields
- `id`
- `vendor_source_id`
- `vendor`
- `family`
- `version`
- `serial`
- `classification` (`existing-refresh`, `known-not-onboarded`, `brand-new`, `rejected`, etc.)
- `intake_mode` (`automatic`, `manual`, `hybrid`)
- `status` (`draft`, `proposed`, `under-review`, `approved`, `rejected`, `deferred`, `in-progress`, `validated`, `failed`)
- `discovered_at`
- `discovered_by_actor`
- `reviewer_user_id`
- `notes`
- `metadata` (json)

### Relationships
- one candidate may have many build runs
- one candidate may have many approval records

---

## 7. Instruction and Script Governance Model

## 7.1 instruction_sets
Represents approved human-readable lifecycle instructions.

### Fields
- `id`
- `name`
- `type` (`onboarding`, `update`, `finalize`, `platform-specific`)
- `vendor`
- `platform_scope`
- `version`
- `status`
- `content_path`
- `approved_by`
- `approved_at`
- `created_at`
- `updated_at`

---

## 7.2 script_bundles
Represents executable implementation bundles.

### Fields
- `id`
- `name`
- `version`
- `status`
- `repo_ref`
- `checksum`
- `compatibility_notes`
- `approved_by`
- `approved_at`
- `created_at`

### Notes
A future build run should ideally record which instruction set and script bundle it used.

---

## 8. Build Model

## 8.1 build_runs
Tracks a single onboarding or refresh execution.

### Fields
- `id`
- `candidate_id` (nullable for ad hoc/manual runs)
- `run_type` (`onboarding`, `refresh`, `manual-test`)
- `status` (`starting`, `running`, `success`, `failed`, `cancelled`)
- `source_drive_uuid`
- `build_drive_uuid`
- `build_server_uuid`
- `build_server_ip`
- `snapshot_name`
- `snapshot_uuid`
- `image_version`
- `build_log_path`
- `started_by_actor`
- `started_by_role`
- `started_at`
- `completed_at`
- `duration_ms`
- `exit_code`
- `summary_json`

### Notes
This maps closely to the current `build.sh` output.

---

## 8.2 build_artifacts
Tracks files/logs emitted by a build.

### Fields
- `id`
- `build_run_id`
- `artifact_type` (`log`, `test-log`, `json-summary`, `snapshot-ref`, `report`)
- `path`
- `content_type`
- `size_bytes`
- `created_at`

---

## 9. Validation Model

## 9.1 validation_runs
Represents one test-suite execution.

### Fields
- `id`
- `build_run_id`
- `status` (`running`, `passed`, `failed`, `partial`)
- `test_suite_version`
- `started_by_actor`
- `started_by_role`
- `started_at`
- `completed_at`
- `pass_count`
- `fail_count`
- `high_risk_fail_count`
- `summary`
- `artifact_path`

---

## 9.2 validation_results
Represents individual test results.

### Fields
- `id`
- `validation_run_id`
- `test_name`
- `result` (`passed`, `failed`, `skipped`, `expected-fail`)
- `risk_level` (`low`, `medium`, `high`, `critical`)
- `message`
- `details`
- `artifact_ref`

### Important tests to model explicitly
- guest user exists
- guest sudo
- guest home dir
- cloud-init installed
- cloud-init datasource
- SSH injection path valid
- metadata reachable
- OpenClaw service active
- webchat service active
- Tailscale state valid
- BOOTSTRAP ready

---

## 10. Publish Model

## 10.1 publish_requests
Represents the human-gated promotion step.

### Fields
- `id`
- `build_run_id`
- `validation_run_id`
- `snapshot_uuid`
- `snapshot_name`
- `status` (`publish-pending`, `approved`, `rejected`, `deferred`, `published`, `failed`)
- `priority`
- `risk_level`
- `reviewer_user_id`
- `requires_manual_mi`
- `mi_state` (`pending`, `completed`, `blocked`)
- `mi_ref`
- `created_by_actor`
- `created_at`
- `updated_at`
- `notes`

### Notes
This maps directly to the current `publish.sh` queue item design.

---

## 11. Distribution Model

## 11.1 distribution_runs
Represents one regional rollout execution.

### Fields
- `id`
- `publish_request_id`
- `snapshot_uuid`
- `snapshot_name`
- `status` (`pending`, `running`, `partial`, `success`, `failed`)
- `started_by_actor`
- `started_at`
- `completed_at`
- `notes`

---

## 11.2 distribution_regions
Per-region rollout state.

### Fields
- `id`
- `distribution_run_id`
- `region_code` (`ZRH`, `FRA`, `SJC`, `MNL`, `TYO`)
- `priority_group`
- `status` (`pending`, `running`, `success`, `failed`, `retrying`, `excluded`)
- `attempt_count`
- `last_error`
- `updated_at`

---

## 11.3 location_exceptions
Approved exclusions for image/region combinations.

### Fields
- `id`
- `image_family`
- `version`
- `region_code`
- `reason`
- `approved_by`
- `approved_at`
- `status`

---

## 12. Governance and Audit Model

## 12.1 approval_records
Explicit record of approval decisions.

### Fields
- `id`
- `object_type` (`candidate`, `instruction-set`, `script-bundle`, `publish-request`, `rollback-request`)
- `object_id`
- `action` (`approve`, `reject`, `defer`, `override`)
- `actor_id`
- `actor_email`
- `actor_role`
- `reason`
- `created_at`
- `metadata`

---

## 12.2 audit_events
Append-only operational audit trail.

### Fields
- `id`
- `actor_type` (`user`, `service-account`, `system`)
- `actor_id`
- `actor_email_or_name`
- `actor_role`
- `event_type`
- `object_type`
- `object_id`
- `result`
- `summary`
- `details`
- `created_at`

### Examples
- ownership-transferred
- role-assigned
- build-triggered
- build-failed
- validation-passed
- publish-request-created
- publish-request-promoted
- distribution-region-failed

---

## 12.3 policy_settings
Stores global governance values.

### Fields
- `id`
- `key`
- `value_json`
- `updated_by`
- `updated_at`

### Example keys
- `retention.default_days`
- `approval.publish.requires_manual_mi`
- `approval.ai_changes.allowed_roles`
- `distribution.region_order`

---

## 13. Relationship Summary

```text
vendor_source -> version_candidate -> build_run -> validation_run -> publish_request -> distribution_run
                                           |               |
                                           |               -> validation_results
                                           -> build_artifacts

Any key object -> approval_records
Any key action -> audit_events

users -> user_role_assignments
users -> system_owner (single active owner)
service_accounts -> automated actions
```

---

## 14. Permission Model for API

## 14.1 Permission groups
Reuse the role model already documented:
- `OWNER_ROLES`
- `ADMIN_ROLES`
- `APPROVER_ROLES`
- `OPERATOR_ROLES`
- `READ_ROLES`

## 14.2 Capability checks
Prefer capability-based checks in code rather than raw role string checks everywhere.

Example:
- `can_trigger_build(actor)`
- `can_approve_publish(actor)`
- `can_transfer_ownership(actor)`

This avoids policy drift and keeps parity with UI gating.

---

## 15. API Endpoint Skeleton

## 15.1 Auth
### POST `/api/auth/login`
- human login
- returns session or token

### POST `/api/auth/logout`
- ends session

### GET `/api/auth/me`
- returns current identity, role, owner badge, capabilities

---

## 15.2 Roles and ownership
### GET `/api/roles`
- list roles, assignments, capability groups
- read roles only

### GET `/api/owner`
- current owner metadata

### POST `/api/owner/transfer`
- owner only
- body: target user id/email, reason

### POST `/api/roles/assign`
- owner/service_admin

### POST `/api/roles/revoke`
- owner/service_admin

---

## 15.3 Vendors and candidates
### GET `/api/vendors`
### POST `/api/vendors`
### GET `/api/candidates`
### POST `/api/candidates`
### POST `/api/candidates/{id}/approve`
### POST `/api/candidates/{id}/reject`
### POST `/api/candidates/{id}/defer`

---

## 15.4 Build runs
### GET `/api/builds`
### GET `/api/builds/{id}`
### POST `/api/builds`
- operator roles only

### POST `/api/builds/{id}/retry`
- operator roles only

### GET `/api/builds/{id}/artifacts`

---

## 15.5 Validation
### GET `/api/validations`
### GET `/api/validations/{id}`
### GET `/api/validations/{id}/results`
### POST `/api/validations/{id}/rerun`
- operator roles only

---

## 15.6 Publish queue
### GET `/api/publish-requests`
### GET `/api/publish-requests/{id}`
### POST `/api/publish-requests`
- operator roles only (`stage` equivalent)

### POST `/api/publish-requests/{id}/approve`
- approver roles only

### POST `/api/publish-requests/{id}/reject`
- approver roles only

### POST `/api/publish-requests/{id}/defer`
- approver roles only

### POST `/api/publish-requests/{id}/promote`
- approver roles only
- records MI completion

---

## 15.7 Distribution
### GET `/api/distributions`
### GET `/api/distributions/{id}`
### POST `/api/distributions`
- operator roles only

### POST `/api/distributions/{id}/regions/{region}/retry`
- operator roles only

---

## 15.8 Audit and policy
### GET `/api/audit-events`
### GET `/api/approval-records`
### GET `/api/policies`
### POST `/api/policies/{key}`
- owner/service_admin only

---

## 16. API Response Examples

## 16.1 `GET /api/auth/me`
```json
{
  "user": {
    "id": "u_123",
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

## 16.2 `GET /api/publish-requests/{id}`
```json
{
  "id": "publish-abc",
  "status": "publish-pending",
  "snapshot": {
    "uuid": "snap-123",
    "name": "openclaw-ubuntu-22.04-2026-04-16-staging"
  },
  "reviewer": {
    "email": "beloslava.spiridonova@cloudsigma.com"
  },
  "mi_state": "pending",
  "validation": {
    "status": "passed",
    "pass_count": 19,
    "fail_count": 0
  }
}
```

---

## 17. Backend Implementation Notes

### 17.1 Start simple
A practical first backend can begin with:
- JSON-backed queue/state for early prototype
- SQLite or Postgres for real app backend
- service layer wrapping existing scripts

### 17.2 Script integration
The API should not reimplement all image logic immediately.
Instead, it should orchestrate:
- `discover.sh`
- `build.sh`
- `publish.sh`
- `distribute.sh`

### 17.3 Future evolution
Later, script execution can migrate into a proper job runner or worker system.

---

## 18. Suggested Implementation Order

1. auth/session endpoints
2. `GET /api/auth/me`
3. roles/owner endpoints
4. publish queue endpoints
5. build run endpoints
6. validation endpoints
7. audit endpoints
8. candidates and vendor endpoints
9. distribution endpoints
10. policy/settings endpoints

Reason:
- matches the most important UI pages first
- supports approval loop early
- builds around the current repo reality

---

## 19. Summary

The backend should be:
- ownership-aware
- role-aware
- approval-centric
- script-orchestrating rather than script-replacing at first
- fully auditable

This gives us a realistic path from the current repo-based prototype to a proper internal product without throwing away the work already done.
