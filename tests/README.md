# CloudSigma Image Validation Test Suite

This directory contains the validation suite for CloudSigma pre-installed Ubuntu VM images. Run it after building or updating an image to confirm all expected components are properly configured.

## Quick Start

```bash
# Run full suite (as root or via sudo)
sudo bash tests/test-suite.sh

# Verbose mode (show detail on each test)
sudo bash tests/test-suite.sh --verbose

# Run a single test
sudo bash tests/test-suite.sh --test=openclaw_service_running

# Show help
sudo bash tests/test-suite.sh --help
```

Results are printed to the terminal with color-coded `PASS`/`FAIL` indicators and also written to:
```
logs/test-results-YYYY-MM-DD-HHMMSS.txt
```

---

## All 19 Tests

### Services

| # | Test Name | What It Checks |
|---|-----------|----------------|
| 1 | `openclaw_service_running` | Runs `systemctl is-active openclaw`. The OpenClaw AI assistant service must be active and running. |
| 2 | `webchat_service_running` | Runs `systemctl is-active webchat-ui`. The web chat interface service must be active and running. |

### Tailscale

| # | Test Name | What It Checks |
|---|-----------|----------------|
| 3 | `tailscale_installed` | Verifies `tailscale` is present in `$PATH` and can report its version. Tailscale must be installed but customers activate it themselves. |
| 4 | `tailscale_not_logged_in` | Confirms the image ships with Tailscale in a logged-out state. A pre-installed image must not carry an active Tailscale session — customers log in with their own account at first boot. |

### OpenClaw / TaaS

| # | Test Name | What It Checks |
|---|-----------|----------------|
| 5 | `taas_configured` | Checks that `~/.openclaw/openclaw.json` (for the `cloud` user) contains a TaaS provider entry. |
| 17 | `openclaw_models_count` | Parses `openclaw.json` and counts configured models. At least **10 models** must be present. Uses Python3 for accurate JSON parsing with grep fallback. |

### Workspace

| # | Test Name | What It Checks |
|---|-----------|----------------|
| 6 | `skills_present` | Verifies that `~/.openclaw/workspace/skills/` exists and contains at least one skill directory. Required skills (e.g. `bash`) are explicitly verified. |
| 7 | `bootstrap_ready` | Confirms `~/.openclaw/workspace/BOOTSTRAP.md` exists and has content. This file drives first-boot onboarding for new customers. |

### Cloud-Init

| # | Test Name | What It Checks |
|---|-----------|----------------|
| 8 | `cloud_init_installed` | Verifies `cloud-init` is installed and executable (`cloud-init --version`). |
| 9 | `cloud_init_datasource` | Checks `/etc/cloud/cloud.cfg` (and `cloud.cfg.d/`) for the **CloudSigma** datasource in the `datasource_list`. Required for proper VM customization at launch. |
| 14 | `ssh_key_injection_config` | Verifies cloud-init is configured to inject SSH public keys into the guest user's `authorized_keys`. Checks for `ssh_authorized_keys`, `ssh_import_id`, or a `users` block in the cloud-init config. |
| 15 | `hostname_config` | Confirms cloud-init will set the hostname at boot. Checks for `set_hostname` / `update_hostname` modules or `preserve_hostname: false` in the config. |

### Guest User

| # | Test Name | What It Checks |
|---|-----------|----------------|
| 10 | `guest_user_exists` | Runs `id cloud` — the primary guest username (`cloud`) must exist on the system. |
| 11 | `guest_user_sudo` | Confirms the `cloud` user has `sudo` access, either via the `sudo`/`wheel`/`admin` group or a sudoers entry. |
| 12 | `guest_user_homedir` | Verifies `/home/cloud` exists and matches the home directory registered for the `cloud` user in `/etc/passwd`. |
| 13 | `no_hardcoded_old_username` | Scans key configuration files for references to the **old username `cloudsigma`** (migration check). Checks: `/etc/cloud/cloud.cfg`, `/etc/sudoers`, `/etc/sudoers.d/*`, and systemd service unit files for `openclaw` and `webchat-ui`. |

### Network

| # | Test Name | What It Checks |
|---|-----------|----------------|
| 16 | `network_reachable` | Performs a `curl` to `https://cloudsigma.com` and checks for a valid HTTP response (200/301/302). Falls back to `https://google.com` if CloudSigma is unreachable but the network is up. |
| 18 | `openclaw_webchat_port` | Confirms the webchat-ui is listening on the expected port (**3000** by default). Checks using `ss`, `netstat`, `lsof`, and a direct `curl` to `localhost:3000`, in order of availability. |
| 19 | `metadata_service_reachable` | Tries to reach the CloudSigma metadata service endpoints (`http://cloudsigma-datasource/`, `http://cloudsigma-datasource/meta/1.0/`, and `http://169.254.169.254/`). Required for cloud-init to fetch VM-specific data at boot. |

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `0`  | All tests passed |
| `1`  | One or more tests failed |

---

## Flags

| Flag | Description |
|------|-------------|
| `--verbose` / `-v` | Print detail lines for each test (also always written to log file) |
| `--test=NAME` | Run a single test by name (e.g. `--test=guest_user_exists`) |
| `--help` / `-h` | Show usage and list all test names |

---

## Output

### Terminal (color when supported)
```
── Services
  ✓ PASS  openclaw_service_running
  ✓ PASS  webchat_service_running

── Tailscale
  ✓ PASS  tailscale_installed
  ✓ PASS  tailscale_not_logged_in
...
============================================================
  RESULT: 19/19 passed — ALL TESTS PASSED ✓
  Log written to: logs/test-results-2026-04-16-120000.txt
============================================================
```

### Log file
Same output is written to `logs/test-results-YYYY-MM-DD-HHMMSS.txt`. In verbose mode, detail lines are always written to the log (even when `--verbose` is not passed to the terminal).

---

## Adding Tests

1. Define a new function `test_YOUR_TEST_NAME()` in `test-suite.sh`
2. Call `pass "YOUR_TEST_NAME" "detail"` or `fail "YOUR_TEST_NAME" "reason"` inside it
3. Add the test name to the `ALL_TESTS` array and call it in the appropriate section block
4. Update this README with the new test description
5. Update `TOTAL_TESTS=19` at the top of the script to the new count

---

## Running in CI / Packer

To run in a Packer provisioner or CI pipeline:

```bash
sudo bash /path/to/tests/test-suite.sh
# Script exits 0 on success, 1 on failure — CI-friendly
```

For Packer, add as a shell provisioner step after all other provisioners complete.

---

## Configuration Variables

At the top of `test-suite.sh`, the following variables can be adjusted:

| Variable | Default | Description |
|----------|---------|-------------|
| `GUEST_USER` | `cloud` | Primary guest username |
| `GUEST_HOME` | `/home/cloud` | Expected home directory |
| `MIN_MODELS` | `10` | Minimum OpenClaw model count |
| `WEBCHAT_PORT` | `3000` | Expected webchat-ui port |
| `REQUIRED_SKILLS` | `(bash)` | Skills that must be present |
