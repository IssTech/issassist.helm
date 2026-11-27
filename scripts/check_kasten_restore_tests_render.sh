#!/usr/bin/env bash
# Render checks for the Kasten restore-test key (IA-0050 #539, IA-0051 #540). Run from
# the chart root:   bash scripts/check_kasten_restore_tests_render.sh
set -u
fail=0
render() { helm template t . -s templates/kasten/restore-tests.yaml "$@" 2>&1; }
on=(--set kastenConnector.restoreTests.enabled=true)
ok() { echo "ok   $1"; }
no() { echo "FAIL $1"; fail=1; }
expect() { local what=$1 pattern=$2; shift 3
  if render "$@" | grep -qE -- "$pattern"; then ok "$what"; else no "$what"; fi; }
expect_not() { local what=$1 pattern=$2; shift 3
  if render "$@" | grep -qE -- "$pattern"; then no "$what"; else ok "$what"; fi; }

if render | grep -q 'could not find template'; then ok "nothing rendered by default"; else no "nothing rendered by default"; fi
if render --set kastenConnector.restoreTests.enabled=yes | grep -q 'could not find template'
then ok "only an explicit true renders"; else no "only an explicit true renders"; fi
if render --set kastenConnector=null | grep -q 'could not find template'
then ok "a release without the key renders nothing"; else no "a release without the key renders nothing"; fi

out=$(render "${on[@]}")
# RestoreActions: a Role in the restore-test namespace, never a ClusterRole.
cr=$(echo "$out" | awk '/^kind: ClusterRole$/,/^---/')
if echo "$cr" | grep -q 'restoreactions'; then no "restoreactions are not in the ClusterRole"; else ok "restoreactions are not in the ClusterRole"; fi
if echo "$cr" | grep -q 'resources: \["restorepoints", "restorepointcontents"\]' \
   && echo "$cr" | grep -q 'verbs: \["get", "list"\]' && [ "$(echo "$cr" | grep -c 'verbs:')" = 1 ]
then ok "the ClusterRole only reads restore points"; else no "the ClusterRole only reads restore points"; fi
role=$(echo "$out" | awk '/^kind: Role$/,/^---/')
if echo "$role" | grep -q 'namespace: issassist-restore-test' \
   && echo "$role" | grep -q 'verbs: \["create", "get", "list", "watch"\]'
then ok "RestoreActions only in the restore-test namespace, no delete/update"; else no "RestoreActions only in the restore-test namespace, no delete/update"; fi
if echo "$role" | grep -q 'resources: \["httproutes"\]' && echo "$role" | grep -q 'resources: \["routes"\]'
then ok "exposing routes can be removed in the restore-test namespace"; else no "exposing routes can be removed in the restore-test namespace"; fi
expect_not "never namespaces cluster-wide"   'resources: \["namespaces"\]' -- "${on[@]}"
expect_not "no admission policy"             'ValidatingAdmissionPolicy' -- "${on[@]}"
# Kasten 9 accepts transforms on a RestoreAction only from a caller allowed to create
# TransformSets in Kasten's namespace; that would let the key make Kasten patch what it
# restores, with Kasten's rights. IssAssist sends none and refuses a key that could.
expect_not "no TransformSet rights (Kasten transforms)" 'transformsets' -- "${on[@]}"
expect_not "nothing in Kasten's namespace"   'namespace: kasten-io' -- "${on[@]}"
# No registry Secret in the restore-test namespace: any restored pod could mount it,
# and teardown empties Secrets there by kind (security review M2).
expect_not "no imagePullSecrets for the restore-test namespace" '(imagePullSecrets|dockerconfigjson)' -- "${on[@]}"
expect_not "never escalate/bind/impersonate" '"(escalate|bind|impersonate)"' -- "${on[@]}"
expect "admin only by RoleBinding"           'name: admin' -- "${on[@]}"
if [ "$(echo "$out" | grep -c '^kind: ClusterRoleBinding$')" = 1 ] && ! echo "$out" | awk '/^kind: ClusterRoleBinding$/,/^---/' | grep -q 'name: admin'
then ok "admin is never bound cluster-wide"; else no "admin is never bound cluster-wide"; fi
expect "the deny-all policy IssAssist requires" 'name: issassist-restore-test-deny-all' -- "${on[@]}"
expect "the scanner is excluded from the intra-namespace policy" 'values: \["yara-scanner"\]' -- "${on[@]}"
expect "no LoadBalancers in the quota"       'services.loadbalancers: "0"' -- "${on[@]}"
expect "the guard label on what teardown keeps" 'issassist.io/restore-test-guard: "true"' -- "${on[@]}"
expect_not "no Namespace unless asked"       '^kind: Namespace$' -- "${on[@]}"
expect "createNamespace renders it labelled" 'issassist.io/restore-test: "true"' -- "${on[@]}" --set kastenConnector.restoreTests.createNamespace=true
expect "in the namespace given"              'namespace: rt-lab$' -- "${on[@]}" --set kastenConnector.restoreTests.namespace=rt-lab
for bad in default kube-system kube-foo kasten-io Bad_NS; do
  if render "${on[@]}" --set kastenConnector.restoreTests.namespace=$bad | grep -qE 'must be a (namespace set aside|Kubernetes namespace name)'
  then ok "namespace $bad is refused"; else no "namespace $bad is refused"; fi
