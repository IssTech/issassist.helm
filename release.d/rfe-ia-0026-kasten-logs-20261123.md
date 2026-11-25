---
release: 1.6.0
date: 2026/11/23
---
### Opt-in read access to K10's pod logs for support (IA-0026, #493) (2026/11/23)

- **What it is:** A switch that lets IssAssist read Veeam Kasten's own pod logs on a monitored
  cluster, so they can be added (anonymised) to a support .zip. Off by default.
- **Where it is:** `values.yaml` → `kastenConnector.podLogs.enabled` (default `false`) and
  `kastenConnector.podLogs.namespace` (default `kasten-io`). With `enabled: true` the connector
  template (`templates/kasten/connector.yaml`) adds a **Role and RoleBinding in that namespace
  only**: `list pods` and `get pods/log`, nothing else — no exec, no Secrets, no cluster-wide
  rule. The namespace is also passed to the API through the new ConfigMap `issassist-kasten`
  (`IA_KASTEN_POD_LOGS_NAMESPACE`).
- **What changed for them:** Nothing until switched on; the existing ClusterRole is unchanged.
  **To grant it, re-apply the connector on each Kasten cluster where you want it** with
  `--set kastenConnector.podLogs.enabled=true` (the cluster list in IssAssist then shows *Pod logs
  for support: Granted*). A namespace value that is not a Kubernetes name fails the render.
- **Detail:** [issassist-api docs/projects/2026-11-23-ia-0026-kasten-logs.md](https://github.com/IssTech/issassist-api/blob/review/docs/projects/2026-11-23-ia-0026-kasten-logs.md)
