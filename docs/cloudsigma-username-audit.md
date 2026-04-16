# CloudSigma Username Audit Report

**Date:** 2026-04-16  
**Audited by:** Ellie (automated audit — subagent `image-lifecycle-audit`)  
**Machine:** EllieDONOTSTOPORDELETE (CloudSigma pre-installed production image)  
**Purpose:** Identify every location where `cloudsigma` appears as a username, path, or service reference before migrating guest VMs to the `cloud` username.

---

## Summary

| Risk Level | Count | Areas |
|---|---|---|
| **HIGH** | 7 | cschpw scripts, cloud.cfg, openvpn service, /etc/passwd, /etc/group sudoers |
| **MEDIUM** | 4 | OpenClaw install path, workspace scripts, .bashrc, webchat-ui service |
| **LOW** | 3 | Workspace docs, comments, GECOS field |

**Overall Migration Complexity: MEDIUM-HIGH**  
The critical blocker is `/usr/bin/cschpw/` — CloudSigma's own first-boot infrastructure scripts. These are **deeply hardcoded** to `cloudsigma` and control SSH key injection, password auth, and user setup. These must be updated before any image migration.

---

## Findings

### 1. `/etc/passwd` — User Entry

```
cloudsigma:x:1000:1000:cloudsigma:/home/cloudsigma:/bin/bash
```

| | |
|---|---|
| **Risk** | HIGH |
| **Impact** | Primary user account. All processes run as this user. |
| **Action** | New images: provision `cloud` user (uid=1000) instead. Existing images: no change. |

---

### 2. `/etc/group` — Group Memberships

```
adm:x:4:syslog,cloudsigma,ubuntu
cdrom:x:24:cloudsigma,ubuntu
sudo:x:27:cloudsigma,ubuntu
dip:x:30:cloudsigma,ubuntu
plugdev:x:46:cloudsigma
lxd:x:101:cloudsigma,ubuntu
cloudsigma:x:1000:
```

| | |
|---|---|
| **Risk** | HIGH |
| **Impact** | `cloudsigma` has sudo, adm, lxd group membership. Missing this in new user = loss of privileges. |
| **Action** | In new images, add `cloud` to same groups: `adm, cdrom, sudo, dip, plugdev, lxd`. The `cloudsigma` primary group becomes `cloud:x:1000:`. |

---

### 3. `/etc/cloud/cloud.cfg` — Default User

```yaml
default_user:
  name: cloudsigma
  lock_passwd: False
  gecos: Cloudsigma
  groups: [adm, cdrom, dip, lxd, sudo]
  shell: /bin/bash
```

| | |
|---|---|
| **Risk** | HIGH |
| **Impact** | This is what creates the guest user on every first boot. Change `name` here and the user changes everywhere cloud-init runs. |
| **Action** | Change `name: cloudsigma` → `name: cloud` and `gecos: Cloudsigma` → `gecos: CloudSigma Guest` in new image builds. |

---

### 4. `/usr/bin/cschpw/ssh_meta.sh` — SSH Key Injection ⚠️ CRITICAL

```bash
rm /home/cloudsigma/.ssh/authorized_keys
touch /home/cloudsigma/.ssh/authorized_keys
echo $s | grep -oP '...' > /home/cloudsigma/.ssh/authorized_keys
echo $s | grep -oP '...' >> /home/cloudsigma/.ssh/authorized_keys
chmod 600 /home/cloudsigma/.ssh/authorized_keys
chown -R cloudsigma:cloudsigma /home/cloudsigma
```

| | |
|---|---|
| **Risk** | **HIGH** — This is the SSH key injection mechanism |
| **Impact** | If user is renamed to `cloud` but this script isn't updated, SSH keys are written to the wrong path → customers cannot log in |
| **Action** | Update all 5 path/ownership references: `/home/cloudsigma` → `/home/cloud`, `cloudsigma:cloudsigma` → `cloud:cloud` |

---

### 5. `/usr/bin/cschpw/auth_ssh.sh` — SSH Auth Manager ⚠️ CRITICAL

```bash
ls -l /home/cloudsigma/.ssh/authorized_keys   # checks key file
sed -i 's|cloudsigma ALL=(ALL) NOPASSWD:ALL|cloudsigma ALL=(ALL) ALL|g' /etc/sudoers.d/90-cloud-init-users
```

