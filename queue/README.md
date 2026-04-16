# Review Queue

This directory stores the lightweight review queue for the CloudSigma Image Lifecycle system.

## Files

- `review-items.json` - current open and historical review items
- `review-items.schema.json` - JSON schema for queue structure
- `../audit/approval-log.jsonl` - append-only approval/rejection/deferral events

## Purpose

This is the minimal Phase 2 implementation of the PRD approval queue concept.
It tracks items that require human review before they become active in production-facing flows.

## Typical item types

- `vendor-change`
- `version-candidate`
- `instruction-change`
- `script-change`
- `test-change`
- `publish-request`
- `rollback-request`

## Status values

Use the PRD-aligned values where possible:
- `draft`
- `proposed`
- `under-review`
- `approved`
- `rejected`
- `deferred`
- `in-progress`
- `validated`
- `failed`
- `deprecated`

## v1.0 Operating Model

For now, items may be added manually or by scripts.
A human reviewer must approve production-impacting changes before merge/activation.

See:
- `../docs/approval-flow-ai-changes.md`
