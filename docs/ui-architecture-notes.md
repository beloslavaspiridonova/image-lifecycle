# UI Architecture Notes

**Date:** 2026-04-16  
**Status:** Early design notes  
**Author:** Ellie

---

## 1. Goal

The CloudSigma Image Lifecycle UI should feel like an internal operator console, not a customer SaaS product.

It needs to support:
- operational clarity
- approval workflows
- artifact traceability
- role-aware actions
- easy handover to jOPS

---

## 2. Suggested UI Shape

### Primary layout
- Left sidebar navigation
- Main content area with tables + detail panels
- Top status bar with environment, current user, role, and last run state

### Recommended sections
1. Overview
2. Version Candidates
3. Build Runs
4. Validation Results
5. Publish Queue
6. Distribution
7. Audit Log
8. Settings

---

## 3. Screen Intent

### Overview
At-a-glance system health:
- latest discovery run
- latest successful build
- pending approvals
- failed runs
- pending distribution issues
- current owner

### Version Candidates
Shows:
- proposed versions
- discovery source
- classification
- status
- approval state

Actions:
- approve
- reject
- defer
- trigger onboarding/update

### Build Runs
Shows:
- run id
- image version
- source drive
- build VM
- snapshot result
- logs
- duration
- status

### Validation Results
Shows:
- latest test suites
- pass/fail counts
- artifact links
- high-risk failures highlighted

### Publish Queue
Shows:
- request id
- snapshot name
- reviewer
- MI state
- approval state
- distribution readiness

Actions vary by role:
- maintainer: create request
- reviewer: approve/reject/defer
- owner/admin: promote after MI confirmation

### Distribution
Shows:
- ZRH, FRA, SJC, MNL, TYO
- current status per region
- retries
- failure notes

### Audit Log
Append-only operational history:
- who did what
- when
- to which object
- outcome

### Settings
Contains:
- roles and assignments
- owner metadata
- service accounts
- vendor source registry
- policy summary

---

## 4. Role-aware actions

### viewer
- read all relevant status pages
- cannot trigger anything

### maintainer
- can trigger runs
- can inspect artifacts
- can create publish requests
- cannot approve final production release

### reviewer
- can review and approve/defer/reject
- should see dedicated approval inbox widgets

### service_admin
- can manage config, roles, and operations
- cannot transfer ownership

### owner
- can do all of the above
- can transfer ownership
- can see special governance controls

---

## 5. UX Principles

1. Show state transitions clearly
2. Make approval context visible without forcing log diving first
3. Highlight blockers and risky failures prominently
4. Keep ownership/governance actions separate from daily operations
5. Avoid mixing build execution with policy editing on the same screen

---

## 6. Suggested Component Types

- status cards
- queue tables
- region rollout matrix
- build log drawer
- test result summary cards
- approval side panel
- audit timeline
- role badges
- owner badge

---

## 7. Recommended v1 build order

1. Overview
2. Publish Queue
3. Build Runs
4. Validation Results
5. Audit Log
6. Settings / Roles
7. Candidates
8. Distribution

Reason: the operational and approval loop matters most first.

---

## 8. Future extension ideas

- Slack/notification inbox integration
- inline diff review for AI-suggested changes
- ownership transfer modal with confirmation
- retention/cleanup dashboard
- platform matrix view (Intel BIOS / Intel UEFI / ARM UEFI)
- per-image compatibility timeline

---

## 9. Product feeling

This should feel like:
- part CI control room
- part release approval console
- part audit dashboard

Not like a generic CRUD admin panel.
