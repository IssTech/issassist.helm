# Release notes — IssAssist Helm chart

What exists now that did not before, written for an operator, a support engineer, or a
documentation agent with no access to the diff. The engineering record for each change is
in `docs/projects/<date>-<slug>.md`, linked from the entry.

> **This file starts here.** It was created on 2026/10/15 with the change below; chart
> releases before it are not documented retrospectively. `docs/projects/` goes back
> further.

---

## Next chart release — in development

### `support.send`: whether this installation may send logs to IssTech support

**What it is.** The site's own say over the new *Send logs to IssTech support* on the Logs
page.

**Where it is.** `values.yaml`:

```yaml
support:
  send: true   # false: never, and the Reporting switch is hidden
```

Rendered as `IA_SUPPORT_SEND` on the API.

**What changed for them.**
- **Nothing is sent by default** even with `send: true`: an administrator must also switch
  it on under Settings → Configuration → Reporting.
- **Dark Sites set `support.send: false`.** Download .zip is unaffected.
- Sending uses `api.issTechConnect` (the dashboard connection), and the installation must
  also reach **`s3.sto1.safedc.net:443`**.

**Where the detail is.** [`docs/projects/2026-10-16-support-send.md`](docs/projects/2026-10-16-support-send.md)

### `logging.*`: how the API and the TSM agent log

**What it is.** One place to set how IssAssist's services log, and how long the Logs page
keeps their lines.

**Where it is.** `values.yaml`:

```yaml
logging:
  level: INFO       # DEBUG, INFO, WARNING or ERROR: what the pods write
  format: text      # text, or json (one object per line) for your own log platform
  keepDays: 30      # 1-365: how long the Logs page keeps a line
  storeFrom: INFO   # INFO, WARNING or ERROR: the lowest level kept
```

These are rendered into the `issassist-logging` ConfigMap, which the API and the TSM agent
read. Both pods also get `IA_POD_NAME` and `IA_NODE_NAME`, so every line says where it came
from.

**What changed for them.**
- **Changing a `logging.*` value restarts the API and TSM agent pods.** The ConfigMap's
  checksum is on both Deployments, because the setting is read at start.
- **Support can turn on debug logs with one command and no new image:**
  `helm upgrade <release> <chart> --reuse-values --set logging.level=DEBUG`. DEBUG goes to the
  pods' output only and is never stored. Set it back to INFO afterwards.
- An out-of-range value fails the install or upgrade with a message, rather than being
  replaced by a default. That includes `keepDays: 0`.
- A `--reuse-values` upgrade from a release without `logging` gets the defaults above.
- **The API has a startup probe that allows up to 10 minutes.** The liveness probe used to
  restart the API 30 seconds into its first start, while it was still running database
  migrations, and each restart began again and lost the only log of why. Liveness checks
  begin once the API has started.
- Requires API and TSM agent images from this release; older images ignore these settings.

**Where the detail is.** `docs/projects/2026-10-15-logging.md` in `issassist-api`.
