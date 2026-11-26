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
exit $fail
