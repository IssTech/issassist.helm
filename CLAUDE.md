# issassist.helm — agent rulebook (the product assembly point)
Helm 3 chart (`Chart.yaml` `apiVersion: v2`, `version: 1.2.0`) that deploys the whole
stack. Style: [`../CLAUDE.md`](../CLAUDE.md) (Helm section).

## This chart IS the product
The chart pins the 3 product image tags in `values.yaml`: `api.image` (issassist-api),
`webGUI.image` (issassist-webgui), `tsmAgent.image` (issassist-tsm-agent) — currently all
`ghcr.io/isstech/issassist-*:1.3`. It also bundles supporting images (postgres:17 x2,
kubernetes-secret-generator, the `superset` subchart). There is **no `releases/` folder**
in this repo today — if you need a BOM/version-tracking record, that mechanism does not
exist yet and would need to be built, not assumed.

## Module conditional pattern (actual, not `.Values.modules.*`)
There is no `modules:` key in `values.yaml` and no `{{- if .Values.modules.<name>.enabled }}`
pattern anywhere in `templates/` — do not use that pattern from memory. Gating is
per-component under real top-level keys: `global`, `api`, `webGUI`, `tsmAgent`, `pgAdmin`,
`imageCredentials`, `kubernetes-secret-generator`, `superset`. Example:
`{{ if .Values.tsmAgent.enabled }}` in `templates/issassist/tsm-agent/deployment.yaml`.
Disabling `tsmAgent.enabled` removes its Deployment plus its dependent Postgres/Valkey
resources (`templates/dependencies/tsm-agent-postgres/`, `templates/dependencies/tsm-agent-valkey/`).
`pgAdmin.enabled` (default `false`) gates `templates/tools/pgadmin/` the same way.
The `superset` subchart uses `condition: superset.enabled` in `Chart.yaml` — follow that
pattern for any new conditional Helm dependency.

**Kasten and AvePoint have no chart-level toggle.** issassist-api has `kasten/` and
`avepoint/` integration packages (see `../issassist-api/CLAUDE.md`), but nothing in this
chart's `values.yaml` or `templates/` references either name — those integrations are
enabled today via issassist-api's own config/env vars, not via a Helm value. If you wire a
Helm-level enable/disable switch for them, follow the Kubernetes-first design rule in the
root `CLAUDE.md` (values.yaml key → ConfigMap → env var, never a hardcoded URL).

## Secrets
cert-manager issues internal TLS (17 `Certificate` resources under `templates/certificates/`);
kubernetes-secret-generator creates passwords (9 resources under `templates/accounts/`) —
never hardcode secrets in templates. Use `secretKeyRef` (used throughout
`templates/issassist/api/deployment.yaml` and `templates/issassist/tsm-agent/deployment.yaml`),
not plain env values.

## Other values worth knowing
- `imageCredentials` — GHCR pull secret config; required per the root README install flow.
- `charts/` — vendored subcharts (`kubernetes-secret-generator`, `superset`).

## Local test path
`values.local-test.yaml` does **not currently exist** in this repo — there is no MicroK8s
Tier-2 test values file today despite the root CLAUDE.md's Tier-2 testing convention. If
you add one, keep it working at all times; a change that breaks it should block the
release once this path exists.

## Release flow
1. Feature branches tested and merged in the relevant repos.
2. Bump image tags in `values.yaml`.
3. Bump `Chart.yaml` version and tag the chart.
4. Publish chart + offline bundle (for air-gapped Dark Site customers).
