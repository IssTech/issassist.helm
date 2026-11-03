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
  - the Secret `issassist-ai-bob-key`, when `bob.apiKey` is set.
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
- **No CiliumNetworkPolicy:** decision 1 is 443 now, with a host-name lock later, and
  Cilium is the provider's to configure.

## Tests

`bash scripts/check_ai_analysis_render.sh` runs 58 render cases, 25 of them new. Each of
these deliberate breaks made at least one case fail:
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
- Bob added to the API pod's key list.

The chart repo has no CI, so this runs by hand.
