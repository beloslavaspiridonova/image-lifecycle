# CloudSigma Image Lifecycle Management

> **Phase 1 — Foundation**
> Structured repository for managing the full lifecycle of CloudSigma pre-installed OS images: from vendor tracking and build instructions through automated testing, staging, and production publication.

**PRD:** https://csigma.atlassian.net/wiki/spaces/DEV/pages/1806630915/

---

## Project Purpose

CloudSigma offers pre-installed OS images to customers as a convenience — ready-to-use virtual machines with a configured OS, cloud-init integration, and a known-good baseline. Today, these images are created and updated manually. This project establishes the tooling, processes, and governance to:

1. **Track** which OS vendor releases are in scope (Ubuntu LTS initially, others later)
2. **Define** exactly how each image should be built and configured (instruction registry)
3. **Automate** the build, update, and test cycle where possible
4. **Govern** changes with clear roles, approval workflows, and an audit trail
5. **Publish** images reliably to the CloudSigma Marketplace (MI platform)

The end state is a weekly automated cycle: detect new upstream OS releases or security updates → build candidate image → run tests → human approves → publish to production. Until automation is fully in place, this repo also documents and governs the manual process.

---

## Folder Structure

```
cloudsigma-image-lifecycle/
├── README.md              ← You are here
├── .gitignore
│
├── vendors/               ← Vendor registry
│   ├── README.md          (coming soon)
│   └── vendors.json       ← Supported OS vendors, versions, architectures
│
├── roles/                 ← Access control definitions
│   └── roles.json         ← Role names, descriptions, current assignments
│
├── instructions/          ← Human-readable build/config specifications
│   └── README.md          ← How the instruction registry works
│
├── scripts/               ← Executable implementations of instructions
│   └── README.md          ← Script governance model
│
├── tests/                 ← Automated tests for scripts and image validation
│
└── logs/                  ← Runtime logs (gitignored)
```

### Directory Descriptions

| Directory | Purpose |
|-----------|---------|
| `vendors/` | Defines which OS vendors and versions are in scope. Each entry describes supported versions, architectures, firmware types, naming conventions, and discovery mode. |
| `roles/` | Defines who can do what. Roles are checked before any action in the automated pipeline. |
| `instructions/` | Versioned, human-readable specifications for each image build/config step. The authoritative "what should be done" — independent of how. |
| `scripts/` | Bash scripts that implement approved instructions. Must be idempotent, tested, and reference their instruction. |
| `tests/` | Test cases for scripts and image validation checks (e.g., cloud-init fires correctly, guest user exists, SSH config is correct). |
| `logs/` | Runtime logs from build/test runs. Gitignored — kept locally or shipped to log storage. |

---

## Current Manual Image Creation Process

> This section documents the current (pre-automation) process as understood. It will be updated as we formalize and automate each step.

### Overview

New CloudSigma pre-installed images are currently created manually by the ops team. The general process is:

1. **Clone the base VM** — Start from the most recent known-good pre-installed image (or a fresh Ubuntu cloud image if building from scratch). Clone it in the CloudSigma control panel.
2. **Boot and connect** — Start the cloned VM, connect via SSH or VNC.
3. **Run updates** — Execute `sudo apt update && sudo apt upgrade -y` (and any other required configuration steps) inside the VM.
4. **Verify** — Manually verify that cloud-init, SSH, and other critical services work as expected.
5. **Snapshot** — Take a snapshot of the VM disk via the CloudSigma control panel.
6. **Publish via MI** — Log into the Market Images (MI) platform, upload/register the snapshot as a new public image. This step requires **2FA** authentication.
7. **Test** — Verify the published image boots correctly and cloud-init runs as expected.
8. **Announce** — Notify the team that a new image version is available.

### Known Pain Points

- No automated testing — verification is manual and inconsistent
- No audit trail for what changed between image versions
- 2FA requirement for MI publication means it cannot be fully automated without additional tooling
- Guest username inconsistency (see migration plan below)
- No defined cadence — updates happen reactively, not on a schedule

---

## Guest Username Migration Plan

### Background

CloudSigma pre-installed images historically used **`cloudsigma`** as the default guest username. This is being migrated to **`cloud`** — a shorter, cleaner name that is less vendor-specific and aligns better with cloud-init conventions.

### Current State

- Existing images: guest user is `cloudsigma`
- New images being built: guest user is `cloud`
- `vendors.json` reflects `"default_guest_username": "cloud"` as the target

### Migration Plan

| Stage | Action |
|-------|--------|
| **New images** | Use `cloud` as the default guest username from now on |
| **Documentation** | Update all references in instructions and scripts to use `cloud` |
| **Customer notice** | Communicate the change in release notes when the new image is published |
| **Legacy images** | Existing images with `cloudsigma` user remain available; not retroactively changed |
| **cloud-init** | Ensure cloud-init `default_user` is set to `cloud` in all new image configurations |

> **Note:** The cloud-init datasource for all CloudSigma images is `CloudSigma`. This must be configured correctly in `/etc/cloud/cloud.cfg` for cloud-init to work on the platform.

---

## Roles & Access Control

Roles are defined in `roles/roles.json`. Summary:

| Role | Description |
|------|-------------|
| `image-admin` | Full access — approve, publish, rollback, manage all config |
| `image-reviewer` | Review STAGING images, approve PRODUCTION, approve AI-suggested changes |
| `image-maintainer` | Run updates manually, trigger tests, manage candidates, propose changes |
| `image-automation` | CI/CD service account — scheduled runs, create candidates, execute tests |
| `image-editor` | Edit vendor/instruction/script definitions (subject to approval) |
| `image-viewer` | Read-only access to status, results, history |

---

## Quick Start for Operators

### Prerequisites

- Access to the CloudSigma control panel
- SSH key configured for the build VMs
- Access to the MI (Market Images) platform with 2FA device
- Git installed locally; clone this repo

### Trigger a Manual Image Update

1. Review `vendors/vendors.json` to confirm the target version and architecture
2. Read the relevant instructions in `instructions/` for the image type you're building
3. Clone the base VM in the CloudSigma control panel
4. SSH into the cloned VM and run the approved scripts from `scripts/` in order
5. Run tests from `tests/` against the VM before snapshotting
6. Take a snapshot via the control panel
7. Log into MI (with 2FA), register the snapshot as a new image
8. Verify the published image boots and cloud-init runs correctly
9. Update `logs/` with a build record (format TBD in Phase 2)
10. Open a PR to update any instruction/script versions if changes were made

### Propose a Change to an Instruction or Script

1. Create a branch: `git checkout -b propose/my-change`
2. Edit the relevant file in `instructions/` or `scripts/`
3. Update the version and status fields in the file header
4. Open a PR — an `image-reviewer` or `image-admin` must approve before merge
5. Do not run unapproved scripts in staging or production

---

## Roadmap

- **Phase 1 (current):** Repo structure, vendor/role/instruction registry, document manual process
- **Phase 2:** Formalize instruction and script library for Ubuntu LTS; automated test suite
- **Phase 3:** Automated build pipeline (CI/CD); candidate lifecycle (DRAFT → STAGING → PRODUCTION)
- **Phase 4:** Automated discovery of upstream releases; weekly build cadence

---

## References

- **PRD:** https://csigma.atlassian.net/wiki/spaces/DEV/pages/1806630915/
- **Ubuntu Cloud Images:** https://cloud-images.ubuntu.com/
- **CloudSigma cloud-init datasource:** https://cloudinit.readthedocs.io/en/latest/reference/datasources/cloudsigma.html
