#!/usr/bin/env bash
# Render checks for api.* keys (IA-0036). Run from the chart root:
#   bash scripts/check_api_render.sh
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
fwd() { render "$@" | grep -A1 'name: IA_FORWARDED_ALLOW_IPS' | tail -1; }
expect_fwd() {  # expect_fwd <description> <exact value line> -- helm args...
  local what=$1 want=$2; shift 3
  if [ "$(fwd "$@" | sed 's/^ *//')" = "value: $want" ]; then echo "ok   $what"; else echo "FAIL $what"; fail=1; fi
}
# Security review H1: no proxy is trusted unless the operator lists it, and never "*".
expect_fwd "no proxy is trusted by default"            '""' --
expect_fwd "a key removed (older release) trusts none" '""' -- --set api.forwardedAllowIps=null
expect_fwd "a CIDR is passed through"                  '"10.42.0.0/16"' -- --set api.forwardedAllowIps=10.42.0.0/16
expect_fwd "a list loses its spaces"                   '"10.0.0.1,10.0.0.2"' -- --set "api.forwardedAllowIps=10.0.0.1\, 10.0.0.2"
expect "a star is refused"                             'never "\*"' -- --set "api.forwardedAllowIps=*"
expect "a star inside a list is refused"               'never "\*"' -- --set "api.forwardedAllowIps=10.0.0.1\,*"
expect "a host name is refused"                        'comma-separated list of IP' -- --set api.forwardedAllowIps=ingress.example
expect_not "the old hardcoded star is gone"            'value: "\*"' --
exit $fail
