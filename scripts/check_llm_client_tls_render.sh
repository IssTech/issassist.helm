#!/usr/bin/env bash
# Render checks for aiAnalysis.providers.local.clientTls (mutual TLS to the local AI
# provider, 2026/11/26) and the local provider's site price. Run from the chart root:
#   bash scripts/check_llm_client_tls_render.sh
# A first test for the 2026/12/04 demo, to be revisited before release.
set -u
fail=0
render() { helm template t . "$@" 2>&1; }
expect() {  # expect <description> <grep pattern> -- helm args...
  local what=$1 pattern=$2; shift 3
  if render "$@" | grep -qE -- "$pattern"; then echo "ok   $what"; else echo "FAIL $what"; fail=1; fi
}
expect_not() {
  local what=$1 pattern=$2; shift 3
  if render "$@" | grep -qE -- "$pattern"; then echo "FAIL $what"; fail=1; else echo "ok   $what"; fi
}
# A name nothing else in the chart uses, so every object that mentions it is found.
secret="llm-client-check-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
tls=(--set "aiAnalysis.providers.local.clientTls.secretName=${secret}"
     --set aiAnalysis.providers.local.clientTls.caConfigMap=isstech-ca-bundle
     --set aiAnalysis.providers.local.clientTls.caKey=isstech-gpu-ca.crt)

expect_not "off by default: no mount"                 'llm-client-tls' --
expect_not "off by default: no client TLS env"        'IA_AI_LOCAL_(CA|CERT|KEY)\b' --
expect "on: the CA path"      'value: "/etc/issassist-llm-client/ca.crt"'  -- "${tls[@]}"
expect "on: the cert path"    'value: "/etc/issassist-llm-client/tls.crt"' -- "${tls[@]}"
expect "on: the key path"     'value: "/etc/issassist-llm-client/tls.key"' -- "${tls[@]}"
expect "on: mounted at /etc/issassist-llm-client" 'mountPath: "/etc/issassist-llm-client"' -- "${tls[@]}"
if render "${tls[@]}" | grep -A2 'mountPath: "/etc/issassist-llm-client"' | grep -q 'readOnly: true'
then echo "ok   on: the mount is read-only"; else echo "FAIL on: the mount is read-only"; fail=1; fi
expect "on: only the CA key is taken from the ConfigMap" 'key: "isstech-gpu-ca.crt"' -- "${tls[@]}"
expect_not "blank values are off"  'llm-client-tls' -- --set "aiAnalysis.providers.local.clientTls.secretName= " \
  --set "aiAnalysis.providers.local.clientTls.caConfigMap= " --set "aiAnalysis.providers.local.clientTls.caKey= "
expect "clientTls gone (older release) renders" '^kind: Deployment' -- --set aiAnalysis.providers.local.clientTls=null

half='set secretName, caConfigMap and caKey together, or none of them'
expect "secretName alone fails"             "$half" -- --set "aiAnalysis.providers.local.clientTls.secretName=${secret}"
expect "secretName without caKey fails"     "$half" -- --set "aiAnalysis.providers.local.clientTls.secretName=${secret}" \
  --set aiAnalysis.providers.local.clientTls.caConfigMap=isstech-ca-bundle
expect "secretName without caConfigMap fails" "$half" -- --set "aiAnalysis.providers.local.clientTls.secretName=${secret}" \
  --set aiAnalysis.providers.local.clientTls.caKey=isstech-gpu-ca.crt
expect "the CA without secretName fails"    "$half" -- --set aiAnalysis.providers.local.clientTls.caConfigMap=isstech-ca-bundle \
  --set aiAnalysis.providers.local.clientTls.caKey=isstech-gpu-ca.crt
expect "caKey alone fails"                  "$half" -- --set aiAnalysis.providers.local.clientTls.caKey=isstech-gpu-ca.crt

# The key's mode (2026/11/27): 0440 under the pod's fsGroup, never 0444 (every uid).
fsg='aiAnalysis.providers.local.clientTls.fsGroup: a whole number from 1 to 999999999'
expect "on: the files are mounted 0440"       'defaultMode: 0440' -- "${tls[@]}"
expect_not "on: never 0444 (readable by every uid)" 'defaultMode: 0444' -- "${tls[@]}"
expect "on: the pod's fsGroup is the image's group" '^        fsGroup: 1000$' -- "${tls[@]}"
expect "on: another fsGroup renders"          '^        fsGroup: 2000$' -- "${tls[@]}" \
  --set aiAnalysis.providers.local.clientTls.fsGroup=2000
