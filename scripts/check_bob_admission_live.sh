#!/usr/bin/env bash
# Live check of IBM Bob's run-namespace admission policy (#463 slice 4), against a
# throwaway Kubernetes API server of 1.30 or later: k3s, kind or k3d. Never staging.
#
#   KUBECTL="kubectl --kubeconfig /path/to/throwaway.yaml" bash scripts/check_bob_admission_live.sh [pod.json ...]
#
# It applies this chart's Bob resources (namespace, quota, Role, policies) to that
# server with the release namespace "issassist", then asks the server, with
# --dry-run=server and as the API's ServiceAccount, to create pods and Secrets.
# Each pod.json given is one the API built (providers/bob.py pod_body) and must be
# admitted. Exits non-zero on the first wrong answer.
set -u
K=${KUBECTL:-kubectl}
REL=issassist
NS=ai-bob-runs
IMAGE="ghcr.io/isstech/issassist-bob-runner@sha256:$(printf '%064d' 7)"
PROXY="ghcr.io/isstech/issassist-bob-keyproxy@sha256:$(printf '%064d' 8)"
GATEWAY="https://api.us-east.bob.ibm.com"
API="system:serviceaccount:${REL}:api"
fail=0
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

$K create namespace "$REL" --dry-run=client -o yaml | $K apply -f - >/dev/null
$K -n "$REL" create serviceaccount api --dry-run=client -o yaml | $K apply -f - >/dev/null
helm template t . --namespace "$REL" --set aiAnalysis.providers.bob.allowed=true \
  --set "aiAnalysis.providers.bob.image=$IMAGE" --set "aiAnalysis.providers.bob.keyproxyImage=$PROXY" \
  --set aiAnalysis.providers.bob.existingSecret=issassist-ai-bob-key \
  --show-only templates/issassist/api/ai-bob-runs.yaml > "$work/bob.yaml"
$K apply -f "$work/bob.yaml" >/dev/null || { echo "FAIL could not apply the chart's Bob resources"; exit 1; }
sleep 2  # policies are compiled asynchronously
# Helm's key Secret, created by whoever runs Helm: the policy must not get in the way.
# Its value is made up here, at runtime: a literal would be flagged by secret scanners.
$K -n "$NS" create secret generic issassist-ai-bob-key \
  --from-literal="api-key=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')" \
  --dry-run=client -o yaml | $K apply -f - >/dev/null || { echo "FAIL the admin could not create Helm's key"; fail=1; }

pod() {  # pod <name> [python patch]: the run pod as providers/bob.py builds it
  python3 - "$1" "$IMAGE" "$PROXY" "$GATEWAY" "${2:-}" <<'PY'
import json, sys
name, image, proxy, gateway, patch = sys.argv[1:6]
locked = {"allowPrivilegeEscalation": False, "readOnlyRootFilesystem": True,
          "capabilities": {"drop": ["ALL"]}}
pod = {"apiVersion": "v1", "kind": "Pod",
       "metadata": {"name": name, "labels": {"app.kubernetes.io/name": "bob-run"}},
       "spec": {"restartPolicy": "Never", "activeDeadlineSeconds": 180,
                "automountServiceAccountToken": False, "enableServiceLinks": False,
                "securityContext": {"runAsNonRoot": True, "runAsUser": 1000, "runAsGroup": 1000,
                                    "seccompProfile": {"type": "RuntimeDefault"}},
                "initContainers": [{"name": "keyproxy", "image": proxy, "restartPolicy": "Always",
                                    "env": [{"name": "KEYPROXY_REAL_KEY", "valueFrom": {"secretKeyRef": {"name": name, "key": "api-key"}}},
                                            {"name": "KEYPROXY_FAKE_KEY", "valueFrom": {"secretKeyRef": {"name": name, "key": "fake-key"}}},
                                            {"name": "KEYPROXY_UPSTREAM", "value": gateway}],
                                    "volumeMounts": [{"name": "proxy-tls", "mountPath": "/run/keyproxy", "readOnly": True}],
                                    "securityContext": locked, "resources": {"limits": {"memory": "96Mi"}}}],
                "containers": [{"name": "bob", "image": image,
                                "args": ["--max-turns", "3", "--max-cost", "5.00"],
                                "env": [{"name": "BOB_API_KEY", "value": "fake-0123456789abcdef"},
                                        {"name": "BOB_GATEWAY_URL", "value": "https://localhost:8443"},
                                        {"name": "NODE_EXTRA_CA_CERTS", "value": "/work/ca.crt"}],
                                "volumeMounts": [{"name": "work", "mountPath": "/work", "readOnly": True},
                                                 {"name": "home", "mountPath": "/home/bob"}],
                                "securityContext": locked, "resources": {"limits": {"memory": "512Mi"}}}],
                "volumes": [{"name": "work", "secret": {"secretName": name, "items": [
                                {"key": "prompt.txt", "path": "prompt.txt"}, {"key": "ca.crt", "path": "ca.crt"}]}},
                            {"name": "proxy-tls", "secret": {"secretName": name, "items": [
                                {"key": "tls.crt", "path": "tls.crt"}, {"key": "tls.key", "path": "tls.key"}]}},
                            {"name": "home", "emptyDir": {}}]}}
c = pod["spec"]["containers"][0]
k = pod["spec"]["initContainers"][0]
exec(patch)
print(json.dumps(pod))
PY
}
admitted() {  # admitted <expect yes|no> <description> <file>
  local out
  out=$($K --as="$API" --as-group=system:serviceaccounts -n "$NS" create --dry-run=server -f "$3" 2>&1)
  if [ $? -eq 0 ]; then got=yes; else got=no; fi
  if [ "$got" = "$1" ]; then echo "ok   $2"; else echo "FAIL $2: $out"; fail=1; fi
}
check_pod() {  # check_pod <expect> <description> <python patch>
  pod bob-run-check "$3" > "$work/p.json"; admitted "$1" "$2" "$work/p.json"
}

