# Release notes — IssAssist Helm chart

What exists now that did not before, written for an operator, a support engineer, or a
documentation agent with no access to the diff. The engineering record for each change is
in `docs/projects/<date>-<slug>.md`, linked from the entry.

> **This file starts here.** It was created on 2026/10/15 with the change below; chart
> releases before it are not documented retrospectively. `docs/projects/` goes back
> further.

---

## Next chart release — in development

### Postgres and Valkey are reachable only inside the cluster: `*.postgres.service` / `*.valkey.service` (IA-0044)

**What it is.** The six database Services (`api-postgres`, `api-valkey`, `tsm-agent-postgres`,
`tsm-agent-valkey`, `superset-postgres`, `superset-valkey`) were fixed `NodePort`s on 30101–30106,
so the databases answered on every node's address to anything that could route to the node
network.

**Where it is.** `api.postgres.service`, `api.valkey.service`, `tsmAgent.postgres.service`,
`tsmAgent.valkey.service`, `superset.postgres.service`, `superset.valkey.service` in values.yaml,
each with `type` and an optional `nodePort`.

**What changed for them.** **The default changed: all six are now `ClusterIP`. The node ports
30101–30106 stop answering on upgrade.** IssAssist itself, pgAdmin and Superset connect by
Service name inside the cluster and are not affected. **Anything that connected from outside the
cluster through a node port — a database client on a laptop, an external backup of the database
— must either use `kubectl port-forward`, or set that Service back, e.g.
`--set api.postgres.service.type=NodePort`, which restores the old port (30101); `nodePort`
chooses another.** Only `ClusterIP` and `NodePort` are accepted. Two releases of the chart can
now run on one cluster, since the fixed ports no longer collide.

**Where the detail is.** [`docs/projects/2026-11-14-1-5-0-more-fixes.md`](docs/projects/2026-11-14-1-5-0-more-fixes.md).

### `api.selfCheck.caBundle`: the CA the public-URL check trusts (#372)

**What it is.** When an operator saves the public API URL, the API calls itself at that URL.
That call now always verifies the certificate (issassist-api 1.5.0); this key gives it the CA
to verify against when the certificate is not from a public CA.

**Where it is.** `api.selfCheck.caBundle.secret` or `.configMap` (one, not both) and `.key`
(default `ca.crt`), rendered as `IA_SELF_CHECK_CA_BUNDLE` and a read-only volume on the API pod
at `/mnt/self-check-ca/`.

**What changed for them.** Nothing to do for a public certificate (`issuerType: cluster` or
`issuer`), or for the chart's own self-signed ingress certificate (`issuerType: disabled`, the
default): the chart then trusts `self-signed-ingress-cert` by itself, mounting only its
`ca.crt`, never the private key. **If something in front of the ingress presents a certificate
from your company CA, create a Secret or ConfigMap holding that CA and name it here, or saving
the public API URL fails with "could not be verified".** A missing Secret or ConfigMap does not
stop the API from starting.

**Where the detail is.** [`docs/projects/2026-11-14-1-5-0-more-fixes.md`](docs/projects/2026-11-14-1-5-0-more-fixes.md).

### Trusted proxies for client addresses: `api.forwardedAllowIps` (IA-0036)

**What it is.** The list of proxies whose `X-Forwarded-For` and `X-Forwarded-Proto` headers
the API believes, so that logs, the audit trail and new-login notices show the real client
address instead of the ingress controller's.

**Where it is.** `api.forwardedAllowIps` in values.yaml, rendered as `IA_FORWARDED_ALLOW_IPS`
on the API pod. A comma-separated list of IP addresses or CIDRs.

**What changed for them.** The chart used to hard-code `"*"`, which the API ignored because of
a bug in its start script; with that bug fixed (issassist-api, IA-0036), `"*"` would have let
any client write its own address. The key now defaults to **empty: no proxy is trusted**, which
is how installations have effectively run so far. `"*"`, a `*` inside a list, a `/0` (`0.0.0.0/0`, `::/0`, which trust every address), an empty
entry or anything that is not an IP address or CIDR stops the render with a message. **To see real client addresses, set it to the ingress
controller's pod CIDR or addresses, never `"*"`. Setting it also makes the API trust
`X-Forwarded-Proto`, so re-test SSO/SAML sign-in after setting it.**

