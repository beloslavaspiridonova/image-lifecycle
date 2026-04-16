# RUNBOOK

**Date:** 2026-04-16  
**Status:** Draft v1.0  
**Author:** Ellie

---

## 1. Purpose

This runbook explains how to operate, troubleshoot, and recover the CloudSigma Image Lifecycle system.

Audience:
- Bela
- future jOPS maintainers
- reviewers and service admins

---

## 2. Operating Model

The lifecycle system works in this order:

```text
discover -> candidate review -> build -> validation -> publish request -> manual MI step -> distribution
```

### Human roles
- `owner` - governance and ownership control
- `service_admin` - internal CloudSigma admin/operator
- `reviewer` - approves publish and risky changes
- `maintainer` - operates discovery/build/test/distribution
- `viewer` - read-only

### Automation
- `image-automation` prepares work, but does not approve production steps

---

## 3. Normal Operating Tasks

## 3.1 Check candidate state
- review candidate list
- confirm whether new version should be onboarded or deferred

## 3.2 Trigger a build
- run build flow for approved candidate or manual test target
- verify snapshot output and logs

## 3.3 Review validation
- confirm no critical failures
- pay special attention to first-boot validation once implemented

## 3.4 Create publish request
- stage validated snapshot for human review
- wait for reviewer approval and MI/manual publish step

## 3.5 Distribute
- distribute published image to target regions
- monitor failures and retries

---

## 4. Failure Handling Guide

## 4.1 Discovery failures
### Symptoms
- no new candidates created
- vendor metadata fetch fails
- malformed version candidate data

### Actions
1. inspect discovery log in `logs/`
2. verify vendor metadata URL still works
3. check for parsing drift in upstream vendor pages
4. rerun discovery manually in `--check` mode

### Escalate if
- upstream source changed format significantly
- credentials or network access are failing unexpectedly

---

## 4.2 Build failures
### Symptoms
- drive clone fails
- VM creation fails
- SSH never comes up
- apt or OpenClaw update fails
- snapshot creation fails

### Actions
1. inspect build log
2. inspect CloudSigma API response in the log
3. verify source drive UUID and credentials
4. verify SSH key path exists and matches guest user expectation
5. check whether failure happened before or after VM boot
6. retry once after fixing obvious configuration issues

### Escalate if
- repeated API errors suggest CloudSigma platform issue
- image no longer boots or never becomes reachable

---

## 4.3 Validation failures
### Symptoms
- service checks fail
- model count wrong
- Tailscale state wrong
- cloud-init or guest-user checks fail
- first-boot login fails

### Actions
1. inspect validation summary first
2. identify whether failure is expected in current environment or a real regression
3. inspect test artifact logs
4. if first-boot validation exists, collect cloud-init + SSH artifacts
5. block publish until critical failures are explained or fixed

### Critical blockers
- guest login path broken
- cloud-init datasource missing
- SSH key injection broken
- sudo not working for intended guest user

---

## 4.4 Publish queue problems
### Symptoms
- request stuck in `publish-pending`
- unclear MI state
- reviewer approval missing

### Actions
1. inspect queue item in `queue/review-items.json`
2. confirm reviewer assignment
3. confirm whether MI/manual publish was completed
4. update request using promote flow only after MI confirmation

### Rule
Never pretend the MI step happened if it did not.

---

## 4.5 Distribution failures
### Symptoms
- one or more regions fail to clone/distribute
- rollout stalls in partial state

### Actions
1. inspect distribution log
2. retry failed region once
3. confirm whether failure is transient or repeatable
4. if a region remains broken, document it clearly
5. use approved location exception only if formally justified

---

## 5. Publish / Release Gate

Before production publish, confirm:
- validation status is acceptable
- no critical first-boot issues
- reviewer approved
- MI/manual publish completed
- distribution plan is ready

Do not publish if:
- login path is broken
- guest username migration is partially applied
- `cschpw` scripts still target the wrong user
- reviewer approval is missing

---

## 6. Ownership and Role Rules

### Owner-only
- transfer ownership

### Owner / service_admin
- manage roles and policy
- override in emergencies

### Reviewer
- approve/reject/defer publish and risky changes

### Maintainer
- operate the system
- trigger builds/tests/distribution
- investigate failures

---

## 7. Manual Override Rules

Overrides are allowed, but must be auditable.

Every override should capture:
- actor
- role
- reason
- affected object
- timestamp

Examples:
- publish exception
- location exception
- emergency rollback
- candidate forced to deferred/rejected/approved

---

## 8. Rollback Guidance

If a bad image reaches production:
1. stop further distribution if still in progress
2. identify last known good image/snapshot
3. create rollback request or emergency action record
4. re-promote/distribute known good version
5. record root cause in audit + docs

### Guest-user specific rollback trigger
Rollback immediately if:
- customers cannot SSH using expected user
- first-boot SSH key injection is broken
- cloud-init/cschpw mismatch blocks access

---

## 9. Suggested Daily / Weekly Checks

### Daily
- check pending approvals
- check failed builds
- check failed distribution regions

### Weekly
- review recent audit history
- review stale queued items
- verify retention/cleanup backlog
- confirm owner/reviewer assignments are still correct

---

## 10. Handover Notes for jOPS

When handing this over:
- explain role model first
- explain that maintainer is the working role
- explain that reviewer/owner are approval/governance roles
- explain that manual MI step still exists
- explain first-boot validation importance for `cloud` migration

---

## 11. Reference Files

- `README.md`
- `docs/auth-and-role-model.md`
- `docs/permissions-matrix.md`
- `docs/backend-data-model-and-api.md`
- `docs/ui-wireframes.md`
- `docs/approval-flow-ai-changes.md`
- `queue/review-items.json`
- `audit/approval-log.jsonl`

---

## 12. Summary

The system is safe when:
- operations are repeatable
- approvals are explicit
- audit is complete
- first-boot access is validated
- production steps are never faked

That last one matters more than people admit.
