# 2026-11-12 Training feed: the site switch (IA-0031)

Mission: IssTech/isstech-issues#512. Mockup: https://claude.ai/artifact/XacK6ueZuAg8SKwUB5y8KG
(copy in issassist-api `docs/mockups/2026-11-12-training-feed.html`).

## What

`aiAnalysis.training.allowed` (default `false`) → `IA_TRAINING_ALLOWED` in the
`issassist-ai-analysis` ConfigMap, which the API reads at start (`envFrom`). The API's
`training.export` job and `PUT /reporting/training/` refuse unless it is `"true"`.

## Why fail closed

Unlike `support.send` (which treats a missing key as allowed, so an upgrade keeps an
existing operator choice), this is new egress of customer-derived data. An upgrade with
`--reuse-values` from a release without the key must not make it possible. Only an
explicit boolean `true` renders `"true"`.

## Tests

`scripts/check_ai_analysis_render.sh`: four cases (default, true, `yes`, key removed).
Watched failing: with the condition changed to "anything but false", the `yes` and
"key removed" cases fail.

## Not in this chart change

- Kasten workload inventory RBAC (`kastenConnector.inventory`): next slice.
- The Dashboard side (bucket, per-installation switch): issassist-dashboard PR #74.
