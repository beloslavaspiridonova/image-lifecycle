# UI Wireframes

**Date:** 2026-04-16  
**Status:** Draft v1.0  
**Author:** Ellie

---

## 1. Purpose

This document translates the Image Lifecycle PRD, role model, and login flow into practical wireframe-style screen definitions.

It is not visual design yet. It is structural UI planning:
- page layout
- information hierarchy
- controls
- role-aware actions
- component priorities

The goal is to make implementation tomorrow much faster once the real tutorials and image-operation flows are plugged in.

---

## 2. Global Shell

### 2.1 Main app layout

```text
+----------------------------------------------------------------------------------+
| Top Bar: Environment | Last cycle state | Search | Notifications | User | Role  |
+----------------------+-----------------------------------------------------------+
| Sidebar              | Main Content Area                                         |
| - Overview           |                                                           |
| - Candidates         |                                                           |
| - Build Runs         |                                                           |
| - Validation         |                                                           |
| - Publish Queue      |                                                           |
| - Distribution       |                                                           |
| - Audit Log          |                                                           |
| - Settings           |                                                           |
+----------------------+-----------------------------------------------------------+
```

### 2.2 Global UI components
- Role badge
- Owner badge
- Status badge (`draft`, `proposed`, `approved`, `failed`, etc.)
- Severity badge (`low`, `medium`, `high`, `critical`)
- Action bar
- Filter bar
- Right-side detail drawer
- Confirmation modal
- Audit event chip list
- Log viewer drawer

### 2.3 Top bar behavior
Left:
- environment label (`dev`, `staging`, `prod-internal` later)
- last successful cycle timestamp
- current overall status

Right:
- pending approvals count
- notification bell
- user avatar/name/email
- role badge
- owner crown badge if applicable
- sign out menu

---

## 3. Login Screen

### 3.1 Layout

```text
+------------------------------------------------------+
| CloudSigma Image Lifecycle                           |
| Internal operator console                            |
|                                                      |
| Email                                                |
| [______________________________________________]     |
|                                                      |
| Password                                             |
| [______________________________________________]     |
|                                                      |
| [ Sign In ]                                          |
|                                                      |
| Future: [ Sign in with SSO ]                         |
+------------------------------------------------------+
```

### 3.2 Notes
- Keep this boring and reliable
- Show error state cleanly
- No lifecycle data should render before auth

### 3.3 Post-login routing
- owner -> Overview + governance summary widgets
- service_admin -> Overview + admin actions enabled
- reviewer -> Overview + approval inbox emphasized
- maintainer -> Overview + run controls emphasized
- viewer -> Overview read-only

---

## 4. Overview Screen

### 4.1 Purpose
One-screen operational summary.

### 4.2 Layout

```text
+----------------------------------------------------------------------------------+
| Overview                                                                         |
| Subtitle: current health of image lifecycle operations                           |
+----------------------------------------------------------------------------------+
| [Card] Latest Discovery | [Card] Latest Build | [Card] Pending Approvals         |
| [Card] Last Validation  | [Card] Distribution | [Card] Current Owner             |
+----------------------------------------------------------------------------------+
| Left: Recent Activity Timeline            | Right: Attention Needed              |
| - build started                           | - pending publish requests           |
| - tests passed                            | - failed build                       |
| - candidate discovered                    | - region distribution failure        |
+----------------------------------------------------------------------------------+
| Bottom: Quick Actions                                                          |
| [Trigger Discovery] [Start Build] [Open Publish Queue] [Open Audit Log]         |
+----------------------------------------------------------------------------------+
```

### 4.3 Components
- Summary cards
- “Attention needed” stack
- Activity feed
- Quick actions row
- Ownership panel

### 4.4 Role behavior
- viewer: cards + feed only
- maintainer: sees discovery/build/test buttons
- reviewer: sees “Open approvals” CTA emphasized
- owner/service_admin: sees settings and governance shortcuts

---

## 5. Candidates Screen

### 5.1 Purpose
Manage discovered vendor versions and onboarding candidates.

### 5.2 Layout

```text
+----------------------------------------------------------------------------------+
| Candidates                                                                       |
| Filters: [status] [vendor] [family] [classification] [search]                   |
+----------------------------------------------------------------------------------+
| Table                                                                            |
| ID | Vendor | Version | Classification | Intake Mode | Status | Reviewer | Date |
|-------------------------------------------------------------------------------  |
| ...                                                                              |
+----------------------------------------------------------------------------------+
| Right Drawer: Candidate Details                                                  |
| - source metadata                                                                |
| - notes                                                                          |
| - linked policy / instruction                                                    |
| - approval history                                                               |
| - actions                                                                        |
+----------------------------------------------------------------------------------+
```