| | |
|---|---|
| **Risk** | HIGH |
| **Impact** | Checks if authorized_keys exists and has content; modifies sudoers. Wrong path = wrong auth behavior. Wrong username in sed = sudoers not updated correctly. |
| **Action** | Update `/home/cloudsigma` → `/home/cloud` in path check; update `cloudsigma ALL=...` → `cloud ALL=...` in sed commands |

---

### 6. `/usr/bin/cschpw/di_ch.sh` — Disable Password Change

```bash
usermod -p '*' cloudsigma
```

| | |
|---|---|
| **Risk** | HIGH |
| **Impact** | Targets wrong user → password lock fails silently |
| **Action** | Update `cloudsigma` → `cloud` |

---

### 7. `/usr/bin/cschpw/en_ch.sh` — Enable Password Change

```bash
chage -d 0 cloudsigma
```

| | |
|---|---|
| **Risk** | HIGH |
| **Impact** | Same as di_ch.sh — targets wrong user |
| **Action** | Update `cloudsigma` → `cloud` |

---

### 8. `/usr/bin/cschpw/global.sh` — Boot Orchestrator

```bash
bash /usr/bin/cschpw/ssh_meta.sh
sh /usr/bin/cschpw/host_key.sh
bash /usr/bin/cschpw/networkscript.sh
```

| | |
|---|---|
| **Risk** | MEDIUM |
| **Impact** | global.sh calls the other scripts but has no direct `cloudsigma` reference. However it gates all the above. Must run last in migration. |
| **Action** | No direct changes needed; but depends on all subscripts being updated. |

---

### 9. `/etc/systemd/system/cloudsigma.service` — Boot Service

```ini
[Unit]
Description=CloudSigma Global Configuration
Wants=cloud-final.service
Before=systemd-user-sessions.service

[Service]
Type=idle
ExecStart=/usr/bin/cschpw/global.sh

[Install]
WantedBy=cloud-init.target
Alias=Cloudsigma
```

| | |
|---|---|
| **Risk** | MEDIUM |
| **Impact** | Service is named `cloudsigma.service` and has `Alias=Cloudsigma`. Functional, but naming is provider-branded. No path changes needed in the unit file itself (paths are in the scripts). |
| **Action** | LOW priority rename. Could become `cs-firstboot.service` in new images for clarity. |

---

### 10. `/etc/systemd/system/openvpn-ellie.service` — OpenVPN Service

```ini
WorkingDirectory=/home/cloudsigma/vpn
ExecStart=/usr/sbin/openvpn --config /home/cloudsigma/vpn/ellie-final.conf ...
```

| | |
|---|---|
| **Risk** | HIGH (for this specific server) |
| **Impact** | This is Ellie's VPN service. Will break if home dir is moved. |
| **Action** | This is server-specific (not baked into new images). Update paths when/if home dir migrates. Not in image build scope. |

---

### 11. OpenClaw Installation at `/home/cloudsigma/.openclaw/`

```
/home/cloudsigma/.openclaw/
/home/cloudsigma/.openclaw/openclaw.json
/home/cloudsigma/.openclaw/workspace/
```

| | |
|---|---|
| **Risk** | MEDIUM |
| **Impact** | All OpenClaw data lives under this path. New images must install to `/home/cloud/.openclaw/`. The install script / image build process must target the correct user home. |
| **Action** | Image build: install OpenClaw as `cloud` user → auto-lands in `/home/cloud/.openclaw/`. No code changes needed if install uses `$HOME`. |

---

### 12. `/home/cloudsigma/.bashrc` — Shell Initialization

```bash
source "/home/cloudsigma/.openclaw/completions/openclaw.bash"
export OPENCLAW_SYSTEMD_UNIT=openclaw-gateway
```

| | |
|---|---|
| **Risk** | MEDIUM |
| **Impact** | Hardcoded path in .bashrc. On a new `cloud` user, this would still work IF the file is installed to `/home/cloud/.openclaw/completions/`. But if .bashrc template is copied verbatim with old path, completions break. |
| **Action** | Image build: update .bashrc template to use `$HOME` instead of `/home/cloudsigma`. |

---

### 13. Workspace Scripts — Path References

