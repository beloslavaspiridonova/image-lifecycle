# UI Screen Flow and Login Design

**Date:** 2026-04-16  
**Status:** Draft for v1.0  
**Author:** Ellie

---

## 1. Purpose

This document defines the first practical UI flow for the CloudSigma Image Lifecycle system, tied directly to:
- role hierarchy
- login/authentication
- approval workflows
- operator responsibilities

It is intended as the bridge between the PRD and future implementation.

---

## 2. Design Goals

The UI should make it easy to:
- understand current image lifecycle state quickly
- run operational actions safely
- approve high-risk steps with enough context
- audit who did what
- keep privileged actions visible only to the right people

This should feel like an internal release-ops console, not a customer portal.

---

## 3. Roles in the UI

### owner
- sees all screens and all actions
- can transfer ownership
- can manage privileged role assignments
- can override or approve all lifecycle actions

### service_admin
- sees all operational and governance screens
- can manage most system settings and roles
- cannot transfer ownership

### reviewer
- sees approval queue, publish queue, validation results, audit, and status pages
- can approve/reject/defer publish requests and AI-suggested changes

### maintainer
- sees operational screens
- can trigger discovery, builds, tests, retries, staging, and distribution prep
- cannot approve production publish or governance changes

### viewer
- sees read-only dashboards, logs, queue state, audit summaries, and status
- cannot trigger actions

---

## 4. Login Flow

### 4.1 Entry points
Two auth entry points are expected:

1. **Human UI login**
2. **Automation/API auth**

### 4.2 Human login flow

```text
User opens UI
  -> Login page
  -> enters credentials or uses SSO
  -> backend resolves user identity
  -> backend resolves lifecycle role
  -> user lands on role-appropriate dashboard
```

### 4.3 Human login screen
Fields:
- email
- password
- optional SSO button later

Actions:
- Sign in
- Forgot password (later)
- Sign in with SSO (future)

### 4.4 Post-login behavior by role
- `owner` -> Overview with owner badge + approval summary + settings visibility
- `service_admin` -> Overview with admin tools visible
- `reviewer` -> Approval-focused overview
- `maintainer` -> Operations-focused overview
- `viewer` -> Read-only overview

### 4.5 Automation login flow
Automation does not use the web login screen.
It authenticates through:
- service account token
- API key
- scheduled runner credentials

Automation should be represented in logs as `image-automation`.

---

## 5. Navigation Model

### Primary sidebar navigation
1. Overview
2. Candidates
3. Build Runs
4. Validation
5. Publish Queue
6. Distribution
7. Audit Log
8. Settings

### Top bar
- environment label
- latest cycle state
- signed-in user
- role badge
- owner badge if applicable
- notifications / pending approvals count
- user menu

---

## 6. Screen-by-Screen Flow

## 6.1 Overview

### Purpose
Show the current health of the system in one glance.

### Visible to
- owner
- service_admin
- reviewer
- maintainer
- viewer

### Sections
- latest discovery result
- latest successful build
- latest failed run
- pending approvals
- pending publish requests
- distribution health
- current owner
- open blockers

### Role-aware actions
- maintainer+: trigger discovery, build, tests
- reviewer+: open approval queue
- owner/service_admin: open settings and governance

---

## 6.2 Candidates

### Purpose
Review discovered versions and onboarding/update candidates.

### Visible to
- owner
- service_admin
- reviewer
- maintainer
- viewer (read-only)

### Table columns
- candidate id
- vendor
- family
- version
- classification
- discovered at
- status
- intake mode
- reviewer

### Actions
- maintainer+: inspect candidate
- reviewer+: approve / reject / defer
- maintainer+: trigger onboarding/update after approval

### Detail panel
- source metadata
- risk notes
- linked instruction set
- linked build history

---

## 6.3 Build Runs

### Purpose
Operate and inspect build activity.

### Visible to
- owner
- service_admin
- reviewer
- maintainer
- viewer (read-only)

### Table columns
- build id
- target version
- source drive uuid
- build drive uuid
- build VM uuid
- snapshot name
- result
- duration
- started by
- started at

### Actions
- maintainer+: trigger build
- maintainer+: retry failed build
- all readers: view logs