**Where the detail is.** IssTech/isstech-issues#517 (IA-0036, security review H1);
`scripts/check_api_render.sh` (16 checks).

### IssProtect for DevOps: workload inventory read rights (IA-0031)

**What it is.** Lets IssAssist see which databases and stateful services run in each
namespace of a Kasten cluster, on which storage, and which Kanister Blueprint protects them.

**Where it is.** `kastenConnector.inventory` in values.yaml. It adds read-only rules to the
`issassist-kasten-connector` ClusterRole: pods, deployments, statefulsets, daemonsets,
CustomResourceDefinitions (list), Kanister blueprints and Kasten blueprintbindings.

**What changed for them.** New key, **default `false`**; only an explicit `true` grants it.
`list` only: never `get`, never Secrets or ConfigMaps, and no write verbs. **Re-apply the connector on every monitored
cluster** (`helm template … -s templates/kasten/connector.yaml | kubectl apply -f -`) after
setting it; until then the Workloads view says the rights are missing. The pod read right
includes container environment values in the answer, which travel over TLS to IssAssist
(accepted risk): IssAssist drops env, command, args and annotations before storing anything.

**Where the detail is.** `docs/projects/2026-11-12-kasten-inventory.md`; mission
IssTech/isstech-issues#512.

### Training feed to IssTech: the site switch (IA-0031)

**What it is.** Whether this installation may send pseudonymised closed cases (IBM Storage
Protect now, IssProtect for DevOps later) to IssTech each night, to train the IssAssist LLM.

**Where it is.** `aiAnalysis.training.allowed` in values.yaml, rendered as
`IA_TRAINING_ALLOWED` in the `issassist-ai-analysis` ConfigMap.

**What changed for them.** New key, **default `false`**. Only an explicit `true` allows it;
a missing key (an upgrade with `--reuse-values` from an older release), `yes` or a typo
keeps it off. With `true`, an AI Admin (`ai_analysis:configure`) can switch the feed on
under Settings → Configuration → Reporting; it stays off until they do. **Sending also
needs the IssTech Dashboard enrolment (`api.issTechConnect`) and IssTech must have enabled
training for the installation.** A changed value restarts the API pod.

**Where the detail is.** `docs/projects/2026-11-12-training-feed.md`; mission
IssTech/isstech-issues#512.

### AvePoint: the hosts the partner credential may be sent to

**What it is.** A list of the AvePoint host names IssAssist is allowed to send the AvePoint
partner credential to. The client secret goes to the token URL, and the access token it buys
goes to the customers, services and jobs endpoints. Until now those four addresses could be
changed freely under Settings → Configuration → AvePoint, and whatever was typed there
received the secret.

**Where it is.** `api.avepoint.allowedHosts` in `values.yaml` (new), rendered into the new
ConfigMap `issassist-avepoint` as `IA_AVEPOINT_ALLOWED_HOSTS` and given to the API pod. A
change to the list restarts the API pod.

**What changed for them.**

- **Default: `identity.avepointonlineservices.com` and `graph.avepointonlineservices.com`**,
  the two hosts AvePoint uses today. An installation using AvePoint's standard addresses
  needs to do nothing.
- **An installation with a saved AvePoint URL on another host stops collecting until the
  host is added to `api.avepoint.allowedHosts` or the URL changed — check Settings →
  Configuration → AvePoint before upgrading.** The collection run then fails with a sentence
  that says which address and what to do; nothing is sent to the other host.
- Exact host names only: no scheme, port, path or wildcard. `helm install`/`upgrade` refuses
  an entry that is not a bare lower-case host name. A new AvePoint region is added here.
- **An empty list refuses every AvePoint address.** Removing the key, or upgrading with
  `--reuse-values` from a release without it, keeps the two defaults.
- Harmless on its own: an API image from before this change ignores the variable, and the
  API's built-in default is the same two hosts.