Multiple scripts in `/home/cloudsigma/.openclaw/workspace/` have hardcoded paths:

| File | Reference | Risk |
|---|---|---|
| `prg_perf.js` | `/home/cloudsigma/.cache/ms-playwright/...` | LOW (dev tool) |
| `prg_timing.js` | `/home/cloudsigma/.cache/ms-playwright/...` | LOW (dev tool) |
| `create_vms_json.py` | `/home/cloudsigma/.openclaw/workspace/...` | LOW (dev tool) |
| `analyze_collections.py` | `/home/cloudsigma/.openclaw/workspace/memory/...` | LOW (dev tool) |
| `webchat-ui/PRD.md` | `User=cloudsigma`, `/home/cloudsigma/.openclaw/...` | LOW (docs only) |
| `.venv-pdf/` | Absolute paths baked by venv creation | LOW (venv scripts) |

| | |
|---|---|
| **Risk** | LOW — these are workspace files, not baked into customer images |
| **Action** | When migrating this server specifically, update scripts. Not blocking for new image builds. |

---

### 14. `/etc/sudoers.d/90-cloud-init-users` — Sudoers Entry

Referenced indirectly by `auth_ssh.sh`:
```
cloudsigma ALL=(ALL) NOPASSWD:ALL
```
(standard cloud-init generated entry)

| | |
|---|---|
| **Risk** | HIGH |
| **Impact** | New images with `cloud` user will have `cloud ALL=(ALL) NOPASSWD:ALL` — this is correct and auto-generated by cloud-init. The `auth_ssh.sh` sed command must match the new username. |
| **Action** | Update `auth_ssh.sh` sed command: `cloudsigma ALL=...` → `cloud ALL=...` |

---

### 15. Running Processes

```
openvpn  --config /home/cloudsigma/vpn/ellie-final.conf
node /home/cloudsigma/.openclaw/workspace/webchat-ui/serve.js
sshd: cloudsigma [priv] / cloudsigma@pts/0 / cloudsigma@pts/1
openclaw-gateway (running as cloudsigma user)
```

| | |
|---|---|
| **Risk** | N/A for new images (runtime state, not baked in) |
| **Action** | On this server: no action. On new images: all processes will naturally run as `cloud`. |

---

## Migration Complexity Assessment

### Overall: MEDIUM-HIGH

**Blocking items (must fix before new image ships):**

1. `cloud.cfg` default_user.name — **1 line change** → low effort
2. `/usr/bin/cschpw/ssh_meta.sh` — **5 references** → ~5 min
3. `/usr/bin/cschpw/auth_ssh.sh` — **2 references** → ~5 min
4. `/usr/bin/cschpw/di_ch.sh` — **1 reference** → 1 min
5. `/usr/bin/cschpw/en_ch.sh` — **1 reference** → 1 min
6. OpenClaw install scripts — must install as `cloud` user

**Non-blocking (fix in parallel or after):**

7. `.bashrc` template — use `$HOME` variable
8. `openvpn-ellie.service` — server-specific, not image concern
9. Workspace dev scripts — LOW priority

### Key Insight

The `cschpw` scripts are CloudSigma-proprietary and completely independent of cloud-init. They form a **parallel** first-boot system that:
- Reads SSH public keys from the CloudSigma metadata service via serial (`/dev/ttyS1`)  
- Injects them into the user's `authorized_keys`
- Manages password auth / host keys / networking

These scripts **must be updated atomically** with the cloud.cfg change. A half-migrated image (cloud.cfg says `cloud`, cschpw still says `cloudsigma`) would be broken at first boot.

---

## Recommended Migration Sequence for New Image Build

```
1. Update /etc/cloud/cloud.cfg: default_user.name = cloud
2. Update /usr/bin/cschpw/ssh_meta.sh (5 path/ownership changes)
3. Update /usr/bin/cschpw/auth_ssh.sh (path + sudoers sed)
4. Update /usr/bin/cschpw/di_ch.sh (1 line)
5. Update /usr/bin/cschpw/en_ch.sh (1 line)
6. Ensure image build installs OpenClaw as 'cloud' user
7. Update .bashrc template to use $HOME
8. Test: cloud-init first boot creates 'cloud' user + SSH keys inject correctly
```

---

_Generated: 2026-04-16 by image-lifecycle-audit subagent_
