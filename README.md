# CloudSigma Image Lifecycle Management

**Status:** Phase 1 - Foundation
**PRD:** https://csigma.atlassian.net/wiki/spaces/DEV/pages/1806630915/CloudSigma+Image+Lifecycle+Management+PRD
**Owner:** Beloslava Spiridonova (Bela)
**AI Maintainer:** Ellie

---

## Purpose

This repo automates the full lifecycle of CloudSigma pre-installed VM images:

1. **Discover** - detect new upstream OS versions
2. **Build** - clone base VM, run updates, configure software
3. **Test** - run 19-test validation suite before any promotion
4. **Stage** - promote to STAGING for human review
5. **Approve** - Bela reviews and approves via MI (2FA required)
6. **Distribute** - push to all 5 CloudSigma regions: ZRH, FRA, SJC, MNL, TYO

Without this system, image maintenance is entirely manual, images go stale, and there are no test gates before customer delivery.

---

## Folder Structure

```
cloudsigma-image-lifecycle/
├── vendors/          - Vendor definitions (vendors.json) - approved upstream sources
├── roles/            - Role assignments (roles.json)
├── instructions/     - Onboarding and update instructions per image family
├── scripts/          - Scripts run inside the guest image during build/update
├── tests/            - test-suite.sh and test documentation
├── docs/             - Architecture docs, audit reports, runbooks
├── logs/             - Test results and run logs (gitignored)
└── README.md         - This file
```

---

## Current Manual Image Creation Process

Today, creating a CloudSigma pre-installed image works like this:

1. Start from an existing base Ubuntu VM
2. SSH in and run `apt update && apt upgrade -y`
3. Install/update OpenClaw manually
4. Verify webchat-ui service is running
5. Check TaaS config has >=10 models
6. Verify Tailscale is installed but NOT logged in
7. Place BOOTSTRAP.md at /home/cloudsigma/.openclaw/workspace/
8. Snapshot the VM
9. Log into the MI (Management Interface) - requires 2FA
10. Publish the snapshot as a library drive
11. Manually distribute to each region

**Problems:** No automation, no tests, single person dependency (Bela for 2FA), no version history, no rollback.

---

## Guest Username Migration

CloudSigma images are migrating from the `cloudsigma` default guest username to `cloud`.

- **Current:** default guest user is `cloudsigma`
- **Target:** default guest user is `cloud`
- **Strategy:** New images built with this repo use `cloud`. Existing published images retain `cloudsigma` until migration is validated.
- **cloud-init:** Remains the source of truth for first-boot user provisioning, SSH key injection, hostname setup.

See `docs/cloud-init-user-strategy.md` for full details.

---

## Supported Platforms

| Architecture | Firmware | Support Level |
|---|---|---|
| Intel x86_64 | BIOS | Legacy - supported, avoid for new images |
| Intel x86_64 | UEFI | Primary - default for new Intel images |
| ARM aarch64 | UEFI | Primary - only supported ARM path |

---

## Quick Start (Operator)

### Run the test suite against a VM:
```bash
# SSH into the target VM first, then:
sudo bash tests/test-suite.sh

# Verbose output:
sudo bash tests/test-suite.sh --verbose

# Single test:
sudo bash tests/test-suite.sh --test=openclaw_service_running
```

### Check vendor definitions:
```bash
cat vendors/vendors.json
```

### Check roles:
```bash
cat roles/roles.json
```

---

## Roles

| Role | Who | Permissions |
|---|---|---|
| image-admin | Bela | Full access: approve, publish, rollback, manage everything |
| image-reviewer | Bela (initially), jOPS lead later | Review STAGING, approve PRODUCTION |
| image-maintainer | Bela + Ellie + jOPS | Run updates, trigger tests, propose changes |
| image-automation | CI/CD service account | Scheduled runs, candidate creation, test execution |
| image-editor | Selected team | Edit vendor defs and instructions (with approval) |
| image-viewer | Any team member | Read-only access |

---

## Image Naming Convention

```
openclaw-ubuntu-{version}-{YYYY-MM-DD}
```

Example: `openclaw-ubuntu-22.04-2026-04-16`

---

## Links

- **PRD:** https://csigma.atlassian.net/wiki/spaces/DEV/pages/1806630915/
- **CloudSigma API Docs:** https://docs.cloudsigma.com/en/latest/
- **OpenClaw:** https://openclaw.ai