**Where the detail is.** issassist-api
[`docs/projects/2026-11-05-ia-0008-avepoint.md`](https://github.com/IssTech/issassist-api/blob/review/docs/projects/2026-11-05-ia-0008-avepoint.md)
(IA-0008, isstech-issues #437).

### IBM Bob: the run pods pull their images with a registry Secret

**What it is.** IBM Bob's run pods, in `aiAnalysis.providers.bob.namespace`, now pull the
runner and key sidecar images with a registry Secret, the way the API and web GUI do. Before,
on a cluster that needs credentials for ghcr.io, no Bob run could start.

**Where it is.** `aiAnalysis.providers.bob.imagePullSecret` (new), and
`imageCredentials`.

**What changed for them.**

- **With `imageCredentials.username`/`password`**, the chart renders the same Secret in Bob's
  run namespace too. Nothing to do.
- **With `imageCredentials.existingSecret`, create a Secret of that name in Bob's run
  namespace as well** (by default `ai-bob-runs`), the same way as in the release
  namespace. Or name another one there with `bob.imagePullSecret`.
- `bob.imagePullSecret: none` pulls without one, for a public or node-authenticated mirror.
- The admission policy admits a run pod only with that one Secret, or none.

**Where the detail is.** issassist-api `docs/projects/2026-10-29-ai-analysis-api.md`,
"Slice 4: the first runs on staging (2026/11/04)".

### IBM Bob: regions to choose from, and a switch of Bob's own for its cluster resources

**What it is.** Two changes to `aiAnalysis.providers.bob`:

- **`regions`** lists the regions an operator can choose between in the web GUI, as region
  name and IBM gateway address. By default these are us-east, eu-de and jp-tok. Run pods may
  forward to these addresses and no other: the admission policy checks it.
- **`clusterResources`** decides whether Bob's run namespace and admission policies are
  rendered. Empty follows `clusterScoped.create`, as before. `true` renders them without
  `clusterScoped.create`, so Bob can be set up where the restore tests' ClusterRole is not
  wanted. `false` leaves them out.

**Where it is.** `values.yaml`: `aiAnalysis.providers.bob.regions`, `.region`,
`.clusterResources`, `.gatewayUrl`.

**What changed for them.**

- **`region` now defaults to eu-de**, and must be one of `regions` where Bob is allowed.
- **`gatewayUrl` now defaults to empty.** Set it only for a customer's own Bob: it is then
  the only address, and nothing can be chosen in the web GUI. A release upgraded with
  `--reuse-values` that still carries IBM's us-east address keeps us-east as its default,
  and the other regions can still be chosen.
- A region address must be plain `https://`, with no credentials and no query string, or
  rendering fails.

**Where the detail is.** issassist-api's `docs/projects/2026-10-29-ai-analysis-api.md`, slice 4.

### `aiAnalysis.providers.isstech` removed

**What it is.** The AI analysis provider "IssTech" (the IssAssist LLM reached through the
IssTech dashboard) is gone. It never ran: it was listed, greyed out, until the dashboard
could offer analysis. The IssAssist LLM is reached as **IssAssist LLM / own LLM**
(`aiAnalysis.providers.local`), an OpenAI-compatible endpoint.

**Where it is.** `values.yaml` → `aiAnalysis.providers`: the `isstech` block is removed.

**What changed for them.** Nothing to do. A release upgraded with `--reuse-values` that
still has an `isstech` block renders as before and the block is ignored: no
`IA_AI_ISSTECH_*` setting and no `issassist-ai-isstech-key` Secret is rendered. If you set
`isstech.apiKey`, Helm no longer renders that Secret, and you can remove the block.

**Where the detail is.** `issassist-api` `docs/projects/2026-10-29-ai-analysis-api.md`.

### `aiAnalysis.providers.<id>.dailyCap` / `dailyCapMax`: a daily cap per AI provider

**What it is.** Each AI provider gets its own daily cap, in its own unit. Operators
change it in Settings › AI analysis, within the maximum set here.

**Where it is.**

| Provider | `dailyCap` | `dailyCapMax` |
|---|---|---|
| `claude` | 5 | 20 (EUR) |
| `gemini` | 5 | 20 (EUR) |
| `bob` | 20 | 50 (bobcoins) |
| `local` | 0 | 0 (no cap; tokens are counted) |

**What changed for them.**
- New.
- **`bob.dailyCapBobcoins` is replaced by `bob.dailyCap` / `bob.dailyCapMax`.**
- `aiAnalysis.maxDailyCapEur` stays: it is the ceiling on all EUR providers together.
- A release upgraded with `--reuse-values` from before these keys existed gets the
  defaults above.

**Where the detail is.** `issassist-api/docs/projects/2026-10-29-ai-analysis-api.md`,
"a daily cap per LLM".

### `aiAnalysis.providers.bob`: IBM Bob runs, one pod per analysis

**What it is.** IBM Bob can now explain a Storage Protect alert. Each analysis runs in a
fresh pod of its own in a separate namespace, which the API creates and deletes. The chart
creates that namespace, what its pods may reach, and the API's permission to start pods
there. The API also gets a ServiceAccount of its own, named `api`, instead of the
namespace's `default`.

**Where it is.** `aiAnalysis.providers.bob` in `values.yaml`:

| Key | Default | Meaning |
|---|---|---|
| `allowed` | `false` | Only `true` turns Bob on for this site. |
| `image` | `""` | The `ghcr.io/isstech/issassist-bob-runner` image, **pinned by digest** (`…@sha256:…`); a tag alone is refused. Empty: Bob is not set up, and every run says so. |
| `keyproxyImage` | `""` | The key sidecar, `ghcr.io/isstech/issassist-bob-keyproxy`, **by digest**. It holds the real key, so that Bob never does. |
| `gatewayUrl` | `https://api.us-east.bob.ibm.com` | Where Bob's calls go, through the sidecar. Use the gateway of the region of the key's Bob instance, or of a customer's own Bob. https only. |
| `dailyCap` / `dailyCapMax` | `20` / `50` | Bob's daily cap in bobcoins, as for every provider above. **A maximum of 0 means Bob cannot be switched on.** |
| `maxCostPerRunBobcoins` | `5` | The most one analysis may spend. |
| `namespace` | `ai-bob-runs` | Where the run pods are. Not the release's own namespace, not `default` or `kube-*`. |
| `timeoutSeconds` | `180` | A run pod is stopped after this. 30 to 900. |
| `maxTurns` | `3` | Passed to Bob. |
| `region` | `us-east` | Shown in the web GUI; Bob runs where the key's Bob instance is. |
| `egress` | `internet-443` | Run pods reach DNS and HTTPS outside the cluster, and nothing inside it. |
| `existingSecret` / `apiKey` | `""` | The key. **`existingSecret` must now be a Secret in `namespace`**, not in the release's namespace. `apiKey` is rendered there as `issassist-ai-bob-key`. |

**What changed for them.**
- New, and off unless `allowed: true` and `clusterScoped.create: true` (the default).
- **To run Bob, set `allowed: true`, plus `image` and `keyproxyImage`, both by digest.** Then set
  the key here or in the web GUI, and accept IBM's licence terms in Settings › AI analysis.
- **A Bob `existingSecret` created in the release's namespace before this release must be
  created again in `ai-bob-runs`.**
- The API pod now runs as the ServiceAccount `api`. Nothing else about it changes.
- The run namespace admits only IssAssist's own Bob run pods:
  - the two configured images (Bob, and the key sidecar), each started by its own
    entrypoint, with its own settings, and the files and folders IssAssist gives
    it, mounted where IssAssist mounts them;
  - pods that choose no node, scheduler, priority or runtime of their own.

  A pod an operator writes by hand is refused there, on purpose. It needs
  Kubernetes 1.30 or later.
- The run namespace's quota now limits CPU as well as memory. A pod an operator writes by hand is refused
  there; that is on purpose. It also caps the run pods at `aiAnalysis.maxConcurrent` + 1
  and their memory. **Needs Kubernetes 1.30 or later** (ValidatingAdmissionPolicy).

**Where the detail is.** [`docs/projects/2026-11-03-ai-bob-runs.md`](docs/projects/2026-11-03-ai-bob-runs.md)
and, for the API side, `issassist-api/docs/projects/2026-10-29-ai-analysis-api.md`.

### `api.avepointRunCheck` and `api.postgres.readonlyRole`: a daily check of the AvePoint collection

**What it is.** Every morning, 15 minutes after the AvePoint collection, a Job checks that
the collection wrote that day's figures. A Failed `avepoint-run-check` job in
`kubectl get jobs` means the collection did not; its log says whether the sync ran and
collected nothing, did not run at all, or whether the check itself could not read the
database. The check reads as its own login, `api-readonly`, which can read ten columns of
the AvePoint collection's own bookkeeping (which customers and services were collected, and
the status codes AvePoint replied with) and nothing else: not users, not the stored AvePoint
credentials, not AvePoint's replies themselves, and nothing it could change.

**Where it is.** `values.yaml`:

```yaml
api:
  postgres:
    readonlyRole:
      enabled: false   # creates the api-readonly login; only `true` turns it on
  avepointRunCheck:
    enabled: false     # needs readonlyRole.enabled
    schedule: "15 6 * * *"   # UTC
```

The login is created, or its password reset from the `api-postgres-readonly-auth` Secret,
by the Job `api-postgres-readonly-role`, which runs after every `helm install` and
`helm upgrade`. Its log ends with `api-readonly: role ready; reads 10 columns of
avepoint.snapshots and avepoint.raw_responses`. It changes only a login it created itself; if
a login by that name already exists, it says `ERROR: could not set up the role` and leaves
it alone.

**What changed for them.** Nothing unless turned on; both are off by default.

- **Turning on the check without the login fails the `helm upgrade`**, with a message that
  says which key to set.
- **On a fresh install the login is ready only after the next `helm upgrade`** if the API
  has not created its tables within 4 minutes. The Job says so in its log and never fails
  the release.
- **Turning `readonlyRole` off later leaves the login in the database.** It still has only
  read access to those ten columns.
- **Staging only, once:** the check used to be applied by hand from
  `k8s-avepoint-run-check.yaml`. Delete that CronJob and ConfigMap before the first upgrade
  that turns `avepointRunCheck` on, or Helm refuses to take them over:
  `kubectl -n issassist-staging delete cronjob,configmap avepoint-run-check`.

**Where the detail is.** [docs/projects/2026-11-03-avepoint-readonly-role.md](docs/projects/2026-11-03-avepoint-readonly-role.md).

### `aiAnalysis.debugWizard.enabled`: the AI debug wizard (IssAssist 2.0)

**What it is.** Turns on the AI debug wizard, a step-by-step view of one AI analysis that
shows real names next to their stand-ins. It is meant for a test installation such as
staging.

**Where it is.** `values.yaml`:

```yaml
aiAnalysis:
  debugWizard:
    enabled: false   # only `true` turns it on
```

Rendered as `IA_AI_DEBUG_WIZARD` in the `issassist-ai-analysis` ConfigMap. Editing that
ConfigMap with kubectl and restarting the API also turns it on or off, **until the next
`helm upgrade`, which puts the values.yaml setting back**.

**What changed for them.** Nothing: it is off by default, and anything but `true` (`yes`, a
missing key after `--reuse-values`) is off.

**Where the detail is.** issassist-api `docs/projects/2026-11-02-ai-debug-wizard.md`.

### `aiAnalysis.providers.<id>.apiKey` and a generated `IA_AI_SECRET_KEY` (IssAssist 2.0)

**What it is.** An AI provider's key can be given at installation either as a Secret you
created (`existingSecret`, preferred) or as the key itself (`apiKey`), in which case the
chart renders the Secret `issassist-ai-<id>-key`. A provider with neither can be given its
key later in the web GUI. **When Helm names a key, Helm wins: the web GUI shows it as "Set
by the installation (Helm)" and can neither replace nor remove it**, even if the named Secret
does not exist yet.

**Where it is.**

```yaml
aiAnalysis:
  providers:
    claude:
      existingSecret: ""   # a Secret you created, key "api-key", or
      apiKey: ""           # the key itself
```

A new Secret, `api-ai-secret-key`, is generated by kubernetes-secret-generator and given to
the API as `IA_AI_SECRET_KEY`. It encrypts keys entered in the web GUI.

**What changed for them.**
- **`apiKey` is stored by Helm in plaintext in the release** (`helm get values`, and a copy
  per revision), as for `imageCredentials`. Prefer `existingSecret`. When both are set,
  `apiKey` is used.
- **`api-ai-secret-key` must survive upgrades.** If it is deleted or changed, every key
  entered in the web GUI has to be entered again.
- **`claude.existingSecret` is now empty by default** (it named `issassist-ai-anthropic`).
  A named Secret means the installation owns the key, so the old default would have kept
  every installation from entering Claude's key in the web GUI. Set it if you use that Secret.
- IBM Bob's key, from Helm, is rendered in this namespace and never mounted into the API pod;
  only its name is, so the web GUI shows it as set. It is for Bob's own run pods (a later
  release).

