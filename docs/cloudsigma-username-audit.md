# CloudSigma Username Audit Report

**Date:** 2026-04-16
**Audited by:** Ellie (automated audit of current production image)
**Purpose:** Find all hardcoded `cloudsigma` username/path references before migrating to `cloud` user

---

## Current State

- **Guest user:** `cloudsigma` (uid=1000, gid=1000)
- **Home dir:** `/home/cloudsigma`
- **Groups:** cloudsigma, adm, cdrom, sudo, dip, plugdev, lxd
- **`cloud` user:** Does NOT exist yet

---

## Findings

### 1. /etc/passwd
| Finding | Risk | Action |
|---|---|---|
| `cloudsigma:x:1000:1000:cloudsigma:/home/cloudsigma:/bin/bash` | HIGH | Create `cloud` user, migrate home dir or create new |

### 2. /etc/cloud/cloud.cfg - default_user
| Finding | Risk | Action |
|---|---|---|
| `default_user.name: cloudsigma` | HIGH | Change to `cloud` in new image builds |
| `default_user.gecos: Cloudsigma` | LOW | Update to `cloud` |

This is the most critical change - cloud-init reads this to create the default user on first boot.

### 3. /etc/systemd/system/openvpn-ellie.service
| Finding | Risk | Action |
|---|---|---|
| `WorkingDirectory=/home/cloudsigma/vpn` | HIGH | Update path to `/home/cloud/vpn` after migration |
| `ExecStart=... --config /home/cloudsigma/vpn/...` | HIGH | Update path |

**Note:** This is Ellie's VPN service, not a customer-facing service. Still needs updating.

### 4. OpenClaw Installation
| Finding | Risk | Action |
|---|---|---|
| OpenClaw installed at `/home/cloudsigma/.openclaw/` | HIGH | New images use `/home/cloud/.openclaw/` |
| All workspace files under `/home/cloudsigma/.openclaw/workspace/` | HIGH | Path changes in new image |
| openclaw.json at `/home/cloudsigma/.openclaw/openclaw.json` | HIGH | Path changes |

### 5. /home/ directory
| Finding | Risk | Action |
|---|---|---|
| `/home/cloudsigma/` exists with full user content | HIGH | New images provision `/home/cloud/` instead |
| `/home/ubuntu/` also exists | LOW | Standard Ubuntu cloud image remnant |

---

## Migration Complexity: MEDIUM

The migration is straightforward but touches several critical paths:

1. **cloud.cfg** - change default_user.name (1 file, 1 line)
2. **systemd services** - update paths (1 service currently)
3. **New image provisioning** - create `cloud` user instead of `cloudsigma`
4. **OpenClaw install scripts** - must target `/home/cloud/` not `/home/cloudsigma/`

---

## Recommended Migration Steps for New Images

1. In `/etc/cloud/cloud.cfg`, set `default_user.name: cloud`
2. Provision OpenClaw to `/home/cloud/.openclaw/`
3. Update any service files to use `/home/cloud/` paths
4. Test cloud-init first-boot with `cloud` user
5. Verify SSH key injection lands in `/home/cloud/.ssh/authorized_keys`
6. Keep `cloudsigma` user in existing published images until v1.0 is stable

---

## Compatibility Note

Existing published images in the library retain `cloudsigma`. This is acceptable during migration.
New images built with this repo use `cloud`.
No customer-facing scripts should hardcode either username - they should use cloud-init metadata.
