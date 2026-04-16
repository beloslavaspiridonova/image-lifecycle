# First-Boot Validation Design

**Date:** 2026-04-16  
**Status:** Draft v1.0  
**Author:** Ellie

---

## 1. Purpose

This document defines the validation path required to prove that a freshly built CloudSigma image actually works on first boot.

This is the most critical open validation gap because the image lifecycle project is changing guest-user behavior from `cloudsigma` to `cloud`, and because CloudSigma relies on both:
- cloud-init
- proprietary `/usr/bin/cschpw/` first-boot scripts

A build that passes package/service checks but fails first-boot login is still a broken image.

---

## 2. What Must Be Proven

A first-boot validation run must prove all of the following on a fresh VM created from the candidate image:

1. VM boots successfully
2. cloud-init runs successfully
3. CloudSigma datasource is active
4. intended guest user exists (`cloud` for new images)
5. guest home directory exists and is owned correctly
6. SSH public key injection succeeds
7. SSH login works using injected key
8. sudo-capable access works for the guest user
9. hostname and metadata processing work as expected
10. first-boot infrastructure does not silently target `cloudsigma` paths when the image is meant to use `cloud`

---

## 3. Why This Needs a Separate Path

The existing test suite checks system state on a machine where tests are executed.
That is useful, but not enough.

It does **not** prove the full first-boot lifecycle from image -> new VM -> metadata -> SSH access.

This path needs a dedicated validation flow because the failure modes are different:
- image boots but SSH keys go to `/home/cloudsigma/.ssh/` instead of `/home/cloud/.ssh/`
- `cloud.cfg` creates `cloud` but `cschpw` still edits `cloudsigma`
- sudoers entry is mismatched to the new username
- metadata path works partially but login path is broken

---

## 4. Proposed Validation Flow

```text
1. Build candidate image snapshot
2. Create a fresh validation VM from that snapshot
3. Inject a known test SSH public key via CloudSigma metadata path
4. Boot the VM
5. Wait for first boot + cloud-init completion
6. Verify guest user exists
7. Verify authorized_keys was created in the expected home
8. SSH in using the matching private key
9. Verify sudo access
10. Run targeted first-boot checks on the VM
11. Capture logs and artifacts
12. Destroy or stop the validation VM
```

---

## 5. Validation Inputs

### Required inputs
- candidate image snapshot UUID
- expected guest username (`cloud` or legacy `cloudsigma`)
- test SSH keypair dedicated to validation
- API credentials for VM creation
- timeout settings

### Recommended inputs
- expected hostname pattern
- expected platform variant (Intel BIOS / Intel UEFI / ARM UEFI)
- validation run id for traceability

---

## 6. First-Boot Checks

## 6.1 Boot-level checks
- VM reaches running state
- network comes up
- instance obtains reachable IP

## 6.2 cloud-init checks
- `cloud-init status --wait` completes successfully
- `/etc/cloud/cloud.cfg` contains expected default user
- datasource reports CloudSigma
- no critical cloud-init errors in logs

## 6.3 Guest-user checks
- expected guest user exists
- expected guest uid/home/shell are correct
- home directory ownership is correct
- `.ssh/authorized_keys` exists in expected home

## 6.4 cschpw compatibility checks
- `/usr/bin/cschpw/ssh_meta.sh` points at the correct home path
- `/usr/bin/cschpw/auth_ssh.sh` path and sudoers handling match the expected user
- `/usr/bin/cschpw/di_ch.sh` and `/usr/bin/cschpw/en_ch.sh` target the expected user

## 6.5 SSH access checks
- SSH reachable with validation key
- login succeeds as expected guest user
- wrong legacy user login is rejected where appropriate

## 6.6 Privilege checks
- `sudo -n true` succeeds
- `id` shows expected group membership

## 6.7 Metadata and hostname checks
- hostname applied correctly
- metadata-dependent provisioning completed

---

## 7. Suggested Implementation Shape

## 7.1 New script
Add a dedicated script, likely:
- `scripts/first-boot-validate.sh`

### Responsibilities
- create validation VM from snapshot
- inject test key
- wait for boot/cloud-init
- verify SSH path
- run remote checks
- emit JSON summary + log paths

## 7.2 Test output
The script should emit:
- validation status
- validation VM UUID
- validation VM IP
- expected user
- SSH status
- sudo status
- cloud-init status
- first-boot artifact paths

---

## 8. Integration with Existing Test Suite

There are two good options:

### Option A - separate validation stage
- keep current `tests/test-suite.sh`
- add first-boot validation as a separate pipeline stage

### Option B - invoke test suite remotely after login succeeds
- first-boot script gets SSH access
- then triggers a subset of `test-suite.sh` remotely

### Recommendation
Use **both**:
1. first-boot validation proves login path works
2. existing test suite runs targeted checks after login

That gives better coverage with less duplication.

---

## 9. New Result Categories

Suggested first-boot validation result fields:
- `boot_ok`
- `cloud_init_ok`
- `datasource_ok`
- `guest_user_ok`
- `ssh_key_injection_ok`
- `ssh_login_ok`
- `sudo_ok`
- `hostname_ok`
- `legacy_path_leak_detected`

---

## 10. Failure Classification

### Critical failures
Any of these should block publish immediately:
- VM never becomes reachable
- cloud-init fails
- expected guest user missing
- authorized_keys missing in expected home
- SSH login fails with injected key
- sudo fails for expected guest user

### High-risk failures
- legacy `cloudsigma` path still used in `cschpw`
- hostname/metadata drift
- ownership or permissions wrong in guest home

### Medium-risk failures
- extra legacy artifacts exist but login path still works
- warning-only cloud-init log noise

---

## 11. Artifacts to Capture

From the validation VM, collect:
- `/var/log/cloud-init.log`
- `/var/log/cloud-init-output.log`
- `/etc/cloud/cloud.cfg`
- copies or excerpts of `/usr/bin/cschpw/*.sh`
- `id <user>` output
- `ls -la /home/<user>/.ssh`
- remote command transcript
- validation JSON summary

These should be attached to the validation run if possible.

---

## 12. Timeouts

Suggested defaults:
- VM boot reachability: 5 minutes
- cloud-init completion: 5 minutes after reachability
- SSH availability: 5 minutes
- total first-boot validation budget: 15 minutes

These can be adjusted later per platform.

---

## 13. Role and Approval Implications

### Maintainer
- can trigger first-boot validation
- can inspect failed artifacts

### Reviewer
- must see first-boot summary before approving publish

### Owner / service_admin
- can approve exceptions only if risk is acceptable and documented

---

## 14. Recommended Next Implementation Step

Implement:
1. `scripts/first-boot-validate.sh`
2. result artifact path under `logs/`
3. a first-boot summary section in validation UI
4. publish gating rule: `ssh_login_ok` and `sudo_ok` must be true for new images

---

## 15. Summary

The first-boot validation path is the missing proof that a freshly published image is actually usable by a customer.

Without this, the project can validate packages and services while still shipping an image with a broken login path.

That is why this path should be treated as a release gate, not a nice-to-have.