### 5.3 Actions
- maintainer+: inspect, prepare run
- reviewer+: approve / reject / defer
- owner/service_admin: override in exceptional cases

### 5.4 Visual emphasis
- proposed candidates highlighted
- deferred clearly distinct from rejected
- brand-new versions visually separated from refresh-path candidates

---

## 6. Build Runs Screen

### 6.1 Purpose
Operate builds and inspect artifacts.

### 6.2 Layout

```text
+----------------------------------------------------------------------------------+
| Build Runs                                                                       |
| Filters: [status] [version] [date] [actor]                                      |
+----------------------------------------------------------------------------------+
| Table                                                                            |
| Build ID | Image Ver | Source Drive | Snapshot | Result | Duration | Started By  |
|-------------------------------------------------------------------------------  |
| ...                                                                              |
+----------------------------------------------------------------------------------+
| Bottom / Drawer: Build Detail                                                    |
| - build summary JSON                                                             |
| - source drive UUID                                                              |
| - build drive UUID                                                               |
| - build VM UUID                                                                  |
| - snapshot UUID                                                                  |
| - linked validation run                                                          |
| - logs                                                                           |
| - artifacts                                                                      |
+----------------------------------------------------------------------------------+
```

### 6.3 Actions
- maintainer+: trigger build
- maintainer+: retry failed build
- all readers: inspect logs/artifacts

### 6.4 Nice-to-have later
- embedded step timeline:
  - clone drive
  - create VM
  - boot VM
  - provision
  - run tests
  - snapshot
  - stop VM

---

## 7. Validation Screen

### 7.1 Purpose
Help reviewers understand safety quickly.

### 7.2 Layout

```text
+----------------------------------------------------------------------------------+
| Validation                                                                       |
| Filters: [status] [build] [risk] [date]                                          |
+----------------------------------------------------------------------------------+
| Summary Row                                                                      |
| PASS COUNT | FAIL COUNT | HIGH-RISK FAILS | FIRST-BOOT STATUS                    |
+----------------------------------------------------------------------------------+
| Left: Test Group Summary                 | Right: Risk Summary                    |
| - services                               | - cloud-init mismatch                  |
| - guest user                             | - SSH key injection issue              |
| - cloud-init                             | - Tailscale state issue                |
| - OpenClaw config                        | - service not active                   |
| - metadata                               |                                        |
+----------------------------------------------------------------------------------+
| Detailed Results Table                                                           |
| Test Name | Result | Risk | Notes | Artifact                                    |
+----------------------------------------------------------------------------------+
```

### 7.3 Reviewer-first design
This page should answer in under 30 seconds:
- is the image safe enough for staging?
- is login path valid?
- is guest-user model correct?
- are failures expected or dangerous?

### 7.4 Actions
- maintainer+: rerun validation
- reviewer+: mark reviewed / request follow-up
- owner/service_admin: approve exception handling

---

## 8. Publish Queue Screen

### 8.1 Purpose
Manage the human approval and manual MI bridge.

### 8.2 Layout

```text
+----------------------------------------------------------------------------------+
| Publish Queue                                                                    |
| Filters: [approval state] [MI state] [reviewer] [date]                          |
+----------------------------------------------------------------------------------+
| Queue Table                                                                       |
| Request ID | Snapshot | Validation | Reviewer | Approval | MI State | Updated    |
|-------------------------------------------------------------------------------  |
| ...                                                                              |
+----------------------------------------------------------------------------------+
| Right Drawer: Publish Request Detail                                             |
| - linked build                                                                   |
| - linked validation                                                              |
| - approval history                                                               |
| - MI reference                                                                   |
| - region rollout readiness                                                       |
| - notes                                                                          |
| Actions: stage / approve / reject / defer / mark MI complete                     |
+----------------------------------------------------------------------------------+
```

### 8.3 Role behavior
- maintainer: can create staged request
- reviewer: can approve/reject/defer
- service_admin/owner: can do all reviewer actions plus governance override
- viewer: read-only

### 8.4 Key UI requirement
The manual MI requirement must be obvious, not hidden.
A banner or status pill should say:
- “Manual MI publish required”
- “Waiting for Bela review”
- “Ready for distribution after MI confirmation”

---

## 9. Distribution Screen

### 9.1 Purpose
Track rollout across locations.

