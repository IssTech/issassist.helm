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
# The provider isstech was removed (2026/11/03). A release upgraded with --reuse-values
# still carries its block: it must render, and nothing of it may reach the API.
leftover=(--set aiAnalysis.providers.isstech.allowed=true --set "aiAnalysis.providers.isstech.apiKey=${keymark}" --set aiAnalysis.providers.isstech.existingSecret=x)
expect "a leftover isstech block still renders"        'name: issassist-ai-analysis' -- "${leftover[@]}"
expect_not "a leftover isstech block reaches nothing"  'ISSTECH|issassist-ai-isstech-key' -- "${leftover[@]}"
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
# Mockup §8: a daily cap per provider, in its own unit.
expect "Claude's cap defaults to 5 EUR"               'IA_AI_CLAUDE_DAILY_CAP: "5"' --
expect "Claude's maximum defaults to 20 EUR"          'IA_AI_CLAUDE_DAILY_CAP_MAX: "20"' --
expect "Gemini's cap defaults to 5 EUR"               'IA_AI_GEMINI_DAILY_CAP: "5"' --
expect "Bob's cap defaults to 20 bobcoins"            'IA_AI_BOB_DAILY_CAP: "20"' --
expect "Bob's maximum defaults to 50 bobcoins"        'IA_AI_BOB_DAILY_CAP_MAX: "50"' --
expect "the local LLM has no cap"                     'IA_AI_LOCAL_DAILY_CAP_MAX: "0"' --
expect "a cap of 0 renders 0, not the fallback"       'IA_AI_CLAUDE_DAILY_CAP: "0"' -- --set aiAnalysis.providers.claude.dailyCap=0
expect "a maximum renders what was set"               'IA_AI_BOB_DAILY_CAP_MAX: "80"' -- --set aiAnalysis.providers.bob.dailyCapMax=80
expect "Claude gone (older release) falls back to 5"  'IA_AI_CLAUDE_DAILY_CAP: "5"' -- --set aiAnalysis.providers.claude=null
expect "Bob gone (older release) falls back to 50"    'IA_AI_BOB_DAILY_CAP_MAX: "50"' -- --set aiAnalysis.providers.bob=null
expect_not "the old Bob-only cap is gone"             'DAILY_CAP_BOBCOINS' --
expect "a per-run limit of 0 renders 0, not 5"        'IA_AI_BOB_MAX_COST_PER_RUN_BOBCOINS: "0"' -- --set aiAnalysis.providers.bob.maxCostPerRunBobcoins=0
expect "Bob gone (older release) renders its defaults" 'IA_AI_BOB_NAMESPACE: "ai-bob-runs"' -- --set aiAnalysis.providers.bob=null
expect "the Bob image reaches the API"                 'IA_AI_BOB_IMAGE: "ghcr.io/isstech/issassist-bob-runner:1"' -- --set aiAnalysis.providers.bob.image=ghcr.io/isstech/issassist-bob-runner:1
# Security review of slice 4 (2026/11/03): the admission policy, the quota, the ranges.
digest="sha256:$(printf '%064d' 7)"
pinned=(--set aiAnalysis.providers.bob.allowed=true --set "aiAnalysis.providers.bob.image=ghcr.io/isstech/issassist-bob-runner@${digest}")
expect "an image by tag only fails"                     'pinned by digest' -- "${bob[@]}" --set aiAnalysis.providers.bob.image=ghcr.io/isstech/issassist-bob-runner:1.5.0-3
expect "the pod policy admits only the pinned image"    "variables.c.image == \"ghcr.io/isstech/issassist-bob-runner@${digest}\"" -- "${pinned[@]}"
expect_section "the pod policy refuses a command"       ValidatingAdmissionPolicy issassist-bob-run-pods-ai-bob-runs '!has\(variables.c.command\)' -- "${pinned[@]}"
expect_section "bob reads nothing from a Secret"       ValidatingAdmissionPolicy issassist-bob-run-pods-ai-bob-runs "variables.c.env.all\\(e, !has\\(e.valueFrom\\)" -- "${pinned[@]}"
expect_section "the pod policy knows Helm's key name"   ValidatingAdmissionPolicy issassist-bob-run-pods-ai-bob-runs '== "issassist-ai-bob"\)' -- "${pinned[@]}" --set aiAnalysis.providers.bob.existingSecret=issassist-ai-bob
expect_section "the pod deadline follows timeoutSeconds" ValidatingAdmissionPolicy issassist-bob-run-pods-ai-bob-runs 'activeDeadlineSeconds <= 240' -- "${pinned[@]}" --set aiAnalysis.providers.bob.timeoutSeconds=240
expect_section "the pod policy denies, not warns"       ValidatingAdmissionPolicyBinding issassist-bob-run-pods-ai-bob-runs 'validationActions: \["Deny"\]' -- "${pinned[@]}"
expect_section "the Secret policy is for the API only"  ValidatingAdmissionPolicy issassist-bob-run-secrets-ai-bob-runs 'request.userInfo.username == "system:serviceaccount:issassist-x:api"' -- "${pinned[@]}" --namespace issassist-x
expect_section "the Secret policy covers delete"        ValidatingAdmissionPolicy issassist-bob-run-secrets-ai-bob-runs 'operations: \["CREATE", "UPDATE", "DELETE"\]' -- "${pinned[@]}"
expect_section "the API may touch only bob-run-* Secrets" ValidatingAdmissionPolicy issassist-bob-run-secrets-ai-bob-runs "startsWith\('bob-run-'\)" -- "${pinned[@]}"
expect "a timeout over 900 s fails"                     'timeoutSeconds must be from 30 to 900' -- "${bob[@]}" --set aiAnalysis.providers.bob.timeoutSeconds=901
expect_section "run pods are capped at maxConcurrent + 1" ResourceQuota bob-runs 'pods: "4"' -- "${bob[@]}" --set aiAnalysis.maxConcurrent=3
expect_section "and so is their memory"                 ResourceQuota bob-runs 'limits.memory: "2560Mi"' -- "${bob[@]}" --set aiAnalysis.maxConcurrent=3
for range in '0\.0\.0\.0/8' '192\.0\.0\.0/24' '198\.18\.0\.0/15'; do
  expect_section "run pods cannot reach ${range//\\/}"     NetworkPolicy bob-runs "- ${range}" -- "${bob[@]}"