expect "on: fsGroup gone (older release) is 1000" '^        fsGroup: 1000$' -- "${tls[@]}" \
  --set aiAnalysis.providers.local.clientTls.fsGroup=null
expect "on: fsGroup 0 (root's group) fails"   "$fsg" -- "${tls[@]}" --set aiAnalysis.providers.local.clientTls.fsGroup=0
expect "on: fsGroup not a number fails"       "$fsg" -- "${tls[@]}" --set aiAnalysis.providers.local.clientTls.fsGroup=abc
expect "on: fsGroup negative fails"           "$fsg" -- "${tls[@]}" --set aiAnalysis.providers.local.clientTls.fsGroup=-5
expect_not "off by default: no fsGroup"       'fsGroup:' --
expect_not "off: fsGroup alone is not client TLS" 'fsGroup:|llm-client-tls' -- --set aiAnalysis.providers.local.clientTls.fsGroup=2000

# Only the API workload mounts the Secret: every object that names it, with every
# optional component switched on, must be the API Deployment. `kind name` per object.
owners=$(render -f ci/all-optional-values.yaml "${tls[@]}" | awk -v s="$secret" '
  function flush() { if (hit) print kind, name; kind=""; name=""; hit=0; meta=0 }
  /^---/ { flush(); next }
  /^kind: / { kind=$2 }
  /^metadata:/ { meta=1; next }
  meta && /^  name: / { name=$2; meta=0 }
  index($0, s) { hit=1 }
  END { flush() }' | sort -u)
if [ "$owners" = "Deployment api" ]; then echo "ok   only the API Deployment mounts the client Secret"
else echo "FAIL only the API Deployment mounts the client Secret (found: ${owners:-nothing})"; fail=1; fi

# The site price for an endpoint outside this cluster.
expect "no price by default"                'IA_AI_LOCAL_PRICE_IN: ""' --
expect "a price renders"                    'IA_AI_LOCAL_PRICE_IN: "0.10"' -- --set-string aiAnalysis.providers.local.priceInEurPerMtok=0.10
expect "the out price renders"              'IA_AI_LOCAL_PRICE_OUT: "0.2"' -- --set aiAnalysis.providers.local.priceOutEurPerMtok=0.2
# Own infrastructure (2026/11/27): off by default, needs clientTls, only `true` is on.
own=(--set aiAnalysis.providers.local.ownInfrastructure=true)
expect "own infrastructure is off by default"      'IA_AI_LOCAL_OWN_INFRASTRUCTURE: "false"' --
expect "own infrastructure without clientTls fails" 'ownInfrastructure needs aiAnalysis.providers.local.clientTls' -- "${own[@]}"
expect "own infrastructure with clientTls is on"   'IA_AI_LOCAL_OWN_INFRASTRUCTURE: "true"' -- "${own[@]}" "${tls[@]}"
expect "ownInfrastructure yes is not on"           'IA_AI_LOCAL_OWN_INFRASTRUCTURE: "false"' -- --set aiAnalysis.providers.local.ownInfrastructure=yes "${tls[@]}"
expect "ownInfrastructure gone (older release) is off" 'IA_AI_LOCAL_OWN_INFRASTRUCTURE: "false"' -- --set aiAnalysis.providers.local.ownInfrastructure=null
# The context window (2026/11/27): what the API budgets a prompt against.
ctxe='aiAnalysis.providers.local.contextTokens: a whole number of tokens'
expect "context window 4096 by default"        'IA_AI_LOCAL_CONTEXT_TOKENS: "4096"' --
expect "context window 8192 renders"           'IA_AI_LOCAL_CONTEXT_TOKENS: "8192"' -- --set aiAnalysis.providers.local.contextTokens=8192
expect "context window gone (older release) is 4096" 'IA_AI_LOCAL_CONTEXT_TOKENS: "4096"' -- --set aiAnalysis.providers.local.contextTokens=null
expect "context window 0 fails"                "$ctxe" -- --set aiAnalysis.providers.local.contextTokens=0
expect "context window not a number fails"     "$ctxe" -- --set aiAnalysis.providers.local.contextTokens=lots
exit $fail