### 9.2 Layout

```text
+----------------------------------------------------------------------------------+
| Distribution                                                                     |
+----------------------------------------------------------------------------------+
| Rollout Summary Card                                                             |
| Snapshot: openclaw-ubuntu-22.04-2026-04-16                                       |
| Status: PARTIAL / SUCCESS / FAILED                                               |
+----------------------------------------------------------------------------------+
| Region Matrix                                                                    |
| ZRH | FRA | SJC | MNL | TYO                                                      |
|-----|-----|-----|-----|-----                                                     |
| OK  | OK  |RUN  |FAIL |WAIT                                                      |
+----------------------------------------------------------------------------------+
| Region Details Table                                                             |
| Region | Status | Attempts | Last Update | Notes | Actions                       |
+----------------------------------------------------------------------------------+
```

### 9.3 Actions
- maintainer+: start/retry region
- reviewer+: inspect failures and approve exception path
- owner/service_admin: apply location exceptions or emergency stop

### 9.4 Good visual idea
Color-coded world-region cards could work later, but table + matrix is enough for v1.

---

## 10. Audit Log Screen

### 10.1 Purpose
Provide trustworthy operational traceability.

### 10.2 Layout

```text
+----------------------------------------------------------------------------------+
| Audit Log                                                                        |
| Filters: [actor] [role] [action] [object type] [date range] [result]            |
+----------------------------------------------------------------------------------+
| Event Table                                                                       |
| Time | Actor | Role | Action | Object Type | Object ID | Result                  |
|-------------------------------------------------------------------------------  |
| ...                                                                              |
+----------------------------------------------------------------------------------+
| Detail Drawer                                                                    |
| - timestamp                                                                      |
| - actor                                                                          |
| - previous state / new state                                                     |
| - notes                                                                          |
| - related objects                                                                 |
+----------------------------------------------------------------------------------+
```

### 10.3 High-value events
- ownership transfer
- privileged role changes
- publish approval/rejection
- rollback initiation
- policy changes
- failed distribution retries

---

## 11. Settings Screen

### 11.1 Purpose
Governance, role, and system configuration.

### 11.2 Layout

```text
+----------------------------------------------------------------------------------+
| Settings                                                                         |
+----------------------------------------------------------------------------------+
| Tabs: [Roles] [Owner] [Service Accounts] [Policy] [Vendors]                      |
+----------------------------------------------------------------------------------+
| Roles Tab                                                                        |
| Role | Scope | Assigned Users | Key Capabilities                                 |
+----------------------------------------------------------------------------------+
| Owner Tab                                                                        |
| Current Owner | Assigned At | Assigned By | Transfer Ownership                   |
+----------------------------------------------------------------------------------+
| Service Accounts Tab                                                             |
| Name | Type | Capabilities | Status                                              |
+----------------------------------------------------------------------------------+
| Policy Tab                                                                       |
| Approval rules, retention defaults, review constraints                           |
+----------------------------------------------------------------------------------+
```

### 11.3 Role behavior
- owner: full access, including ownership transfer
- service_admin: full except ownership transfer
- reviewer: limited summary only
- maintainer/viewer: normally no settings edit access

### 11.4 Ownership transfer modal

```text
Transfer Ownership
------------------
Current owner: Bela
New owner: [ select user ]
Reason: [ text area ]

[ Cancel ] [ Confirm Transfer ]
```

Require explicit confirmation.

---

## 12. Mobile / Narrow Width Behavior

Not a priority, but minimum expectations:
- sidebar collapses
- tables become stacked cards or horizontally scroll
- approval actions remain accessible
- logs open full screen

This is an internal ops UI, so desktop-first is fine.

---

## 13. Suggested Component Library Needs

Useful reusable components:
- status badge
- role badge
- owner badge
- severity chip
- action menu
- split-pane layout
- filter toolbar
- detail drawer
- log viewer
- timeline list
- region status grid
- approval decision modal

---

## 14. Implementation Priority

### Phase A1 - must have
- Login
- Overview
- Publish Queue
- Validation
- Build Runs

### Phase A2 - strongly recommended
- Audit Log
- Settings / Roles / Owner
- Candidates

### Phase A3 - next
- Distribution
- richer artifacts/log viewer
- notifications center

---

## 15. Summary

The wireframe direction is:
- clear operator shell
- role-aware actions
- fast approval comprehension
- explicit ownership and governance
- desktop-first operational console

This should give us a clean base for actual UI implementation once the final image workflows and tutorials are added.
