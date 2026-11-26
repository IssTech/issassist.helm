---
release: 2.0.0
date: 2026/11/26
---
### Kasten restore-test key and ransomware scan settings (IA-0050 #539, IA-0051 #540) (2026/11/26)

- **What it is:** The identity IssAssist uses to restore Kasten backups into one restore-test
  namespace and check them, and the settings for the YARA ransomware scan. A second key, never
  the read-only connector's.
- **Where it is:** `values.yaml` → `kastenConnector.restoreTests.*` (`enabled`, `namespace`,
  `createNamespace`, `serviceAccountName`, `image`, `timeoutMinutes`, `keepOnFailureMaxHours`,
  `maxReplicas`, `quota`) and `kastenConnector.yara.*` (`enabled`, `maxFileSizeMiB`); new
  template `templates/kasten/restore-tests.yaml`; the API gets them as `IA_KASTEN_RT_*` /
  `IA_KASTEN_YARA_*` through the `issassist-kasten` ConfigMap, and a new generated Secret
  `api-kasten-rt-secret-key` encrypts the stored keys.
- **What changed for them:** Nothing until `kastenConnector.restoreTests.enabled: true` (only an
  explicit true). Then, in the restore-test namespace only: a ServiceAccount and its token, a
  RoleBinding to `admin`, a Role to create/get/list/watch RestoreActions (no delete, no
  update), deny-all NetworkPolicies (the scanner gets no network at all), a ResourceQuota (no
  LoadBalancers or NodePorts) and a LimitRange; plus one ClusterRole that can only get/list
  restore points. **No cluster-wide namespace rights and no admission policy.** The connector is
  unchanged. `default`, `kube-*`, `kasten-io` and the release namespace are refused as the
  restore-test namespace, because teardown empties it.
- **Operator steps:** **create the namespace (or `createNamespace: true`) and exclude it from
  every Kasten policy; apply the template on each Kasten cluster that runs restore tests
  (`helm template … -s templates/kasten/restore-tests.yaml | kubectl apply -f -`); register the
  `issassist-restore-test-token` token for that cluster in IssAssist; set `image` to the
  `issassist-restore-scanner` digest.** Treat the token as sensitive as the applications'
  Secrets: a restore copies them into the namespace.
- **Detail:** [issassist-api docs/projects/2026-11-26-kasten-restore-tests.md](https://github.com/IssTech/issassist-api/blob/review/docs/projects/2026-11-26-kasten-restore-tests.md)
