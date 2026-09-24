# Schedules in the app — the TSM sync CronJobs are switched off

**Repo:** `issassist.helm` · **Branch:** `fix/schedules-in-the-app-20260924` · **Closed:** 2026-09-24

## Summary

The two `sync-client` CronJobs — `sync-all-operations-centers` and
`sync-all-dedup-stats` — are no longer rendered. Both syncs are jobs inside
IssAssist now, scheduled from its own settings, where an operator can move them
without a release.

## Why

Their schedules lived in `values.yaml` (`*/10 * * * *` and `0 20 * * *`), so an
installation whose backup window collided with the nightly dedup sync had to wait
for a chart release to move it. They also reported nothing: a CronJob pod's
output is not visible anywhere in the product.

## Cross-repo overview

| Repo | Role | Branch | README |
|---|---|---|---|
| `issassist.helm` | Stops rendering the CronJobs | `fix/schedules-in-the-app-20260924` | this file |
| `issassist-api` | Runs both syncs as scheduled jobs | `rfe/general-processing-20260923` | `docs/projects/2026-09-24-general-processing.md` |
| `issassist-webgui` | The schedule editor | `rfe/general-processing-20260923` | `docs/projects/2026-09-24-general-processing.md` |

**Merge this last.** If the chart lands before the API that replaces these jobs,
nothing syncs Operations Centers in between.

## What changed in this repo

`templates/cronjobs.yaml` — both CronJobs now also require
`.Values.tsmAgent.sync.useCronJobs`, which defaults to **false**.

> **Why a new key rather than the existing `enabled` flags.** `helm upgrade
> --reuse-values` carries an installation's old values forward, and those say
> `enabled: true`. Gating on them would leave every upgraded installation syncing
> twice — once on the chart's crontab and once on the operator's schedule. A key
> that did not exist before cannot do that.

`values.yaml` — `tsmAgent.sync.useCronJobs: false`, with the two `crontab` values
kept and marked as used only when it is true. They are the way back.

## Configuration

| Key | Default | Meaning |
|---|---|---|
| `tsmAgent.sync.useCronJobs` | `false` | Render the old CronJobs instead of using the app's scheduler. Turn it on **and** switch the two jobs off in the app, or the estate is synced twice. |

Nothing else changes. `tsmAgent.enabled` and the two `sync.*.enabled` flags still
gate as before when `useCronJobs` is on.

## How to verify

```bash
helm template test . --set tsmAgent.enabled=true                                 # 0 CronJobs
helm template test . --set tsmAgent.enabled=true --set tsmAgent.sync.useCronJobs=true  # 2 CronJobs
```

On staging (revision 104) both CronJobs are gone, and the app's own
`storage_protect.sync_operations_centers` job ran and succeeded in their place.
The only CronJob left in that namespace is `avepoint-run-check`, which is not in
this chart — someone created it by hand, and it has errored on its last three runs.

## Deployment & rollback

Deploy after the API that carries the replacement jobs. Rollback is
`--set tsmAgent.sync.useCronJobs=true`, which restores both CronJobs on their
original crontabs; switch the two jobs off in Settings → Configuration → IBM
Storage Protect → Scheduled work at the same time.

## Known limitations & follow-ups

- The chart still ships `sync.operationsCenters.enabled` and
  `sync.dedupStats.enabled`, which now only matter when `useCronJobs` is true.
  Worth removing once no installation runs the CronJobs.

## Commits

```
b134dc7 fix: stop running the TSM syncs from CronJobs
```
