# IBM Bob's run namespace in the chart (#463 slice 4)

2026/11/03. Mockup: `issassist-api/docs/mockups/2026-11-03-ai-bob-slice4.html`, approved the
same day. The API side, its tests and its security pass are in
`issassist-api/docs/projects/2026-10-29-ai-analysis-api.md`, section "Slice 4".

## What was built

- `templates/issassist/api/ai-bob-runs.yaml`, rendered with `clusterScoped.create` and
  `aiAnalysis.providers.bob.allowed: true`:
  - the namespace, labelled for the `restricted` Pod Security level;
  - a NetworkPolicy for every pod in it: no ingress; egress to kube-dns on 53, and to TCP
    443 outside 10/8, 172.16/12, 192.168/16, 100.64/10, 169.254/16 and 127/8;
  - the Role `issassist-bob-runner`: pods create, get, list, delete; pods/log get; secrets
    create and delete only;
  - its RoleBinding, to the ServiceAccount `api` in the release namespace;
  - the Secret `issassist-ai-bob-key`, when `bob.apiKey` is set;
  - a ResourceQuota: pods `maxConcurrent + 1` (a Settings › Test beside the analyses),
    and `limits.memory` 512 Mi each;
  - two ValidatingAdmissionPolicies with their bindings (security review, 2026/11/03).
    - **Pods:** only the pod `providers/bob.py` builds is admitted:
      - the configured image, which must be pinned by digest;
      - no `command`, and `args` exactly `--max-turns <n> --max-cost <n>`;
      - one container, with no init or ephemeral containers, hooks, probes or `envFrom`;
      - the single env var `BOB_API_KEY`, taken from Helm's key or the pod's own Secret;
      - volumes limited to that Secret and emptyDirs;
      - no ServiceAccount token, a deadline of at most `timeoutSeconds`, and
        `restartPolicy: Never`;
      - no `nodeName`, `hostAliases` or `dnsConfig`.
    - **Secrets:** the API's account may create, change and delete only `bob-run-*`.
      Helm's own key Secret is created by whoever runs Helm and is not restricted.
- `templates/issassist/api/serviceaccount.yaml`, the API's own ServiceAccount `api`, with
  `serviceAccountName: api` on the API Deployment.
- `ai-analysis-configmap.yaml`: the new `IA_AI_BOB_*` values.
- `ai-provider-keys.yaml`: Bob's `apiKey` Secret is no longer rendered in the release
  namespace. A pod can only use a Secret in its own namespace.

## Decisions and traps

- **Only `allowed: true` counts,** and everything is read through `default dict`, so
  `--reuse-values` from a release without these keys renders the defaults.
- **Numbers are not read with `default`.** Sprig treats 0 as empty, and a limit of 0 is a
  choice.
- **The namespace is refused** when it is the release's own, `default` or `kube-*`. The
  Role lets the API start pods there.
- **IPv6 egress is not opened.** No rule means denied.
- **The excepted IPv4 ranges** are the private, shared, link-local and loopback ones,
  plus `0.0.0.0/8`, `192.0.0.0/24` and `198.18.0.0/15`.
- **The policies are the fence, not the Role.** The Role must let the API create pods
  and read their logs, so what a pod may be is decided at admission. Change
  `pod_body()` in the API and the policy together.
- **No CiliumNetworkPolicy:** decision 1 is 443 now, with a host-name lock later, and
  Cilium is the provider's to configure.

## Tests

`bash scripts/check_ai_analysis_render.sh` runs 74 render cases, 41 of them new.

`scripts/check_bob_admission_live.sh` applies the chart's Bob resources to a throwaway
API server and asks it, with `--dry-run=server` and as the API's account, to create pods
and Secrets. It was run on 2026/11/03 against k3s v1.36.5 (control plane only, in Docker),
and passed 24 checks:
- the pod as built is admitted, with Helm's key and with the run's own Secret;
- 19 variants are refused: a `command`, an extra env var, another Secret, another
  image, an extra argument, a non-number cost, a token, Helm's key as a volume, a hook,
  a probe, two containers, an init container, no deadline, a longer one, `Always`, a
  node, hostAliases, no label, and `envFrom`;
- the API may create `bob-run-*` Secrets, and no other;
- the API may not delete Helm's key.

Six breaks of the policy each made it fail: `command`, env, image, the Secret name,
hooks, and volumes.

Each of these deliberate breaks made at least one render case fail:
- `get` on Secrets;
- open ingress;
- 10/8 reachable;
- link-local reachable;
- port 80 reachable;
- `baseline` instead of `restricted`;
- `allowed: yes` counted;
- the `clusterScoped` check removed;
- `pods/exec` granted;
- the binding to `default`;
- the key in the release namespace;
- no ServiceAccount on the API;
- `| default 5` for the per-run limit;
- the release-namespace guard removed;
- the `kube-*`/`default` guard removed;
- Bob added to the API pod's key list;
- an image by tag accepted;
- the quota without its + 1;
- `198.18.0.0/15` removed;
- no `timeoutSeconds` bound;
- `Warn` instead of `Deny`;
- the Secret policy applied to everyone.

The chart repo has no CI, so this runs by hand.
