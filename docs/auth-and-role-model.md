# Auth and Role Model

**Date:** 2026-04-16  
**Status:** Draft for v1.0  
**Author:** Ellie  
**References:** TaaS role hierarchy, OmniSupport RBAC, CloudSigma Image Lifecycle PRD

---

## 1. Purpose

This document defines how authentication, role evaluation, ownership, and operational permissions should work in the CloudSigma Image Lifecycle system.

The design intentionally aligns with CloudSigma patterns already used in TaaS and OmniSupport:
- hierarchical roles
- explicit approval tiers
- auditability
- separation between human roles and automation credentials

---

## 2. Auth Model

### 2.1 Human login
Human operators should authenticate with a normal user account.

Preferred order for v1.x:
1. CloudSigma internal SSO, if available
2. email + password session login
3. optional magic-link or invite flow later

A logged-in user session should resolve to a principal containing at least:
- `user_id`
- `email`
- `role`
- `is_authenticated`
- optional scope metadata

Example:
```json
{
  "user_id": "u_123",
  "email": "beloslava.spiridonova@cloudsigma.com",
  "role": "owner",
  "is_authenticated": true
}
```

### 2.2 Automation login
Automation should authenticate separately from humans.

Recommended mechanism:
- API key or service account token
- scoped to non-approval actions
- identifiable in audit logs as `image-automation`

Automation may:
- run discovery
- trigger builds
- run tests
- create publish requests
- update queue state

Automation may not:
- approve publish
- approve AI changes
- transfer ownership
- change role assignments

### 2.3 Internal admin session
If the future UI uses a framework with `is_staff` or equivalent, it should be treated as an implementation detail, not the source of truth.

The real authorization source should be the resolved lifecycle role:
- `owner`
- `service_admin`
- `reviewer`
- `maintainer`
- `viewer`

---

## 3. Role Hierarchy

The lifecycle system uses this hierarchy:

```text
owner
service_admin
reviewer
maintainer
viewer
```

This is intentionally simpler than TaaS and OmniSupport because Image Lifecycle is a system-internal operations product, not a reseller/customer platform.

### Role meanings

| Role | Meaning |
|---|---|
| `owner` | Singular system owner. May transfer ownership and control privileged governance. |
| `service_admin` | Internal CloudSigma operator with broad operational powers, but cannot transfer ownership. |
| `reviewer` | Human approver for publish requests and AI-suggested changes. |
| `maintainer` | Main operational role. Runs builds, tests, retries, staging, and investigations. |
| `viewer` | Read-only visibility into state, history, and artifacts. |

---

## 4. Ownership Rules

Ownership is not just another normal role assignment.

Rules:
1. There must be exactly one active system owner
2. Only the current owner may transfer ownership
3. Ownership transfer must be audited
4. Ownership transfer should capture actor, target, time, and reason
5. `service_admin` does not imply ownership transfer rights

Ownership metadata is stored separately in `roles/system-owner.json`.

---

## 5. Permission Groups

These groupings mirror the TaaS/OmniSupport pattern of reusable admin sets.

```text
OWNER_ROLES    = owner
ADMIN_ROLES    = owner, service_admin
APPROVER_ROLES = owner, service_admin, reviewer
OPERATOR_ROLES = owner, service_admin, reviewer, maintainer
READ_ROLES     = owner, service_admin, reviewer, maintainer, viewer
```

These should be implemented centrally, not redefined per endpoint or screen.

---

## 6. Capability Model

### Owner-only
- transfer ownership
- assign/remove privileged roles
- change governance policy
- define approval policy
- final override in emergencies

### Admin
- manage normal role assignment
- manage queue/policy/config
- run operational flows
- initiate rollback
- assist with approvals

### Reviewer
- approve publish requests
- approve AI-suggested instruction/script changes
- reject or defer changes
- review test evidence and logs

### Maintainer
- trigger discovery/build/test
- create publish requests
- rerun failed jobs
- inspect logs and artifacts
- prepare staging artifacts

### Viewer
- read-only dashboard, logs, queue, audit, and docs

---

## 7. Audit Requirements

Every privileged action should record:
- `actor_id`
- `actor_email`
- `actor_role`
- `action`
- `object_type`
- `object_id`
- `result`
- `timestamp`
- optional `reason`

This follows the same general direction as TaaS and OmniSupport.

Examples:
- publish request created
- publish approved
- publish rejected
- ownership transferred
- reviewer assigned
- rollback initiated
- role changed

---

## 8. UI Implications

The UI should be role-aware from the beginning.

### 8.1 Minimal screens
- Dashboard
- Version candidates
- Build runs
- Validation results
- Publish queue
- Distribution status
- Audit log
- Role/access management
- Ownership transfer dialog

### 8.2 Role-based visibility
- `viewer` sees status only
- `maintainer` sees operational actions
- `reviewer` sees approval actions
- `service_admin` sees governance and configuration actions
- `owner` sees ownership transfer and privileged settings

### 8.3 UX principle
Do not show destructive or forbidden actions as active controls for users who cannot perform them.
Disabled actions with explanation are fine. Hidden or explained is better than ambiguous.

---

## 9. Recommended Next UI Step

For v1.0, design the UI around a left-nav operator console with these sections:
- Overview
- Candidates
- Builds
- Tests
- Publish Queue
- Distribution
- Audit
- Settings

Top-right user menu should show:
- logged-in identity
- current role
- owner badge if applicable
- sign out

Settings should include:
- roles and assignments
- owner metadata
- service account list
- policy summary

---

## 10. Summary

The Image Lifecycle system should use:
- one explicit owner
- CloudSigma-aligned hierarchical roles
- separate automation credentials
- centralized permission groups
- strong audit trails
- role-aware UI and action gating

This keeps the system understandable for Bela, future jOPS operators, and anyone already familiar with TaaS or OmniSupport.
