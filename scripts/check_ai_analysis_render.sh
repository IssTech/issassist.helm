#!/usr/bin/env bash
# Render checks for aiAnalysis.* and global.darkSite (#463). Run from the chart root:
#   bash scripts/check_ai_analysis_render.sh
# Exits non-zero on the first case that renders the wrong thing.
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
expect "default values are not dark"         'IA_DARK_SITE: "false"' --
expect "darkSite null (the key gone, as after --reuse-values from an older release) is dark"               'IA_DARK_SITE: "true"' -- --set global.darkSite=null
expect "darkSite flase is dark"              'IA_DARK_SITE: "true"' -- --set global.darkSite=flase
expect "allowed: yes is not allowed"         'IA_AI_CLAUDE_ALLOWED: "false"' -- --set aiAnalysis.providers.claude.allowed=yes
expect "allowed: true is allowed"            'IA_AI_CLAUDE_ALLOWED: "true"' -- --set aiAnalysis.providers.claude.allowed=true
expect "an http endpoint fails"              'must start with https://' -- --set aiAnalysis.providers.local.endpoint=http://x.svc/v1
# Built at runtime: a credential-shaped literal in the repo is what secret scanners flag.
marker="m$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
with_creds="https://u""se""r:${marker}""@x.svc/v1"
expect "credentials in the endpoint fail"    'must not carry credentials' -- --set "aiAnalysis.providers.local.endpoint=${with_creds}"
expect_not "a failing endpoint is not echoed" "${marker}" -- --set "aiAnalysis.providers.local.endpoint=${with_creds}"
expect_not "an @ in the path is not credentials" 'must not carry credentials' -- --set "aiAnalysis.providers.local.endpoint=https://x.svc/v1/@m"
expect_not "the API pod never holds the Bob key" 'IA_AI_BOB_API_KEY' -- --set aiAnalysis.providers.bob.existingSecret=issassist-ai-bob
expect "the Claude key reference is optional" 'optional: true' -- --set aiAnalysis.providers.claude.existingSecret=issassist-ai-anthropic
expect "a cap of 0 renders 0, not the default"        'IA_AI_MAX_DAILY_CAP_EUR: "0"' -- --set aiAnalysis.maxDailyCapEur=0
expect "maxConcurrent 0 renders 0, not the default"   'IA_AI_MAX_CONCURRENT: "0"' -- --set aiAnalysis.maxConcurrent=0
expect "a missing cap renders the default 20"         'IA_AI_MAX_DAILY_CAP_EUR: "20"' -- --set aiAnalysis.maxDailyCapEur=null
expect_not "BOB in capitals is still kept out of the API pod" 'IA_AI_BOB_API_KEY' -- --set aiAnalysis.providers.BOB.existingSecret=issassist-ai-bob
expect_not "an unknown provider id adds no key to the API pod" 'IA_AI_EVIL_API_KEY' -- --set aiAnalysis.providers.evil.existingSecret=x
expect "a query string in the endpoint fails"         'must not carry a query string' -- --set "aiAnalysis.providers.local.endpoint=https://x.svc/v1?k=v"
expect "the debug wizard is off by default"            'IA_AI_DEBUG_WIZARD: "false"' --
expect "debugWizard.enabled true turns it on"          'IA_AI_DEBUG_WIZARD: "true"' -- --set aiAnalysis.debugWizard.enabled=true
expect "debugWizard.enabled yes is not on"             'IA_AI_DEBUG_WIZARD: "false"' -- --set aiAnalysis.debugWizard.enabled=yes
expect "debugWizard gone (older release) is off"       'IA_AI_DEBUG_WIZARD: "false"' -- --set aiAnalysis.debugWizard=null
# Slice 1b: keys through Helm, and the key that encrypts keys entered in the web GUI.
keymark="k$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
expect "apiKey renders its own Secret"                'name: issassist-ai-claude-key' -- --set "aiAnalysis.providers.claude.apiKey=${keymark}"
expect "apiKey wins over existingSecret in the pod"   'name: "issassist-ai-claude-key"' -- --set "aiAnalysis.providers.claude.apiKey=${keymark}"
expect "the Secret name shown is the rendered one"    'IA_AI_CLAUDE_SECRET_NAME: "issassist-ai-claude-key"' -- --set "aiAnalysis.providers.claude.apiKey=${keymark}"
expect_not "no apiKey renders no key Secret"          'name: issassist-ai-claude-key' --
expect_not "a Bob apiKey never reaches the API pod"   'IA_AI_BOB_API_KEY' -- --set "aiAnalysis.providers.bob.apiKey=${keymark}"
expect "a Bob apiKey renders Bob's own Secret"        'name: issassist-ai-bob-key' -- --set "aiAnalysis.providers.bob.apiKey=${keymark}" --set aiAnalysis.providers.bob.allowed=true
expect "the API is told Bob's key is Helm's (name only)" 'IA_AI_BOB_SECRET_NAME: "issassist-ai-bob-key"' -- --set "aiAnalysis.providers.bob.apiKey=${keymark}"
expect_not "no Secret is named for Claude by default"  'IA_AI_CLAUDE_SECRET_NAME' --
expect "the web-key encryption key is generated"      'secret-generator.v1.mittwald.de/autogenerate: "ai-secret-key"' --
expect "the API reads IA_AI_SECRET_KEY"               'name: IA_AI_SECRET_KEY' --
expect_not "a blank existingSecret names no Secret"      'IA_AI_CLAUDE_SECRET_NAME' -- --set "aiAnalysis.providers.claude.existingSecret= "
expect "an existingSecret is trimmed"                  'IA_AI_CLAUDE_SECRET_NAME: "issassist-ai-anthropic"' -- --set "aiAnalysis.providers.claude.existingSecret= issassist-ai-anthropic "
# Slice 4: IBM Bob, one pod per run in its own namespace.
bob=(--set aiAnalysis.providers.bob.allowed=true)
section() {  # section <kind> <name> -- helm args...: that object's rendered YAML
  local kind=$1 name=$2; shift 3
  render "$@" | awk -v k="kind: $kind" -v n="  name: $name" '
    /^---/ { if (hit) exit; buf=""; seen_k=0; seen_n=0; next }
    { buf = buf $0 "\n"; if ($0 == k) seen_k=1; if ($0 == n) seen_n=1;
      if (seen_k && seen_n && !hit) { hit=1; printf "%s", buf; next } if (hit) print }'
}
expect_section() {  # expect_section <description> <kind> <name> <pattern> -- helm args...
  local what=$1 kind=$2 name=$3 pattern=$4; shift 5
  if section "$kind" "$name" -- "$@" | grep -qE -- "$pattern"; then echo "ok   $what"; else echo "FAIL $what"; fail=1; fi
}
expect_section_not() {
  local what=$1 kind=$2 name=$3 pattern=$4; shift 5
  if section "$kind" "$name" -- "$@" | grep -qE -- "$pattern"; then echo "FAIL $what"; fail=1; else echo "ok   $what"; fi
}
expect_not "Bob off renders no run namespace"           'name: ai-bob-runs' --
expect "Bob allowed renders its run namespace"         'name: ai-bob-runs' -- "${bob[@]}"
expect_not "bob.allowed yes is not on"                 'name: ai-bob-runs' -- --set aiAnalysis.providers.bob.allowed=yes
expect_not "without clusterScoped.create no namespace" 'name: ai-bob-runs' -- "${bob[@]}" --set clusterScoped.create=false
expect "the run namespace enforces restricted"         'pod-security.kubernetes.io/enforce: restricted' -- "${bob[@]}"
expect_section "no connection into a run pod"           NetworkPolicy bob-runs 'ingress: \[\]' -- "${bob[@]}"
expect_section "run pods cannot reach the pod network"  NetworkPolicy bob-runs '- 10\.0\.0\.0/8' -- "${bob[@]}"
expect_section "run pods cannot reach link-local (cloud metadata)" NetworkPolicy bob-runs '- 169\.254\.0\.0/16' -- "${bob[@]}"
expect_section "run pods reach the internet on 443 only" NetworkPolicy bob-runs 'port: 443' -- "${bob[@]}"
expect_section_not "run pods reach no other port"       NetworkPolicy bob-runs 'port: (80|8000|5432|6379)$' -- "${bob[@]}"
expect_section "the API may create and delete Secrets"  Role issassist-bob-runner 'verbs: \["create", "delete"\]' -- "${bob[@]}"
if section Role issassist-bob-runner -- "${bob[@]}" | grep -A1 'resources: \["secrets"\]' | grep -qE '"(get|list|watch|update|patch)"'; then
  echo "FAIL the Secret rule grants only create and delete"; fail=1
