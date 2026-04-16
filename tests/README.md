# Test Suite

## Overview

`test-suite.sh` validates that a CloudSigma pre-installed VM image meets all quality gates before it can be promoted to STAGING or PRODUCTION.

## Usage

```bash
# Run all 19 tests (requires sudo for some checks):
sudo bash tests/test-suite.sh

# Verbose output (shows what each test is checking):
sudo bash tests/test-suite.sh --verbose

# Run a single test:
sudo bash tests/test-suite.sh --test=openclaw_service_running

# Results are saved to logs/test-results-YYYY-MM-DD-HHMMSS.txt
```

## The 19 Tests

| # | Test Name | What It Checks |
|---|---|---|
| 1 | openclaw_service_running | `openclaw.service` is active via systemctl |
| 2 | webchat_service_running | `webchat-ui.service` is active via systemctl |
| 3 | tailscale_installed | `tailscale` binary is present and returns a version |
| 4 | tailscale_not_logged_in | Tailscale is installed but NOT authenticated (customer logs in) |
| 5 | taas_configured | openclaw.json contains TaaS provider configuration |
| 6 | openclaw_models_count | openclaw.json has >=10 models configured |
| 7 | skills_present | At least 1 skill exists in workspace/skills/ |
| 8 | bootstrap_ready | BOOTSTRAP.md exists at workspace root |
| 9 | cloud_init_installed | `cloud-init` binary present and returns version |
| 10 | cloud_init_datasource | CloudSigma datasource configured in /etc/cloud/cloud.cfg |
| 11 | guest_user_exists | Guest user (`cloud` or `cloudsigma`) exists in /etc/passwd |
| 12 | guest_user_sudo | Guest user has sudo access |
| 13 | guest_user_homedir | /home/<guest_user> directory exists |
| 14 | no_hardcoded_old_username | No /home/cloudsigma references in active systemd service files (post-migration) |
| 15 | ssh_key_injection_config | cloud-init configured to inject SSH keys |
| 16 | hostname_config | cloud-init configured for hostname setup |
| 17 | network_reachable | Internet connectivity to cloudsigma.com |
| 18 | openclaw_webchat_port | webchat-ui is listening on a port |
| 19 | metadata_service_reachable | CloudSigma metadata service is reachable |

## Pass/Fail Criteria

- **PASS**: All 19 tests pass - image is eligible for STAGING promotion
- **FAIL**: Any test fails - image must not be promoted until fixed

## Guest User Detection

The suite auto-detects whether the image uses `cloud` or `cloudsigma` as the guest user. During migration, `cloudsigma` is expected. New images should use `cloud`.

## Log Files

Results are saved to `logs/test-results-YYYY-MM-DD-HHMMSS.txt`. These are gitignored. Keep them for audit purposes.
