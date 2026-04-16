# Permissions Matrix

**Date:** 2026-04-16  
**Status:** Draft v1.0  
**Author:** Ellie

---

## 1. Purpose

This matrix makes the lifecycle permission model explicit and implementation-ready.

It should be used by:
- backend authorization checks
- frontend action gating
- documentation and handover
- test planning

---

## 2. Roles

| Role | Meaning |
|---|---|
| `owner` | Singular system owner with top-level governance control |
| `service_admin` | Internal CloudSigma admin/operator |
| `reviewer` | Approval role for publish and AI-suggested changes |
| `maintainer` | Main operational role |
| `viewer` | Read-only role |
| `image-automation` | Service account, not a human role |

---

## 3. Human Action Matrix

| Action | owner | service_admin | reviewer | maintainer | viewer |
|---|---:|---:|---:|---:|---:|
| View overview/dashboard | ✅ | ✅ | ✅ | ✅ | ✅ |
| View candidates | ✅ | ✅ | ✅ | ✅ | ✅ |
| View build runs | ✅ | ✅ | ✅ | ✅ | ✅ |
| View validation results | ✅ | ✅ | ✅ | ✅ | ✅ |
| View publish queue | ✅ | ✅ | ✅ | ✅ | ✅ |
| View distribution status | ✅ | ✅ | ✅ | ✅ | ✅ |
| View audit log | ✅ | ✅ | ✅ | ✅ | ✅ |
| Trigger discovery | ✅ | ✅ | ✅ | ✅ | ❌ |
| Create candidate manually | ✅ | ✅ | ✅ | ✅ | ❌ |
| Approve candidate | ✅ | ✅ | ✅ | ❌ | ❌ |
| Reject candidate | ✅ | ✅ | ✅ | ❌ | ❌ |
| Defer candidate | ✅ | ✅ | ✅ | ❌ | ❌ |
| Trigger build | ✅ | ✅ | ✅ | ✅ | ❌ |
| Retry failed build | ✅ | ✅ | ✅ | ✅ | ❌ |
| View build artifacts/logs | ✅ | ✅ | ✅ | ✅ | ✅ |
| Trigger validation | ✅ | ✅ | ✅ | ✅ | ❌ |
| Rerun validation | ✅ | ✅ | ✅ | ✅ | ❌ |
| Stage publish request | ✅ | ✅ | ✅ | ✅ | ❌ |
| Approve publish request | ✅ | ✅ | ✅ | ❌ | ❌ |
| Reject publish request | ✅ | ✅ | ✅ | ❌ | ❌ |
| Defer publish request | ✅ | ✅ | ✅ | ❌ | ❌ |
| Mark MI completed / promote | ✅ | ✅ | ✅ | ❌ | ❌ |
| Start distribution | ✅ | ✅ | ✅ | ✅ | ❌ |
| Retry failed region | ✅ | ✅ | ✅ | ✅ | ❌ |
| Apply location exception | ✅ | ✅ | ✅ | ❌ | ❌ |
| Initiate rollback | ✅ | ✅ | ✅ | ❌ | ❌ |
| Manage normal role assignments | ✅ | ✅ | ❌ | ❌ | ❌ |
| Manage privileged role assignments | ✅ | ✅ | ❌ | ❌ | ❌ |
| Transfer ownership | ✅ | ❌ | ❌ | ❌ | ❌ |
| Edit policy settings | ✅ | ✅ | ❌ | ❌ | ❌ |
| View settings summary | ✅ | ✅ | ✅ | ❌ | ❌ |

---

## 4. Service Account Matrix

| Action | image-automation |
|---|---:|
| Trigger discovery | ✅ |
| Create candidate automatically | ✅ |
| Trigger build | ✅ |
| Trigger validation | ✅ |
| Stage publish request | ✅ |
| View status | ✅ |
| Approve candidate | ❌ |
| Approve publish request | ❌ |
| Promote publish request | ❌ |
| Transfer ownership | ❌ |
| Manage roles | ❌ |
| Edit policy settings | ❌ |

---

## 5. UI Gating Guidance

### Show as active
If user can perform the action directly.

### Show disabled with explanation
If seeing the action helps users understand the workflow.
Examples:
- maintainer sees approve button disabled with note: "Reviewer or above required"
- reviewer sees transfer ownership hidden or disabled with note: "Owner only"

### Hide completely
For highly privileged governance actions where discoverability is not useful for non-privileged roles.
Examples:
- service account management from viewers
- ownership transfer from non-owner roles

---

## 6. Backend Authorization Guidance

Prefer capability helpers instead of raw role checks everywhere.

Examples:
- `can_view_status(actor)`
- `can_trigger_build(actor)`
- `can_approve_publish(actor)`
- `can_manage_roles(actor)`
- `can_transfer_ownership(actor)`

This reduces drift between backend and frontend.

---

## 7. Special Rules

### Ownership
- only current `owner` can transfer ownership
- `service_admin` does not inherit ownership transfer rights

### Publish
- production publish remains approval-gated
- MI/manual step must remain explicit in workflow state

### Automation
- `image-automation` may prepare work, but never approve risk-bearing steps

### Reviewers
- reviewers can approve or defer operational work, but do not own governance policy by default

---

## 8. Suggested Tests

Authorization tests should cover at least:
- maintainer cannot approve publish
- reviewer can approve publish
- service_admin cannot transfer ownership
- owner can transfer ownership
- viewer cannot trigger build
- automation cannot approve publish

---

## 9. Summary

This matrix is the operational contract for the lifecycle system.
If a UI control or API endpoint contradicts this file, the implementation should be treated as wrong until reviewed.