done
# The key never lives where restored workloads land (security review H1).
key=$(helm template t . --namespace issassist-key -s templates/kasten/restore-tests.yaml "${on[@]}" 2>&1)
sa=$(echo "$key" | awk '/^kind: ServiceAccount$/,/^---/'; echo "$key" | awk '/^kind: Secret$/,/^---/')
if echo "$sa" | grep -q 'namespace: issassist-key' && ! echo "$sa" | grep -q 'namespace: issassist-restore-test'
then ok "the key's ServiceAccount and token are outside the restore-test namespace"
else no "the key's ServiceAccount and token are outside the restore-test namespace"; fi
if [ "$(echo "$key" | grep -c 'namespace: issassist-key')" -ge 5 ]; then ok "every binding names the key in its own namespace"
else no "every binding names the key in its own namespace"; fi
expect "createNamespace enforces Pod Security baseline" 'pod-security.kubernetes.io/enforce: baseline' -- "${on[@]}" --set kastenConnector.restoreTests.createNamespace=true
# The connector stays read-only whatever restore tests say.
con() { helm template t . -s templates/kasten/connector.yaml --set kastenConnector.enabled=true "$@" 2>&1; }
if [ "$(con | md5sum)" = "$(con "${on[@]}" | md5sum)" ]; then ok "the connector is unchanged by restore tests"
else no "the connector is unchanged by restore tests"; fi
# Values -> ConfigMap -> env (Kubernetes-first).
cm() { helm template t . -s templates/issassist/api/kasten-configmap.yaml "$@" 2>&1; }
cm | grep -q 'IA_KASTEN_RT_ENABLED: "false"' && ok "API: off by default" || no "API: off by default"
cm | grep -q 'IA_KASTEN_YARA_ENABLED: "false"' && ok "API: yara off by default" || no "API: yara off by default"
cm "${on[@]}" --set kastenConnector.yara.enabled=true | grep -q 'IA_KASTEN_YARA_ENABLED: "true"' && ok "API: yara on" || no "API: yara on"
cm "${on[@]}" --set kastenConnector.restoreTests.image=img@sha256:1 | grep -q 'IA_KASTEN_RT_IMAGE: "img@sha256:1"' && ok "API: image passed" || no "API: image passed"
cm | grep -q 'IA_KASTEN_RT_KASTEN_NAMESPACE: "kasten-io"' && ok "API: Kasten's namespace defaults to kasten-io" || no "API: Kasten's namespace defaults to kasten-io"
cm "${on[@]}" --set kastenConnector.restoreTests.kastenNamespace=k10 | grep -q 'IA_KASTEN_RT_KASTEN_NAMESPACE: "k10"' && ok "API: Kasten's namespace passed" || no "API: Kasten's namespace passed"
helm template t . -s templates/issassist/api/deployment.yaml 2>&1 | grep -q 'name: api-kasten-rt-secret-key' && ok "API: encryption key from its Secret" || no "API: encryption key from its Secret"
exit $fail
