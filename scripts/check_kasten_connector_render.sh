#!/usr/bin/env bash
# Render checks for the Kasten connector's ClusterRole (IA-0031 inventory). Run from the
# chart root:   bash scripts/check_kasten_connector_render.sh
set -u
fail=0
render() { helm template t . -s templates/kasten/connector.yaml --set kastenConnector.enabled=true "$@" 2>&1; }
expect() { local what=$1 pattern=$2; shift 3
  if render "$@" | grep -qE -- "$pattern"; then echo "ok   $what"; else echo "FAIL $what"; fail=1; fi; }
expect_not() { local what=$1 pattern=$2; shift 3
  if render "$@" | grep -qE -- "$pattern"; then echo "FAIL $what"; fail=1; else echo "ok   $what"; fi; }
inv=(--set kastenConnector.inventory=true)
expect_not "no inventory rules by default"            'resources: \["pods"\]' --
expect_not "inventory yes is not true"                'resources: \["pods"\]' -- --set kastenConnector.inventory=yes
expect_not "inventory removed (older release) is off" 'resources: \["pods"\]' -- --set kastenConnector.inventory=null
expect "inventory true grants pods"                   'resources: \["pods"\]' -- "${inv[@]}"
expect "and workloads"                                'resources: \["deployments", "statefulsets", "daemonsets"\]' -- "${inv[@]}"
expect "and Kanister blueprints"                      'resources: \["blueprints"\]' -- "${inv[@]}"
expect "and blueprint bindings"                       'resources: \["blueprintbindings"\]' -- "${inv[@]}"
expect "CRDs are list only"                           'resources: \["customresourcedefinitions"\]' -- "${inv[@]}"
expect_not "never secrets"                            'secrets' -- "${inv[@]}"
expect_not "never configmaps"                         'configmaps' -- "${inv[@]}"
expect_not "never a write verb"                       '"(create|update|patch|delete|deletecollection|escalate|bind|impersonate)"' -- "${inv[@]}"
# List only (security review L2): turning the inventory on adds no `get` rule.
gets_off=$(render | grep -c '"get"')
gets_on=$(render "${inv[@]}" | grep -c '"get"')
if [ "$gets_off" = "$gets_on" ]; then echo "ok   the inventory rules are list only"
else echo "FAIL the inventory rules are list only ($gets_off vs $gets_on get rules)"; fail=1; fi
expect_not "never exec into pods"                     'pods/exec|pods/log|pods/attach' -- "${inv[@]}"
# Pod logs for support (IA-0026 slice 2): a namespaced Role, opt-in, nothing more.
pl=(--set kastenConnector.podLogs.enabled=true)
expect_not "no pod-log Role by default"               'kind: Role$' --
expect_not "podLogs yes is not true"                  'kind: Role$' -- --set kastenConnector.podLogs.enabled=yes
expect_not "podLogs removed (older release) is off"   'kind: Role$' -- --set kastenConnector.podLogs=null
expect "podLogs true renders a Role"                  'kind: Role$' -- "${pl[@]}"
expect "in kasten-io by default"                      'namespace: kasten-io' -- "${pl[@]}"
expect "in the namespace given"                       'namespace: k10$' -- "${pl[@]}" --set kastenConnector.podLogs.namespace=k10
expect "bound to the connector"                       'kind: RoleBinding' -- "${pl[@]}"
expect "pods/log get"                                 'resources: \["pods/log"\]' -- "${pl[@]}"
expect_not "never exec, attach or port-forward"       'pods/exec|pods/attach|pods/portforward' -- "${pl[@]}" "${inv[@]}"
expect_not "never secrets with pod logs"              'secrets' -- "${pl[@]}"
expect_not "never a write verb with pod logs"         '"(create|update|patch|delete|deletecollection|escalate|bind|impersonate)"' -- "${pl[@]}"
roles=$(render "${pl[@]}" | grep -c '^kind: ClusterRole$')
if [ "$roles" = "1" ]; then echo "ok   pod logs add no ClusterRole"; else echo "FAIL pod logs add no ClusterRole ($roles)"; fail=1; fi
cr_off=$(render | awk '/^kind: ClusterRole$/,/^---/' | md5sum)
cr_on=$(render "${pl[@]}" | awk '/^kind: ClusterRole$/,/^---/' | md5sum)
if [ "$cr_off" = "$cr_on" ]; then echo "ok   the ClusterRole is unchanged by pod logs"
else echo "FAIL the ClusterRole is unchanged by pod logs"; fail=1; fi
if render "${pl[@]}" --set kastenConnector.podLogs.namespace='Bad_NS' | grep -q 'must be a Kubernetes namespace name'
then echo "ok   a namespace that is not a name fails the render"
else echo "FAIL a namespace that is not a name fails the render"; fail=1; fi
# The API gets the namespace through its ConfigMap (Kubernetes-first).
api_cm() { helm template t . -s templates/issassist/api/kasten-configmap.yaml "$@" 2>&1; }
if api_cm | grep -q 'IA_KASTEN_POD_LOGS_NAMESPACE: "kasten-io"'; then echo "ok   API gets kasten-io by default"
else echo "FAIL API gets kasten-io by default"; fail=1; fi
if api_cm --set kastenConnector.podLogs.namespace=k10 | grep -q 'IA_KASTEN_POD_LOGS_NAMESPACE: "k10"'; then echo "ok   API gets the namespace given"
else echo "FAIL API gets the namespace given"; fail=1; fi
if api_cm --set kastenConnector=null | grep -q 'IA_KASTEN_POD_LOGS_NAMESPACE: "kasten-io"'; then echo "ok   API default survives a release without the key"
else echo "FAIL API default survives a release without the key"; fail=1; fi
if helm template t . -s templates/issassist/api/deployment.yaml 2>&1 | grep -q 'name: issassist-kasten$'; then echo "ok   API envFrom the kasten ConfigMap"
else echo "FAIL API envFrom the kasten ConfigMap"; fail=1; fi
exit $fail
