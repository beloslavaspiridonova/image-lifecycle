# Instruction Registry

## What Is an Instruction?

An **instruction** is a versioned, human-readable specification that defines what must be done to a guest OS image at a particular stage of its lifecycle. Instructions are not scripts — they describe the *intent* and *requirements* of a build step (e.g., "configure cloud-init for the CloudSigma datasource", "disable password authentication for SSH", "set the default guest username to `cloud`"). Each instruction file lives in this directory, is tracked in git, and must be reviewed and approved before it is considered active.

Instructions are the authoritative source of truth for how CloudSigma pre-installed images should be built and configured. When a script is written to automate a step, it must reference the instruction it implements. If an instruction changes, the corresponding script must be reviewed and updated accordingly. This separation ensures that human intent is always captured in plain language, independent of the technical implementation.

## Lifecycle & Governance

Instructions follow a lightweight approval workflow. New or modified instructions are proposed via pull request and require review by an `image-reviewer` or `image-admin` before merging. AI-assisted suggestions (e.g., from Ellie) are treated as proposals and must be approved by a human reviewer before taking effect. Once merged, an instruction is considered **approved** and may be referenced by scripts and automation. Deprecated instructions are archived rather than deleted, preserving the historical record of how images were built.

## File Naming Convention

Instruction files use the format `<vendor>-<topic>-<version>.md` (e.g., `ubuntu-cloud-init-v1.md`, `ubuntu-guest-user-v2.md`). Each file should include a metadata header (vendor, version, status, approved-by, date) followed by the human-readable specification. See existing files in this directory for examples.
