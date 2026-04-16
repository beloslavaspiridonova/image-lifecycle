# Approval Flow for AI-Suggested Instruction and Script Changes

**Date:** 2026-04-16  
**Status:** Approved for repository use  
**Author:** Ellie  
**Scope:** AI-suggested changes to instructions, scripts, config, and validation logic in `cloudsigma-image-lifecycle`

---

## 1. Purpose

This document defines how AI-suggested changes are proposed, reviewed, approved, rejected, and activated in the CloudSigma Image Lifecycle system.

The core rule is simple:

**AI may propose. Humans approve. Automation executes only approved changes.**

This applies to:
- instruction files in `instructions/`
- operational scripts in `scripts/`
- validation logic in `tests/`
- supporting config in `vendors/`, `roles/`, and future policy files
- build/publish/distribution behavior that could affect customer-facing images

---

## 2. Why This Exists

The PRD requires that AI-assisted improvements are allowed, but that production-impacting changes must not become active without human approval.

This protects against:
- silent drift in image build logic
- accidental breakage from plausible but wrong automation edits
- unreviewed changes to guest username, cloud-init, SSH, or first-boot behavior
- undocumented script behavior that only exists in generated code

It also preserves the useful part of AI involvement:
- faster gap detection
- draft generation
- compatibility review
- proposal preparation
- repetitive documentation and script scaffolding

---

## 3. In-Scope Change Types

### 3.1 AI may propose changes to
- vendor discovery definitions
- onboarding instructions
- update/finalization instructions
- build scripts
- publish/distribution scripts
- validation tests
- runbooks and audit docs
- structured metadata files used by the lifecycle system

### 3.2 High-risk areas
These always require explicit human approval before use in any active path:
- guest username logic (`cloud` vs `cloudsigma`)
- cloud-init config
- `/usr/bin/cschpw/` migration logic
- SSH key injection behavior
- sudoers or auth changes
- publish/promotion logic
- region distribution logic
- cleanup or deletion behavior
- retention/rollback behavior

---

## 4. Roles

| Role | Can Propose | Can Review | Can Approve | Can Merge/Activate |
|---|---|---|---|---|
| `maintainer` | Yes | Yes | No | No |
| `reviewer` | Yes | Yes | Yes | Yes |
| `service_admin` | Yes | Yes | Yes | Yes |
| `owner` | Yes | Yes | Yes | Yes |
| `image-automation` | Yes, if preconfigured | No | No | Only approved items |
| Ellie (AI) | Yes | Can assist review | No | No |

### Approval authority
- Normal AI-suggested instruction/script changes: `reviewer`, `service_admin`, or `owner`
- Policy-level or security-sensitive changes: prefer `owner` or `service_admin`
- Emergency rollback-related changes: `owner` or `service_admin`, or `reviewer` under emergency policy with audit note

---

## 5. Status Model

AI-suggested changes use the PRD status vocabulary.

| Status | Meaning |
|---|---|
| `draft` | Local working change, not submitted |
| `proposed` | Ready for human review |
| `under-review` | Reviewer is actively assessing it |
| `approved` | Human approved for merge/use |
| `rejected` | Human rejected it |
| `deferred` | Valid idea, postponed |
| `in-progress` | Being implemented/applied after approval |
| `validated` | Passed required checks after merge/apply |
| `failed` | Broke validation or execution |
| `deprecated` | Superseded by a newer approved change |

---

## 6. Standard Workflow

### Step 1 - AI detects a gap or improvement
Examples:
- hardcoded `/home/cloudsigma` path found in a script
- test coverage missing for first-boot SSH validation
- vendor discovery logic missing rejection handling
- build script missing a template or cleanup rule

### Step 2 - AI prepares a proposal
The proposal should include:
- what is changing
- why it is needed
- files affected
- risk level
- expected validation needed
- whether the change is safe for immediate merge after approval

### Step 3 - Proposal is recorded
At minimum, proposals must be visible in version control as one of:
- a git commit not yet merged to the protected branch
- a pull request
- a review-queue JSON entry in a future queue file
- a documented patch bundle attached to a review request

### Step 4 - Human review
Reviewer checks:
- correctness against PRD requirements
- compatibility with cloud-init and CloudSigma behavior
- whether customer-facing behavior changes
- whether tests need updates
- whether docs/runbook also need updates

### Step 5 - Human decision
Reviewer chooses one:
- `approved`
- `rejected`
- `deferred`

The decision must include:
- actor
- timestamp
- short reason
- any required follow-up conditions