**Where the detail is.** issassist-api `docs/projects/2026-10-29-ai-analysis-api.md`, section "Slice 1b".

### `aiAnalysis.*` and `global.darkSite`: what AI analysis may use (IssAssist 2.0)

**What it is.** AI analysis explains Storage Protect alerts with an AI (mission #463,
behind IssAssist Preview). These keys decide which AI providers this installation may use
at all, where the local one is, and the most an operator may spend per day. Whether a
provider is **on** is the operator's switch under Settings → Configuration → AI analysis.

**Where it is.** `values.yaml`:

```yaml
global:
  darkSite: false        # true: only providers inside this cluster may be used
aiAnalysis:
  maxDailyCapEur: 20     # the highest daily cap an operator may set
  maxConcurrent: 2
  providers:
    local:
      allowed: false
      endpoint: ""        # must be https://
      model: "qwen2.5:14b"
      existingSecret: ""  # optional bearer token, key "api-key"
    claude:
      allowed: false
      existingSecret: "issassist-ai-anthropic"   # key "api-key"
```

Rendered into the new ConfigMap `issassist-ai-analysis` and, for keys, into optional
`secretKeyRef`s on the API. A change restarts the API pod.

**What changed for them.** Nothing by default: every provider is `allowed: false`.
**To use Claude, create the Secret first** (`kubectl create secret generic
issassist-ai-anthropic --from-literal=api-key=…`) and set `claude.allowed: true`. The key
is never in `values.yaml`. **Every switch fails closed:** `darkSite` is off only for a
literal `false`. **Missing or null is dark**, so an upgrade with `--reuse-values` from a
chart without the key starts as a Dark Site until `global.darkSite: false` is set; a
provider is allowed only for `allowed: true`. **`maxDailyCapEur: 0` means 0**: nothing
outside this cluster can run. **A local endpoint that is not `https://`, or that carries
credentials (`user:pass@`) or a query string, fails the install** with a message that does
not repeat the value. Keys are wired only for the known providers (`local`, `claude`,
`gemini`, `copilot`); any other name under `providers`, `BOB` included, is
ignored. There is no switch for plain HTTP. **The API pod never receives the
IBM Bob key**, even if `bob.existingSecret` is set.

