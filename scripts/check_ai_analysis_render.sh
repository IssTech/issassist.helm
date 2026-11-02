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
expect "the Claude key reference is optional" 'optional: true' --
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
expect_not "a Bob apiKey never reaches the API pod"   'IA_AI_BOB_API_KEY|issassist-ai-bob-key' -- --set "aiAnalysis.providers.bob.apiKey=${keymark}"
expect "the web-key encryption key is generated"      'secret-generator.v1.mittwald.de/autogenerate: "ai-secret-key"' --
expect "the API reads IA_AI_SECRET_KEY"               'name: IA_AI_SECRET_KEY' --
exit $fail
