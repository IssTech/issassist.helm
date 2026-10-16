# Send logs to IssTech support (issassist.helm)

> **Cross-repo overview.** Mission [#244](https://github.com/IssTech/IssAssist-Mission/issues/244).
> An operator chooses which log files go in the support .zip, reads them first, adds
> their own files, and either downloads it or sends it, anonymised, as a ticket in the
> IssAssist Dashboard; IssTech's answer is pulled back by the installation.
>
> | Repo                  | Role                                                                                          | Branch                      | Record                                     |
> | --------------------- | --------------------------------------------------------------------------------------------- | --------------------------- | ------------------------------------------ |
> | `issassist-api`       | builds and anonymises the .zip, opens the ticket, uploads, completes, reads tickets | `rfe/support-send-20261016` | `docs/projects/2026-10-16-support-send.md` |
> | `issassist-webgui`    | the Download / Send dialog, tickets on the Logs page, the Reporting switch                     | `rfe/support-send-20261016` | `docs/projects/2026-10-16-support-send.md` |
> | `issassist.helm`      | `support.send` → `IA_SUPPORT_SEND`                                                             | `rfe/support-send-20261016` | `docs/projects/2026-10-16-support-send.md` |
> | `issassist-dashboard` | tickets, presigned storage, retention, Support tab, Support access                             | `rfe/support-send-20261016` (from `main`) | `docs/projects/2026-10-16-support-send.md` |
>
> Approved mockup: [`docs/mockups/2026-10-16-support-send/`](../mockups/2026-10-16-support-send/).

```mermaid
flowchart LR

## Summary

One values key, `support.send` (default `true`), rendered as `IA_SUPPORT_SEND` on the API
container. `false` removes the possibility of sending logs to IssTech; `true` only lets an
administrator switch it on in the application.

## What changed in this repo

- `values.yaml`: `support.send: true`, with what each value means.
- `templates/issassist/api/deployment.yaml`: `IA_SUPPORT_SEND`, "false" only when the value
  is literally false, so an upgrade with `--reuse-values` from a release without the key
  renders "true" (nothing is sent until an administrator switches it on).

Data model, wire contract: none in this repo.

## How to verify

```bash
helm template t . | grep -A1 IA_SUPPORT_SEND                          # value: "true"
helm template t . --set support.send=false | grep -A1 IA_SUPPORT_SEND # value: "false"
```

## Deployment & rollback

Ships with the API image of mission #244. The customer site also needs egress to
`s3.sto1.safedc.net:443`. Rollback: previous chart revision.

## Known limitations & follow-ups

None specific to the chart.

## Commits

See `git log origin/review..rfe/support-send-20261016` in this repo.
