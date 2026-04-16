# Implementation Roadmap - Next Steps

**Date:** 2026-04-16  
**Status:** Working plan  
**Author:** Ellie

---

## 1. Current Position

The project now has:
- core lifecycle scripts (`discover`, `build`, `publish`, `distribute`)
- test suite
- approval flow
- queue + audit
- CloudSigma-aligned role and ownership model
- UI and backend design docs
- runbook
- Slack notification spec
- first-boot validation design
- first-boot validation script scaffolding

This means the project is past the vague-design stage and is now in implementation-hardening mode.

---

## 2. Highest-Priority Remaining Work

## Priority 1 - Plug in the real image instructions
Waiting on Bela's current tutorials and scripts.

Needed inputs:
- onboarding / installation steps
- update / refresh steps
- cleanup / finalization steps
- publish / MI handoff details
- any required SSH/service account assumptions

Deliverable after input:
- real instruction files in `instructions/`
- script alignment against actual process

---

## Priority 2 - Finish first-boot validation
### Current state
- design doc exists
- script scaffolding exists

### Still needed
- validate actual metadata/key injection path
- confirm whether VM creation from snapshot/drive needs adjustment
- wire it into build -> validation -> publish gate
- expose summary in future UI

Deliverable:
- first-boot validation as an actual release gate

---

## Priority 3 - End-to-end dry run
Run full flow manually:
1. discover
2. approve candidate
3. build
4. validate
5. stage publish request
6. manual MI publish
7. distribute

Deliverable:
- one documented full-cycle rehearsal
- list of friction points and corrections

---

## Priority 4 - Slack notification wiring
### Current state
- spec exists

### Still needed
- channel setup (`#image-lifecycle`)
- routing decisions (channel vs DM)
- actual notification implementation/hooks

Deliverable:
- action-focused notifications, not spam

---

## 3. Strong Candidate Tasks for Tonight / Next Session

### A. Create instruction templates
Files to add:
- `instructions/ubuntu-onboarding-v1.md`
- `instructions/ubuntu-update-v1.md`
- `instructions/ubuntu-finalize-v1.md`

These can be templated now and filled tomorrow.

### B. Integrate first-boot validation into publish gating docs
- update README
- update validation references
- make publish blockers explicit

### C. Add queue item examples
- publish request example
- ownership transfer example
- AI-suggested script change example

### D. Add simple validation helper or wrapper script
A wrapper could run:
- build
- test suite
- first-boot validation
- publish stage creation

---

## 4. Best Next Implementation Sequence

### Step 1
Get Bela's current tutorials/scripts

### Step 2
Convert them into structured instruction files

### Step 3
Align existing scripts with real process details

### Step 4
Run first full-cycle dry run

### Step 5
Patch failures and missing assumptions

### Step 6
Wire Slack and tighten runbook

---

## 5. Success Definition for the Next Milestone

The next milestone is reached when:
- actual image instructions are in repo
- first-boot validation runs against a fresh VM
- one full manual cycle works end-to-end
- reviewer can safely approve with evidence
- manual MI step is cleanly documented and traceable

---

## 6. Notes

Do not spend too much time polishing surfaces before the first-boot and real-process integration are proven.

The riskiest remaining areas are:
- real guest login behavior
- hidden assumptions in Bela's current manual image workflow
- MI/manual publish handoff details

Those are the dragons. Everything else is mammoth carpentry.
