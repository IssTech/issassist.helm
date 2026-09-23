# The ingress issuer that could never be ready — issassist.helm

**Closed:** 2026-09-23 · **Branch:** `fix/self-signed-ingress-issuer-20260923`

## Summary

Removes `self-signed-ingress-issuer`, a cert-manager `Issuer` that was refused in every
install and issued nothing. Its only effect was a permanently NotReady resource, which
fails `helm upgrade --wait` and buries real failures.

## Why

The Issuer was declared as a **CA issuer** whose CA is `self-signed-ingress-cert`:

```yaml
spec:
  ca:
    secretName: self-signed-ingress-cert
```

That secret holds the ingress's own **server** certificate — `usages: [server auth]`,
no `isCA: true` — so cert-manager refused it, every time:

```
Error getting keypair for CA issuer: certificate is not a CA
```

On staging the condition had been `False` since **2026-08-11**. Nothing ever issued from
it: `grep -rn issuerRef templates/` shows every certificate pointing at `root-issuer`,
`issassist-ca-issuer` or `docker-ca-issuer`, and the ingress references the *secret*
directly (`templates/ingress.yaml`, `templates/tools/pgadmin/ingress.yaml`).

It surfaced while deploying: `helm upgrade --wait` failed on this resource although both
Deployments had rolled out, leaving revision 82 marked `failed` — which then made
`--reuse-values` on later upgrades reuse revision 81's values and silently revert the API
image.

## Cross-repo overview

| Repo | Role in this project | Branch | README |
|---|---|---|---|
| issassist.helm | This fix | `fix/self-signed-ingress-issuer-20260923` | this file |
| issassist-api | Module switches, build version, dashboard sync, licence audits | `rfe/storage-protect-audit-licence-20260923` | `docs/projects/2026-09-23-settings-versioning-and-licence-audit.md` |
| issassist-webgui | The operator-facing half of the same | `rfe/storage-protect-audit-licence-20260923` | `docs/projects/2026-09-23-settings-versioning-and-licence-audit.md` |
| issassist-tsm-agent | `audit_licences` | `rfe/storage-protect-audit-licence-20260923` | `docs/projects/2026-09-23-settings-versioning-and-licence-audit.md` |

This chart change is independent of the other three; it was found and fixed while
deploying them, and is closed with them.

## What changed in this repo

`templates/certificates/self-signed-ingress-cert.yaml`: the `Issuer` block is deleted.
The `Certificate` above it is untouched — it is the ingress's TLS certificate and is
still issued by `root-issuer`.

A comment replaces it explaining why there is deliberately no issuer here and naming
`issassist-ca-issuer` as the internal CA to issue from, so the next person does not
re-add it.

Considered and rejected: making it a real CA (a second certificate with `isCA: true`
plus its own issuer, as `issassist-ca.yaml` does). Nothing issues from it, so that would
add a certificate to keep alive for no consumer.

## Data model & migrations

None.

## Wire & API contract

None.

## Configuration

No `values.yaml` keys added, changed or removed. One fewer Kubernetes resource is
rendered.

## How to verify

```bash
helm template test . --set global.publicDomainName=staging.int.isstech.io | grep -c self-signed-ingress-issuer   # 0
```

- `helm lint` fails with `chart metadata is missing these dependencies:
  kubernetes-secret-generator` — **pre-existing**, needs `helm dependency build`, and
  identical on `review`.
- On staging (revision 84): `kubectl -n issassist-staging get issuer` now lists
  `docker-ca-issuer` and `issassist-ca-issuer`, both `True`, and the broken one is gone.
  `self-signed-ingress-cert` is still `Ready`, the site answers 200, and
  `helm upgrade --wait` completed cleanly (revision 85) — it could not before.

## Deployment & rollback

Applied to staging on 2026-09-23, revision 84, then re-run with `--wait` as revision 85
to prove the wait now succeeds. Staging is at revision 90 after the rest of the project.

Rollback: `helm rollback` restores the Issuer, which will immediately be NotReady again.
Nothing depends on it, so neither direction affects traffic.

## Known limitations & follow-ups

- `helm lint` needs `helm dependency build` first; not addressed here.
- Other charts were not audited for the same shape of mistake.
- The staging release has failed revisions in its history (82). They are harmless but
  make `--reuse-values` reuse older values — see the API README's warning.

## Commits

| SHA | Subject |
|---|---|
| `4ffd29f` | fix: drop the ingress CA issuer that could never be ready |
