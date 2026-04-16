# Slack Notification Spec

**Date:** 2026-04-16  
**Status:** Draft v1.0  
**Author:** Ellie

---

## 1. Purpose

This document defines when the lifecycle system should send Slack notifications, to whom, and with what message shape.

The goal is to notify humans when attention is actually useful, without turning Slack into alarm wallpaper.

---

## 2. Notification Targets

### Primary target
- `#image-lifecycle`

### Direct notifications
- Bela for publish-ready staging items and urgent failures
- later: designated reviewer or jOPS lead

---

## 3. Event Types

## 3.1 Discovery events
### Send when
- a new candidate is discovered
- discovery run fails repeatedly

### Message shape
- vendor
- version
- classification
- next required action

Example:
> New image candidate discovered: Ubuntu 24.04 (brand-new). Review required before onboarding.

---

## 3.2 Build events
### Send when
- build starts (optional, low priority)
- build succeeds
- build fails

### Message shape
- build id
- image version
- snapshot name if created
- result
- link/path to logs

Example:
> Build succeeded for Ubuntu 22.04. Snapshot `openclaw-ubuntu-22.04-2026-04-16-staging` is ready for validation.

---

## 3.3 Validation events
### Send when
- validation passes fully
- validation fails with high/critical issues

### Message shape
- pass/fail counts
- critical blocker summary
- whether publish is blocked

Example:
> Validation failed for Ubuntu 22.04 candidate: 2 critical issues. Publish blocked. See first-boot access summary.

---

## 3.4 Publish queue events
### Send when
- publish request is created
- reviewer approval is needed
- request approved/rejected/deferred
- MI/manual publish still pending after a threshold

### Highest-value message
> Staging image ready for review. Manual MI publish required after approval.

---

## 3.5 Distribution events
### Send when
- distribution starts
- distribution completes successfully
- one or more regions fail after retry

Example:
> Distribution partial: ZRH/FRA/SJC succeeded, MNL failed after retry, TYO pending.

---

## 3.6 Governance events
### Send when
- ownership changes
- privileged role assignment changes
- emergency override or rollback is triggered

These are higher-sensitivity notifications and may be better as direct notifications plus audit entries.

---

## 4. Notification Priority Model

### Low
- build started
- discovery completed with no new findings

### Medium
- candidate discovered
- build succeeded
- publish request created
- distribution started

### High
- build failed
- validation failed with publish blocker
- publish waiting on Bela review
- repeated distribution failure

### Critical
- first-boot login broken
- ownership changed
- emergency rollback triggered

---

## 5. Suggested Message Templates

## 5.1 Publish-ready template
```text
🟡 Image ready for review
Image: Ubuntu 22.04
Snapshot: openclaw-ubuntu-22.04-2026-04-16-staging
Validation: PASS (19/19)
Action: Bela review + manual MI publish required
```

## 5.2 Build failed template
```text
🔴 Build failed
Image: Ubuntu 22.04
Build ID: build_20260416_001
Failure stage: SSH wait timeout
Action: Maintainer investigation required
```

## 5.3 Distribution partial template
```text
🟠 Distribution partial
Snapshot: openclaw-ubuntu-22.04-2026-04-16-staging
Success: ZRH, FRA, SJC
Failed: MNL
Pending: TYO
Action: Retry failed region or approve exception
```

## 5.4 Critical first-boot failure template
```text
🚨 Critical image validation failure
Image: Ubuntu 22.04
Issue: SSH login failed for expected guest user `cloud`
Impact: Publish blocked
Action: Fix cloud-init / cschpw migration before release
```

---

## 6. Delivery Rules

### Channel messages
Use for:
- normal pipeline state
- shared awareness
- distribution status

### Direct messages to Bela / reviewer
Use for:
- publish-ready approval request
- urgent validation blocker
- ownership or governance change

---

## 7. Noise Control Rules

Do not send Slack for every tiny state change.

### Avoid notifying for
- routine success with no action needed, if channel gets noisy
- repeated retries unless the issue persists
- low-value debug transitions

### Always notify for
- approval-needed publish request
- critical first-boot validation failure
- build failure that blocks pipeline
- distribution failure after retry
- ownership transfer

---

## 8. Future Integration Notes

Once Slack is wired in:
- channel notifications can map to `#image-lifecycle`
- direct reviewer pings can go to Bela
- messages should link back to relevant UI pages later

---

## 9. Summary

Slack should function as:
- action prompt
- blocker alert
- release visibility tool

Not as a live firehose of every internal event.
