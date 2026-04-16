# cloud-init User Strategy

**Date:** 2026-04-16  
**Status:** Approved for Phase 1  
**Author:** Ellie (image-lifecycle-audit subagent)

---

## 1. Current State

### Guest User: `cloudsigma`

The current production image ships with `cloudsigma` as the default guest user, created by two independent mechanisms:

#### A. cloud-init (`/etc/cloud/cloud.cfg`)

```yaml
system_info:
  default_user:
    name: cloudsigma
    lock_passwd: False
    gecos: Cloudsigma
    groups: [adm, cdrom, dip, lxd, sudo]
    shell: /bin/bash
```

cloud-init creates this user on first boot when the `users: [default]` directive is set.

#### B. CloudSigma cschpw Scripts (`/usr/bin/cschpw/`)

CloudSigma's proprietary first-boot infrastructure runs via `cloudsigma.service` → `global.sh` and performs:
- **SSH key injection** (`ssh_meta.sh`) — reads keys from serial metadata service, writes to `/home/cloudsigma/.ssh/authorized_keys`
- **SSH auth mode management** (`auth_ssh.sh`) — enables/disables password auth based on whether SSH keys exist
- **Host key generation** (`host_key.sh`) — creates SSH host keys if missing
- **Password enforcement** (`di_ch.sh` / `en_ch.sh`) — manages `chage`/`usermod` for password changes
- **Network setup** (`networkscript.sh`) — configures multi-NIC networking

**Critical:** The cschpw scripts are completely separate from cloud-init. They hardcode `cloudsigma` throughout and will **not** automatically adapt when the cloud.cfg username changes.

#### C. Active Services & SSH Sessions

```
sshd: cloudsigma@pts/0    (SSH sessions)
node /home/cloudsigma/.openclaw/workspace/webchat-ui/serve.js
openclaw-gateway (as uid 1000 = cloudsigma)
```

#### D. Datasource

```yaml
# /etc/cloud/cloud.cfg.d/90_dpkg.cfg
datasource_list: [ CloudSigma ]
```

The CloudSigma datasource is the only configured datasource. It handles metadata retrieval (hostname, network, userdata).

---

## 2. Target State

### Guest User: `cloud`

New images will ship with `cloud` as the default guest user.

#### A. cloud-init config change

```yaml
system_info:
  default_user:
    name: cloud
    lock_passwd: False
    gecos: CloudSigma Guest
    groups: [adm, cdrom, dip, lxd, sudo]
    shell: /bin/bash
```

**Why just `name: cloud`?** All group memberships, shell, and sudo behavior remain identical. Only the username changes.

#### B. cschpw Scripts Update (Required — Parallel Change)

All five cschpw scripts must be updated simultaneously:

| File | Change Required |
|---|---|
| `ssh_meta.sh` | `/home/cloudsigma/.ssh/` → `/home/cloud/.ssh/`; `chown cloudsigma:cloudsigma` → `chown cloud:cloud` |
| `auth_ssh.sh` | Path check `/home/cloudsigma` → `/home/cloud`; sudoers sed `cloudsigma ALL=` → `cloud ALL=` |
| `di_ch.sh` | `usermod -p '*' cloudsigma` → `usermod -p '*' cloud` |
| `en_ch.sh` | `chage -d 0 cloudsigma` → `chage -d 0 cloud` |
| `global.sh` | No changes needed (calls subscripts) |

#### C. OpenClaw Installation

OpenClaw must be installed/provisioned as the `cloud` user so it lands in `/home/cloud/.openclaw/`. If the install script uses `$HOME` or derives the path from the current user, this is automatic. Verify the install script doesn't hardcode `/home/cloudsigma`.

#### D. .bashrc Template

Update the image's `.bashrc` template:
```bash
# Change:
source "/home/cloudsigma/.openclaw/completions/openclaw.bash"
# To:
source "$HOME/.openclaw/completions/openclaw.bash"
```

---

## 3. Why `cloud`?

| Reason | Detail |
|---|---|
| **Less provider-branded** | Customers feel the VM is theirs, not CloudSigma's |
| **Standard naming convention** | Similar to `ubuntu`, `ec2-user`, `debian`, `centos` |
| **Short and clean** | Easy to type, easy to recognize |
| **Future-proof** | Not tied to company name — survives rebrandings |
| **Industry expectation** | Customers coming from AWS/GCP/Azure expect a neutral username |