done
# Mockup §9: the key sidecar.
proxied=("${pinned[@]}" --set "aiAnalysis.providers.bob.keyproxyImage=ghcr.io/isstech/issassist-bob-keyproxy@${digest}")
expect "the sidecar image by tag only fails"          'keyproxyImage must be pinned by digest' -- "${pinned[@]}" --set aiAnalysis.providers.bob.keyproxyImage=ghcr.io/isstech/issassist-bob-keyproxy:1
expect "the pod policy admits only the pinned sidecar" "variables.p.image == \"ghcr.io/isstech/issassist-bob-keyproxy@${digest}\"" -- "${proxied[@]}"
# Regions chosen in the web GUI (decided 2026/11/04).
expect "the default region is eu-de"                  'IA_AI_BOB_REGION: "eu-de"' --
expect "the web GUI is offered IBM's three regions"   'IA_AI_BOB_REGIONS: .*eu-de.*https://api.eu-de.bob.ibm.com.*jp-tok.*us-east' --
expect "no fixed gateway by default"                  'IA_AI_BOB_GATEWAY_URL: ""' --
expect "the sidecar forwards to a listed region only" "e.name == 'KEYPROXY_UPSTREAM' && e.value in \[\"https://api.eu-de.bob.ibm.com\",\"https://api.jp-tok.bob.ibm.com\",\"https://api.us-east.bob.ibm.com\"\]" -- "${proxied[@]}"
expect "a customer's own Bob is the only address"     "e.name == 'KEYPROXY_UPSTREAM' && e.value in \[\"https://bob.customer.example\"\]" -- "${proxied[@]}" --set aiAnalysis.providers.bob.gatewayUrl=https://bob.customer.example
expect "and then nothing can be chosen"               'IA_AI_BOB_REGIONS: "[{][}]"' -- --set aiAnalysis.providers.bob.gatewayUrl=https://bob.customer.example
expect "the old us-east default is a region again"    'IA_AI_BOB_REGION: "us-east"' -- --set aiAnalysis.providers.bob.gatewayUrl=https://api.us-east.bob.ibm.com
expect "an old release without regions gets IBM's"    'IA_AI_BOB_REGIONS: .*us-east' -- --set aiAnalysis.providers.bob.regions=null
expect "an unlisted region fails where Bob is on"     'region must be one of' -- "${bob[@]}" --set aiAnalysis.providers.bob.region=frankfurt
expect "but never stops an upgrade where Bob is off"  'IA_AI_BOB_REGION: ""' -- --set aiAnalysis.providers.bob.region=frankfurt
expect "an http region fails"                         'every address must be a plain https' -- --set aiAnalysis.providers.bob.regions.eu-de=http://x.example
expect "a region address with credentials fails"      'every address must be a plain https' -- --set "aiAnalysis.providers.bob.regions.eu-de=https://u""@x.example"
expect "a region address with a fragment fails"       'every address must be a plain https' -- --set "aiAnalysis.providers.bob.regions.eu-de=https://x.example#y"
expect "a region address without a host fails"        'every address must be a plain https' -- --set "aiAnalysis.providers.bob.regions.eu-de=https://"
expect "a gatewayUrl with a space fails"              'gatewayUrl must be a plain https' -- --set "aiAnalysis.providers.bob.gatewayUrl=https://x.example/a b"
expect "a gatewayUrl with a port and path is fine"    'IA_AI_BOB_GATEWAY_URL: "https://bob.customer.example:8443/v1"' -- --set "aiAnalysis.providers.bob.gatewayUrl=https://bob.customer.example:8443/v1"
expect "a region name with capitals fails"            'region name is lowercase' -- --set aiAnalysis.providers.bob.regions.EU=https://x.example
# Bob's own switch for its cluster-scoped resources (decided 2026/11/04).
expect "clusterResources true renders Bob without clusterScoped" 'name: ai-bob-runs' -- "${bob[@]}" --set clusterScoped.create=false --set aiAnalysis.providers.bob.clusterResources=true
expect_not "and not the restore tests' ClusterRole"  'name: sp-restore-tester' -- "${bob[@]}" --set clusterScoped.create=false --set aiAnalysis.providers.bob.clusterResources=true
expect_not "clusterResources false keeps Bob out"     'name: ai-bob-runs' -- "${bob[@]}" --set aiAnalysis.providers.bob.clusterResources=false
expect "a clusterResources of yes fails"              'clusterResources must be true, false or empty' -- "${bob[@]}" --set aiAnalysis.providers.bob.clusterResources=yes
expect "an http gateway fails"                        'gatewayUrl must be a plain https' -- "${bob[@]}" --set aiAnalysis.providers.bob.gatewayUrl=http://x.example
expect "a gateway with credentials fails"             'gatewayUrl must be a plain https' -- "${bob[@]}" --set "aiAnalysis.providers.bob.gatewayUrl=https://u""@x.example"
expect_section "no shared process namespace"          ValidatingAdmissionPolicy issassist-bob-run-pods-ai-bob-runs 'shareProcessNamespace == false' -- "${proxied[@]}"
expect "the sidecar image reaches the API"            "IA_AI_BOB_KEYPROXY_IMAGE: \"ghcr.io/isstech/issassist-bob-keyproxy@${digest}\"" -- "${proxied[@]}"
# The second review: CPU in the quota, and the mounts pinned in the policy.
expect_section "the quota caps CPU limits"            ResourceQuota bob-runs 'limits.cpu: "4800m"' -- "${bob[@]}" --set aiAnalysis.maxConcurrent=3
expect_section "the quota caps CPU requests"          ResourceQuota bob-runs 'requests.cpu: "480m"' -- "${bob[@]}" --set aiAnalysis.maxConcurrent=3
expect_section "bob's mounts are pinned by path"      ValidatingAdmissionPolicy issassist-bob-run-pods-ai-bob-runs "m.name == 'work' && m.mountPath == '/work'" -- "${proxied[@]}"
expect_section "keyproxy's mount is pinned by path"   ValidatingAdmissionPolicy issassist-bob-run-pods-ai-bob-runs "variables.p.volumeMounts\\[0\\].mountPath == '/run/keyproxy'" -- "${proxied[@]}"
expect_section "an item's path is its key"            ValidatingAdmissionPolicy issassist-bob-run-pods-ai-bob-runs 'i.path == i.key && !has.i.mode.' -- "${proxied[@]}"
expect_section "a run pod is named bob-run-*"         ValidatingAdmissionPolicy issassist-bob-run-pods-ai-bob-runs "startsWith\\('bob-run-'\\)" -- "${proxied[@]}"
exit $fail
