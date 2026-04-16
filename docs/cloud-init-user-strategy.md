# cloud-init User Strategy

**Date:** 2026-04-16
**Status:** Approved for Phase 1

---

## Current State

cloud.cfg default_user on existing production images:
```yaml
default_user:
  name: cloudsigma
  lock_passwd: False
  gecos: Cloudsigma
  groups: [adm, cdrom, sudo, dip, plugdev, lxd]
  sudo: ["ALL=(ALL) NOPASSWD:ALL"]
  shell: /bin/bash
```

---

## Target State (New Images)

```yaml
default_user:
  name: cloud
  lock_passwd: False
  gecos: CloudSigma
  groups: [adm, cdrom, sudo, dip, plugdev, lxd]
  sudo: ["ALL=(ALL) NOPASSWD:ALL"]
  shell: /bin/bash
```

The only change: `name: cloudsigma` -> `name: cloud`

---

## Why `cloud`?

- Cleaner, less provider-branded - customers feel it's their machine
- Standard-looking (similar to `ubuntu`, `ec2-user`, `debian`)
- Short, easy to type
- Not tied to "CloudSigma" branding in the guest OS

---

## cloud-init Datasource

CloudSigma uses its own cloud-init datasource. The datasource handles:
- SSH key injection from user-data
- Hostname setup from server context
- Metadata processing on first boot

This is configured in `/etc/cloud/cloud.cfg`:
```yaml
datasource_list: [CloudSigma, None]
```

Or via `/etc/cloud/cloud.cfg.d/90_dpkg.cfg`.

---

## SSH Key Injection

cloud-init injects SSH keys from the CloudSigma server context into:
```
/home/cloud/.ssh/authorized_keys
```

This happens automatically via the `users` and `ssh` modules. No change needed for the key injection mechanism - only the target username changes.

---

## Migration Policy

| Image Type | Username | Timeline |
|---|---|---|
| Existing published library images | cloudsigma | Retain until migration validated |
| New images built with this repo | cloud | Immediately from Phase 1 |
| Production rollout | cloud | After Phase 1 testing complete |

---

## Risk: Compatibility

Any component that assumes `/home/cloudsigma` or runs as the `cloudsigma` user must be updated before production:

- OpenClaw systemd service (ExecStart user)
- webchat-ui systemd service (WorkingDirectory)
- Any cron jobs
- Any scripts in the image that reference `/home/cloudsigma`

This is tracked in `docs/cloudsigma-username-audit.md`.

---

## Dual-User Option

If full migration introduces risk in v1.0, we can temporarily create BOTH users:
- `cloud` as default login user
- `cloudsigma` as a legacy symlink or alias

This avoids breaking existing automation while new images are validated.
Decision: start with `cloud` only in new images; keep `cloudsigma` in existing.
