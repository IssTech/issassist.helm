# 2026-11-12 Kasten workload inventory: connector read rights (IA-0031)

Mission IssTech/isstech-issues#512, mockup v2 tab 4 (https://claude.ai/artifact/XacK6ueZuAg8SKwUB5y8KG).

## What

`kastenConnector.inventory` (default false). With an explicit `true` the connector
ClusterRole also grants get/list on pods, apps deployments/statefulsets/daemonsets, Kanister
`cr.kanister.io/blueprints`, Kasten `config.kio.kasten.io/blueprintbindings`, and list on
`apiextensions.k8s.io/customresourcedefinitions` (to see which database operators are
installed: CloudNativePG, Percona, Strimzi …).

## Why fail closed, and the trade-off

New read scope on customer clusters. A missing key (`--reuse-values` from an older
release), `yes` or a typo keeps it off.

RBAC cannot grant pods without `spec.containers[].env`, so the token can read literal env
values. The API's parser keeps an allow-list (image, ports, probe type, replicas, owner,
claim names) and discards everything else before storing; a test proves no env, command,
args or annotation value reaches the database. Secrets and ConfigMaps stay unreadable,
so env values taken from them (`valueFrom`) are never resolved.

## Tests

`scripts/check_kasten_connector_render.sh`: 12 cases. Watched failing: with the condition
changed to "anything but false" (3 fail) and with `secrets` added to the pods rule (1 fails).

## Security review, 2026/11/12

- **L2:** the inventory rules are `list` only; `get` was dropped (the daily collection lists
  each kind once). Render check: turning the inventory on adds no `get` rule (watched failing
  with `get` put back on pods).
- **Accepted risk, stated in values.yaml and the template:** the pod list carries literal
  environment values over TLS to the IssAssist API. IssAssist's allow-list discards them
  before storing anything, but they cross the wire. Kubernetes RBAC cannot grant pods
  without their spec.