Render checks for every one of these cases: `bash scripts/check_ai_analysis_render.sh`
(this repository has no CI, so run it before a release).

**Where the detail is.** issassist-api `docs/projects/2026-10-29-ai-analysis-api.md`.

### `global.preview.allowed`: whether IssAssist Preview may be turned on

**What it is.** IssAssist Preview turns on the IssAssist 2.0 features, which are not
verified yet. This key decides whether an operator may turn it on at all. Whether it
*is* on is the operator's switch under Settings → IssAssist, after a warning, and it is
off until they turn it on.

**Where it is.** `values.yaml`:

```yaml
global:
  preview:
    allowed: true   # false locks Preview off
```

Rendered as `IA_PREVIEW_ALLOWED` on the API.

**What changed for them.** Nothing by default: the key is `true`, and Preview itself is
off after install and upgrade. **A site that must not run unverified features should set
`allowed: false`**; the switch is then shown locked. Any value other than `true` locks it,
so a typo errs on the safe side. An upgrade from a chart without the key behaves as `true`.

**Where the detail is.** [docs/projects/2026-10-29-issassist-preview.md](docs/projects/2026-10-29-issassist-preview.md)

### `tsmAgent.tapeSync.concurrency`: how many servers the tape sync asks at once

**What it is.** A cap on how many Storage Protect servers the tape sync asks at the same
time. Every question goes through the one Operations Center, so on a large estate this is
what keeps the sync from opening dozens of command sessions on it at once.

**Where it is.** `values.yaml`:

```yaml
tsmAgent:
  tapeSync:
    concurrency: 4   # 1 to 32
```

Rendered as `IA_TAPE_SYNC_CONCURRENCY` on the tsm-agent.

**What changed for them.** New. The default, 4, is also what the agent uses when the key is
absent, so an upgrade with `--reuse-values` (which keeps the old values, without this key)
behaves the same. A value outside 1 to 32 falls back to 4 and the agent logs a warning.

**Where the detail is.** `issassist-tsm-agent/docs/projects/2026-10-22-tape-v1-2-part2.md`.

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