### Detail drawer
- log stream
- build summary JSON
- artifacts
- linked validation run

---

## 6.4 Validation

### Purpose
Show test evidence clearly enough for reviewers to approve safely.

### Visible to
- owner
- service_admin
- reviewer
- maintainer
- viewer

### Sections
- pass/fail summary
- high-risk failures
- test artifacts
- guest-user/cloud-init checks
- first-boot validation status

### Actions
- maintainer+: rerun tests
- reviewer+: mark reviewed

### Important UX note
Reviewer should not need to read raw logs first to understand whether a build is safe.
The summary must surface:
- service readiness
- login path validity
- cloud-init compatibility
- SSH key injection health

---

## 6.5 Publish Queue

### Purpose
Drive the human approval step and MI/manual handoff.

### Visible to
- owner
- service_admin
- reviewer
- maintainer
- viewer (read-only)

### Table columns
- request id
- snapshot name
- validation status
- reviewer
- approval state
- MI state
- created at
- updated at

### Actions by role
- maintainer: create publish request (`stage`)
- reviewer: approve / reject / defer
- owner/service_admin/reviewer: mark MI completed (`promote`)
- owner/service_admin: override or emergency block

### Detail panel
- linked snapshot
- linked build run
- linked test results
- approval history
- MI reference field
- region distribution readiness

---

## 6.6 Distribution

### Purpose
Track rollout across ZRH, FRA, SJC, MNL, TYO.

### Visible to
- owner
- service_admin
- reviewer
- maintainer
- viewer

### Layout
Use a region matrix or rollout timeline.

### Per-region status
- pending
- running
- succeeded
- failed
- retrying
- excluded by exception

### Actions
- maintainer+: start distribution
- maintainer+: retry region
- reviewer+: review failures
- owner/service_admin: approve exception handling

---

## 6.7 Audit Log

### Purpose
Give trustworthy traceability.

### Visible to
- all read roles

### Filters
- actor
- role
- action
- object type
- object id
- date range
- result

### Important events
- candidate created
- candidate approved/rejected/deferred
- build triggered/completed/failed
- test run started/completed
- publish request created
- publish request approved/rejected/promoted
- distribution started/completed/failed
- role changed
- ownership transferred

---

## 6.8 Settings

### Purpose
Governance, ownership, roles, and system configuration.

### Visible to
- owner
- service_admin
- limited summary for reviewer

### Sections
- owner metadata
- role assignments
- service accounts
- vendor source registry
- approval policy summary
- retention/cleanup policy

### Special actions
- owner only: transfer ownership
- owner/service_admin: manage privileged assignments

---

## 7. Ownership Transfer Flow

### Visible to
- owner only

### Flow
```text
Settings
  -> Ownership
  -> Transfer ownership
  -> choose target user
  -> enter reason
  -> confirm
  -> audit event recorded
  -> owner metadata updated
```

### Safety rules
- must be explicit
- must record actor, previous owner, new owner, reason, timestamp
- should require confirmation dialog

---

## 8. Login-State UX

### Unauthenticated state
- login page only
- no data visible

### Authenticated state
Show the current identity clearly:
- full name / email
- current role
- owner badge if applicable

### Forbidden actions
Prefer one of:
- hide control if user should not even see it
- disable control with tooltip if seeing it helps explain workflow

Example:
- maintainer sees publish row but not active “Approve” button
- viewer sees run status but no “Retry build” button

---

## 9. Suggested First UI Build Order

1. Login page
2. Overview
3. Publish Queue
4. Validation
5. Build Runs
6. Audit Log
7. Settings / Roles / Ownership
8. Candidates
9. Distribution

Reason:
- approval loop matters most first
- review confidence is more important than visual completeness

---

## 10. Future Extensions

- inline review of AI-suggested diffs
- Slack approval links
- role-aware notifications
- retention cleanup dashboard
- platform matrix visualization
- ownership transfer acceptance flow
- SSO integration

---

## 11. Summary

The UI should guide users according to their role:
- maintainer works the system
- reviewer approves the risky parts
- service_admin governs operations
- owner controls top-level authority
- viewer observes without changing state

The login flow should resolve identity first, then role, then show the right actions. The UI should never make users guess what they are allowed to do.