else echo "ok   the Secret rule grants only create and delete"; fi
expect_section_not "the API cannot exec into a run pod"  Role issassist-bob-runner 'pods/exec|"\*"' -- "${bob[@]}"
expect_section "the Role is bound to the API's own account" RoleBinding issassist-bob-runner 'name: api$' -- "${bob[@]}"
expect "the API runs as its own ServiceAccount"        'serviceAccountName: api' --
expect_section "a Bob apiKey lands in the run namespace" Secret issassist-ai-bob-key 'namespace: ai-bob-runs' -- "${bob[@]}" --set "aiAnalysis.providers.bob.apiKey=${keymark}"
expect "the run namespace cannot be the release's"     'must not be the release' -- "${bob[@]}" --set aiAnalysis.providers.bob.namespace=default
expect "kube-system cannot be the run namespace"      'namespace of its own' -- "${bob[@]}" --set aiAnalysis.providers.bob.namespace=kube-system
expect "default cannot be the run namespace"          'namespace of its own' -- "${bob[@]}" --set aiAnalysis.providers.bob.namespace=default --namespace other
expect "an unknown egress mode fails"                  'egress must be' -- "${bob[@]}" --set aiAnalysis.providers.bob.egress=open
expect "Bob's limit defaults to 0 (unpriced: off)"    'IA_AI_BOB_DAILY_CAP_BOBCOINS: "0"' --
expect "Bob's limit renders what was set"             'IA_AI_BOB_DAILY_CAP_BOBCOINS: "20"' -- --set aiAnalysis.providers.bob.dailyCapBobcoins=20
expect "a per-run limit of 0 renders 0, not 5"        'IA_AI_BOB_MAX_COST_PER_RUN_BOBCOINS: "0"' -- --set aiAnalysis.providers.bob.maxCostPerRunBobcoins=0
expect "Bob gone (older release) renders its defaults" 'IA_AI_BOB_NAMESPACE: "ai-bob-runs"' -- --set aiAnalysis.providers.bob=null
expect "the Bob image reaches the API"                 'IA_AI_BOB_IMAGE: "ghcr.io/isstech/issassist-bob-runner:1"' -- --set aiAnalysis.providers.bob.image=ghcr.io/isstech/issassist-bob-runner:1
exit $fail