---

## 4. Migration Policy

| Image Type | Username | Action | Timeline |
|---|---|---|---|
| Currently published library images | `cloudsigma` | **Leave as-is** | No change planned |
| New images built from this repo | `cloud` | Apply changes from this doc | Phase 1 |
| Production rollout | `cloud` | After Phase 1 test suite passes 19/19 | Phase 2 |

**No backward compatibility shim needed** for new images. Existing images with `cloudsigma` continue to work. There is no overlap requirement.

---

## 5. Full cloud.cfg Section for New Images

The complete `system_info.default_user` block to use in new image builds:

```yaml
system_info:
  distro: ubuntu
  default_user:
    name: cloud
    lock_passwd: False
    gecos: CloudSigma Guest
    groups: [adm, cdrom, dip, lxd, sudo]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
  network:
    dhcp_client_priority: [dhcpcd, dhclient, udhcpc]
    renderers: ['netplan', 'eni', 'sysconfig']
    activators: ['netplan', 'eni', 'network-manager', 'networkd']
  ntp_client: auto
  paths:
    cloud_dir: /var/lib/cloud/
    templates_dir: /etc/cloud/templates/
  ssh_svcname: ssh
```

The `sudo: ["ALL=(ALL) NOPASSWD:ALL"]` line ensures cloud-init also creates the sudoers entry (in `/etc/sudoers.d/90-cloud-init-users`) with the correct username.

---

## 6. SSH Key Injection Flow (Target State)

```
[CloudSigma API] → customer uploads SSH public key
       ↓
[VM First Boot] → cloudsigma.service starts
       ↓
[global.sh] → runs ssh_meta.sh
       ↓
[ssh_meta.sh] → reads key from /dev/ttyS1 (serial metadata)
       ↓
[ssh_meta.sh] → writes to /home/cloud/.ssh/authorized_keys
       ↓
[ssh_meta.sh] → chown cloud:cloud /home/cloud
       ↓
[auth_ssh.sh] → checks key file exists + has content
       ↓
[auth_ssh.sh] → disables password auth in sshd_config
       ↓
Customer can SSH as: ssh cloud@<vm-ip>
```

---

## 7. Compatibility Notes

### Existing Automation

Any customer automation that SSHes as `cloudsigma` will not work on new images. This is a **known breaking change** and is the **intended behavior** — new images are a new generation.

Documentation must clearly state:
- Old images (≤ current): SSH as `cloudsigma`
- New images (Phase 1+): SSH as `cloud`

### cloud-init Idempotency

cloud-init only runs user creation on first boot (guarded by `/var/lib/cloud/instance/`). Subsequent boots do not re-create users. This means:
- A VM that booted once as `cloudsigma` **retains** `cloudsigma` even if cloud.cfg is edited later
- New images always start fresh

### The `users: [default]` Directive

`/etc/cloud/cloud.cfg` sets:
```yaml
users:
  - default
```

This tells cloud-init to create the `default_user` defined in `system_info`. No additional user-data configuration is needed for standard deployments.

---

## 8. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| cschpw scripts not updated atomically with cloud.cfg | **CRITICAL** | Script updates are in same image build step; test-suite checks SSH key injection |
| `.bashrc` has hardcoded path, completions break | MEDIUM | Use `$HOME` variable in template |
| Existing documentation/tutorials reference `cloudsigma` | LOW | Update docs in Phase 2 |
| Customer automation assumes `cloudsigma` username | MEDIUM | Publish migration notice; changelog entry |
| SSH key injection fails silently (no logs to customer) | MEDIUM | Add logging to ssh_meta.sh in new image |

---

## 9. Dual-User Option (If Needed)

If v1.0 migration risk is too high, a transitional option is available:

Create **both** users in the initial cloud.cfg:
```yaml
users:
  - default
  - name: cloudsigma
    no_create_home: true
    system: true
    shell: /bin/bash
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
```

This creates `cloud` as the main user AND `cloudsigma` as a system alias. Not recommended — adds complexity and confusion.

**Decision:** Start with `cloud` only in new images. No dual-user shim.

---

_Generated: 2026-04-16 by image-lifecycle-audit subagent_