check_pod yes "the run pod as built is admitted" ""
check_pod yes "the run pod with Helm's key is admitted" 'k["env"][0]["valueFrom"]["secretKeyRef"]["name"]="issassist-ai-bob-key"'
# The attack the review found: a command that prints the environment, read back from the log.
check_pod no  "bob with a command is refused"         'c["command"]=["sh","-c","cat /proc/self/environ"]'
check_pod no  "keyproxy with a command is refused"    'k["command"]=["sh","-c","cat /proc/self/environ"]'
check_pod no  "keyproxy with args is refused"         'k["args"]=["x"]'
check_pod no  "bob with an extra env var is refused"  'c["env"].append({"name":"X","value":"1"})'
check_pod no  "keyproxy with an extra env var is refused" 'k["env"].append({"name":"X","value":"1"})'
# The real key, in any form, near bob (mockup §9).
check_pod no  "bob reading the real key is refused"   'c["env"][0]={"name":"BOB_API_KEY","valueFrom":{"secretKeyRef":{"name":"issassist-ai-bob-key","key":"api-key"}}}'
check_pod no  "bob reading the run Secret is refused" 'c["env"][0]={"name":"BOB_API_KEY","valueFrom":{"secretKeyRef":{"name":"bob-run-check","key":"api-key"}}}'
check_pod no  "the key as a bob file is refused"      'pod["spec"]["volumes"][0]["secret"]["items"].append({"key":"api-key","path":"k"})'
check_pod no  "the TLS key as a bob file is refused"  'pod["spec"]["volumes"][0]["secret"]["items"].append({"key":"tls.key","path":"k"})'
check_pod no  "the whole run Secret as a volume is refused" 'del pod["spec"]["volumes"][0]["secret"]["items"]'
check_pod no  "bob mounting the TLS pair is refused"  'c["volumeMounts"].append({"name":"proxy-tls","mountPath":"/x"})'
check_pod no  "a shared process namespace is refused" 'pod["spec"]["shareProcessNamespace"]=True'
check_pod no  "Helm's key as a volume is refused"     'pod["spec"]["volumes"].append({"name":"k","secret":{"secretName":"issassist-ai-bob-key"}})'
check_pod no  "keyproxy forwarding elsewhere is refused" 'k["env"][2]["value"]="https://elsewhere.example"'
check_pod no  "bob talking past the sidecar is refused" 'c["env"][1]["value"]="https://api.us-east.bob.ibm.com"'
check_pod no  "keyproxy reading another Secret is refused" 'k["env"][0]["valueFrom"]["secretKeyRef"]["name"]="other"'
check_pod no  "no sidecar is refused"                 'del pod["spec"]["initContainers"]'
check_pod no  "another sidecar image is refused"      'k["image"]="busybox@sha256:"+"0"*64'
check_pod no  "a sidecar that is not native is refused" 'del k["restartPolicy"]'
check_pod no  "another image is refused"              'c["image"]="busybox@sha256:"+"0"*64'
check_pod no  "an extra argument is refused"          'c["args"]=c["args"]+["--yolo"]'
check_pod no  "a non-number max-cost is refused"      'c["args"][3]="1;id"'
check_pod no  "a ServiceAccount token is refused"     'pod["spec"]["automountServiceAccountToken"]=True'
check_pod no  "a postStart hook is refused"           'k["lifecycle"]={"postStart":{"exec":{"command":["sh","-c","env"]}}}'
check_pod no  "an exec probe is refused"              'c["livenessProbe"]={"exec":{"command":["env"]}}'
check_pod no  "a second container is refused"         'pod["spec"]["containers"].append(dict(c, name="two"))'
check_pod no  "no deadline is refused"                'del pod["spec"]["activeDeadlineSeconds"]'
check_pod no  "a longer deadline is refused"          'pod["spec"]["activeDeadlineSeconds"]=100000'
check_pod no  "restartPolicy Always is refused"       'pod["spec"]["restartPolicy"]="Always"'
check_pod no  "a pinned node is refused"              'pod["spec"]["nodeName"]="n1"'
check_pod no  "hostAliases are refused"               'pod["spec"]["hostAliases"]=[{"ip":"10.0.0.1","hostnames":["localhost"]}]'
check_pod no  "a pod without the label is refused"    'pod["metadata"]["labels"]={}'
check_pod no  "envFrom is refused"                    'k["envFrom"]=[{"secretRef":{"name":"bob-run-check"}}]'

secret() {  # secret <expect> <description> <name> [as]
  $K -n "$NS" create secret generic "$3" --from-literal=k=v --dry-run=client -o json > "$work/s.json"
  admitted "$1" "$2" "$work/s.json"
}
secret yes "the API may create its run Secret"    bob-run-check
secret no  "the API may not create another Secret" not-a-run
if $K --as="$API" -n "$NS" delete secret issassist-ai-bob-key --dry-run=server >/dev/null 2>&1; then
  echo "FAIL the API could delete Helm's key"; fail=1
else echo "ok   the API cannot delete Helm's key"; fi
for f in "$@"; do admitted yes "the API's own pod $(basename "$f") is admitted" "$f"; done
exit $fail
