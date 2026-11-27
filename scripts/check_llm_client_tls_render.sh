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
owners=$(render -f ci/all-optional-values.yaml "${tls[@]}" \
  --set-string "aiAnalysis.providers.local.ownInfrastructureUntil=$(date -u -d '+30 days' +%Y/%m/%d)" | awk -v s="$secret" '
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
# Priced, capped (D5 = C) and with an end date (D2 = B), owner decisions 2026/11/27.
until_ok=$(date -u -d "+30 days" +%Y/%m/%d)
latest=$(date -u -d "+92 days" +%Y/%m/%d)
paid=(--set-string aiAnalysis.providers.local.priceInEurPerMtok=10
      --set-string aiAnalysis.providers.local.priceOutEurPerMtok=10
      --set aiAnalysis.providers.local.dailyCap=1.5 --set aiAnalysis.providers.local.dailyCapMax=5
      --set-string "aiAnalysis.providers.local.ownInfrastructureUntil=${until_ok}")
expect "own infrastructure with clientTls is on"   'IA_AI_LOCAL_OWN_INFRASTRUCTURE: "true"' -- "${own[@]}" "${tls[@]}" "${paid[@]}"
expect "the end date renders ISO" "IA_AI_LOCAL_OWN_INFRASTRUCTURE_UNTIL: \"${until_ok//\//-}\"" -- "${own[@]}" "${tls[@]}" "${paid[@]}"
expect "no end date when own infrastructure is off" 'IA_AI_LOCAL_OWN_INFRASTRUCTURE_UNTIL: ""' --
expect "the date 92 days ahead is the latest allowed" 'IA_AI_LOCAL_OWN_INFRASTRUCTURE: "true"' -- "${own[@]}" "${tls[@]}" "${paid[@]}" \
  --set-string "aiAnalysis.providers.local.ownInfrastructureUntil=${latest}"
expect "today is still allowed" 'IA_AI_LOCAL_OWN_INFRASTRUCTURE: "true"' -- "${own[@]}" "${tls[@]}" "${paid[@]}" \
  --set-string "aiAnalysis.providers.local.ownInfrastructureUntil=$(date -u +%Y/%m/%d)"
unpriced='ownInfrastructure is priced and capped like any endpoint outside this cluster: set priceInEurPerMtok'
uncapped='ownInfrastructure is priced and capped like any endpoint outside this cluster: set dailyCap'
expect "own infrastructure without a price fails"    "$unpriced" -- "${own[@]}" "${tls[@]}" "${paid[@]}" \
  --set-string aiAnalysis.providers.local.priceInEurPerMtok=
expect "own infrastructure at price 0 fails"         "$unpriced" -- "${own[@]}" "${tls[@]}" "${paid[@]}" \
  --set-string aiAnalysis.providers.local.priceOutEurPerMtok=0
expect "own infrastructure with a price of abc fails" "$unpriced" -- "${own[@]}" "${tls[@]}" "${paid[@]}" \
  --set-string aiAnalysis.providers.local.priceOutEurPerMtok=abc
expect "own infrastructure without a cap fails"      "$uncapped" -- "${own[@]}" "${tls[@]}" "${paid[@]}" \
  --set aiAnalysis.providers.local.dailyCap=0
expect "own infrastructure without a cap maximum fails" "$uncapped" -- "${own[@]}" "${tls[@]}" "${paid[@]}" \
  --set aiAnalysis.providers.local.dailyCapMax=0
expect "own infrastructure without an end date fails" \
  'ownInfrastructureUntil is required with ownInfrastructure: true' -- "${own[@]}" "${tls[@]}" "${paid[@]}" \
  --set-string aiAnalysis.providers.local.ownInfrastructureUntil=
past=$(date -u -d "-1 day" +%Y/%m/%d)
expect "an end date that has passed fails, as the mockup words it" \
  "ownInfrastructureUntil \\(${past}\\) has passed: own infrastructure was a staging test. Remove ownInfrastructure, or set a new date \\(at most ${latest}\\) after reviewing it." \
  -- "${own[@]}" "${tls[@]}" "${paid[@]}" --set-string "aiAnalysis.providers.local.ownInfrastructureUntil=${past}"
far=$(date -u -d "+93 days" +%Y/%m/%d)
expect "an end date more than 92 days ahead fails" "ownInfrastructureUntil \\(${far}\\) is more than 92 days ahead" \
  -- "${own[@]}" "${tls[@]}" "${paid[@]}" --set-string "aiAnalysis.providers.local.ownInfrastructureUntil=${far}"
for zone in Europe/Stockholm America/New_York Pacific/Kiritimati UTC; do
  if TZ=$zone helm template t . "${own[@]}" "${tls[@]}" "${paid[@]}" 2>&1 | grep -q 'IA_AI_LOCAL_OWN_INFRASTRUCTURE: "true"'
  then echo "ok   a valid end date renders with TZ=$zone"; else echo "FAIL a valid end date renders with TZ=$zone"; fail=1; fi
done
for bad in 2026/02/30 2027/13/01 2026-12-31 31/12/2026 2026/1/5 tomorrow; do
  expect "end date ${bad} is not a date (never rolled over)" "ownInfrastructureUntil \\(${bad}\\) is not a date" \
    -- "${own[@]}" "${tls[@]}" "${paid[@]}" --set-string "aiAnalysis.providers.local.ownInfrastructureUntil=${bad}"
done
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
