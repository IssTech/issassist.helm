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
exit $fail
