# Script Governance

## Role of Scripts

Scripts in this directory are the *executable implementations* of approved instructions. Every script must reference the instruction it implements (by filename and version) in its header comment. Scripts are never authoritative on their own — the instruction is. If a script and its corresponding instruction ever conflict, the instruction wins and the script must be updated.

Scripts are written in Bash unless there is a specific reason to use another language (which must be noted in the script header). All scripts must be idempotent: running them multiple times on the same image should produce the same result as running them once. This is essential for reliable automation and safe retries.

## Governance Model

Changes to scripts follow the same approval workflow as instructions. Proposed changes are submitted via pull request, reviewed by an `image-reviewer` or `image-admin`, and must pass automated tests before merging. Scripts that are AI-generated or AI-modified (e.g., by Ellie) are flagged as `ai-proposed` and require explicit human approval. No script may be executed in a production or staging context without being in an approved, merged state in this repository.

## File Naming Convention

Script files use the format `<vendor>-<topic>[-<variant>].sh` (e.g., `ubuntu-cloud-init.sh`, `ubuntu-guest-user-migrate.sh`). Each script must include a header block with:
- `# Instruction: <instruction-filename>` — the approved instruction this script implements
- `# Version: <semver>` — script version
- `# Status: approved | draft | deprecated`
- `# Last-reviewed-by: <name>` and `# Last-reviewed-date: <date>`

Scripts in `draft` or `deprecated` status must not be executed by automation.

## Testing

All scripts must have corresponding test cases in the `tests/` directory. Tests are run automatically as part of the image build pipeline and must pass before a candidate image is promoted from STAGING to PRODUCTION.