### Step 6 - Merge/activate only after approval
Only approved changes may become part of:
- default build flow
- scheduled automation
- production publication path
- active instruction registry

### Step 7 - Validation
After merge/apply, run the appropriate validation:
- docs-only change -> no runtime validation required
- test-only change -> lint/manual review or targeted test
- build/publish/distribution change -> dry-run at minimum
- guest access / cloud-init / SSH changes -> end-to-end VM validation required

---

## 7. Required Review Data for Each Proposal

Every AI-suggested change should capture these fields, either in PR text, review queue entry, or commit note:

```json
{
  "id": "change-uuid-or-slug",
  "type": "instruction|script|test|config|doc",
  "title": "Short human-readable summary",
  "status": "proposed",
  "proposed_by": "ellie-ai",
  "created_at": "2026-04-16T19:00:00Z",
  "risk_level": "low|medium|high",
  "files": ["scripts/build.sh"],
  "reason": "Why the change is needed",
  "validation_required": ["dry-run", "manual-review"],
  "approved_by": null,
  "approved_at": null,
  "rejection_reason": null,
  "notes": "Optional reviewer notes"
}
```

These fields align well with a future `ApprovalRecord` and `AuditEvent` model from the PRD.

---

## 8. Validation Matrix

| Change Type | Example | Minimum Validation Before Active Use |
|---|---|---|
| Docs only | README, runbook text | Human review |
| Instruction text | onboarding/update instruction | Human review + consistency check against scripts |
| Discovery logic | `discover.sh` | Dry-run + candidate file inspection |
| Build logic | `build.sh` | Dry-run + manual execution in test environment |
| Publish logic | future `publish.sh` | Dry-run + guarded manual verification |
| Distribution logic | `distribute.sh` | Dry-run + limited-region test |
| Validation logic | `tests/test-suite.sh` | Run affected tests on target VM |
| Guest access logic | cloud-init / SSH / user model | Fresh boot end-to-end validation |

---

## 9. Guardrails

### 9.1 AI must not do these without approval
- merge its own production-impacting changes by policy
- change the approved guest access model silently
- enable deletion-heavy cleanup behavior without human signoff
- bypass MI/manual publish requirements
- alter approval records after the fact

### 9.2 Automation must not consume unapproved changes
Scheduled or background automation must only use:
- the approved branch
- approved instruction versions
- approved script versions
- approved config/policy files

### 9.3 Review must be explicit for risky changes
A lack of response is not approval.
For high-risk changes, approval should be an explicit reviewer action in git, queue state, or documented signoff.

---

## 10. Minimal v1.0 Operating Model

Until a full review queue exists, use this lightweight model:

1. Ellie prepares a change in git
2. Change is documented in commit message and/or docs
3. Bela reviews the diff
4. Bela approves by instructing merge or by merging herself
5. Only then is the change considered active

This keeps governance simple while still satisfying the PRD requirement.

---

## 11. Planned v1.1 Review Queue

A future review queue should store proposal records in a versioned file, for example:
- `queue/review-items.json`
- `audit/approval-log.jsonl`

Suggested queue item types:
- `vendor-change`
- `version-candidate`
- `instruction-change`
- `script-change`
- `test-change`
- `publish-request`
- `rollback-request`

Suggested queue actions:
- submit
- assign reviewer
- approve
- reject
- defer
- mark validated
- archive

---

## 12. Approval Examples

### Example A - Low risk
AI suggests README clarification for image naming.
- Risk: low
- Reviewer: `image-reviewer`
- Validation: review only
- Outcome: can merge after approval

### Example B - Medium risk
AI updates `discover.sh` to avoid duplicate candidates.
- Risk: medium
- Reviewer: `image-reviewer`
- Validation: `--check` dry-run, inspect JSON outputs
- Outcome: merge after review and dry-run

### Example C - High risk
AI changes first-boot logic affecting SSH login or guest username.
- Risk: high
- Reviewer: prefer `image-admin`
- Validation: fresh VM boot, SSH login test, cloud-init verification, test-suite run
- Outcome: do not activate until end-to-end test passes

---

## 13. Decision

For v1.0 of the CloudSigma Image Lifecycle system:
- AI-assisted changes are allowed and encouraged as proposals
- Human approval is mandatory before production-impacting activation
- Git history is the temporary system of record
- A dedicated review queue should be added in Phase 2

This satisfies the PRD requirement while keeping the process small, auditable, and realistic.
