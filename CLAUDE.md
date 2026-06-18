# issassist.helm — agent rulebook (the product assembly point)
Helm 3 chart (v1.2.x) that deploys the whole stack. Style: `../.claude/STYLE.md` (Helm).

## This chart IS the product
A tagged release of this chart, pinning the 3 image tags (api, tsm-agent, webgui), is the
immutable product BOM. The `releases/` folder records every validated version.

## Module conditional pattern
Modules are conditional: wrap each integration's Deployment/Service/PVC/CronJob in
`{{- if .Values.modules.<name>.enabled }}`. Disabling tsm removes real pods (agent +
its Postgres/Valkey); disabling kasten/avepoint switches off API routes/schedulers but
keeps no extra pods. The superset dependency already uses `condition: superset.enabled`
as a reference.

## Secrets
cert-manager issues internal TLS; kubernetes-secret-generator creates passwords — never
hardcode secrets in templates. Use secretKeyRef, not plain env values.

## Local test path
Keep `values.local-test.yaml` working for the MicroK8s Tier-2 test path at all times.
A change that breaks the local test path blocks the release.

## Release flow
1. Feature branches tested and merged in the relevant repos.
2. Bump image tags in `values.yaml`, write `releases/vX.Y.Z.yaml` (BOM).
3. Bump `Chart.yaml` version and tag the chart.
4. Publish chart + offline bundle (for air-gapped Dark Site customers).
