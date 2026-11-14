#!/usr/bin/env bash
# Render checks for api.selfCheck.caBundle (#372). Run from the chart root:
#   bash scripts/check_self_check_render.sh
# The public-URL self-check always verifies the certificate; these check that the API pod
# is given the CA that signs what the ingress presents, and never the ingress private key.
set -u
fail=0
render() { helm template t . "$@" 2>&1; }
api() { render "$@" | awk '/^# Source: .*templates\/issassist\/api\/deployment.yaml/{p=1;next} /^# Source:/{p=0} p'; }
expect() {  # expect <description> <grep pattern> -- helm args...
  local what=$1 pattern=$2; shift 3
  if api "$@" | grep -qE -- "$pattern"; then echo "ok   $what"; else echo "FAIL $what"; fail=1; fi
}
expect_not() {
  local what=$1 pattern=$2; shift 3
  if api "$@" | grep -qE -- "$pattern"; then echo "FAIL $what"; fail=1; else echo "ok   $what"; fi
}
expect_render_fails() {
  local what=$1 pattern=$2; shift 3
  if render "$@" | grep -qE -- "$pattern"; then echo "ok   $what"; else echo "FAIL $what"; fail=1; fi
}
# Default: issuerType "disabled", so the ingress presents the chart's self-signed certificate.
expect "default: the env var is set"                    'name: IA_SELF_CHECK_CA_BUNDLE' --
expect "default: trusts the self-signed ingress cert"   'secretName: "self-signed-ingress-cert"' --
expect "default: only ca.crt is projected"              'key: "ca.crt"' --
expect_not "the ingress private key is never projected" 'key: "?tls\.key' --
expect_not "no subPath for the CA (renewal must reach)" 'mountPath: "/mnt/self-check-ca".*subPath' --
# A public issuer: the public store is enough, nothing is mounted.
expect_not "public issuer: no env var"                  'IA_SELF_CHECK_CA_BUNDLE' -- --set global.ingress.tls.issuerType=cluster --set global.ingress.tls.issuer=le
expect_not "public issuer: no CA volume"                'name: self-check-ca' -- --set global.ingress.tls.issuerType=cluster --set global.ingress.tls.issuer=le
# The operator's own CA wins, Secret or ConfigMap.
expect "operator Secret is used"                        'secretName: "corp-ca"' -- --set api.selfCheck.caBundle.secret=corp-ca
expect "operator Secret with a public issuer too"       'secretName: "corp-ca"' -- --set api.selfCheck.caBundle.secret=corp-ca --set global.ingress.tls.issuerType=cluster
expect "operator ConfigMap is used"                     'name: "corp-ca-cm"' -- --set api.selfCheck.caBundle.configMap=corp-ca-cm
expect "operator key name is used"                      'key: "root.pem"' -- --set api.selfCheck.caBundle.configMap=corp-ca-cm --set api.selfCheck.caBundle.key=root.pem
expect_render_fails "both Secret and ConfigMap refused" 'not both' -- --set api.selfCheck.caBundle.secret=a --set api.selfCheck.caBundle.configMap=b
# Verification can never be switched off from the chart.
expect_not "no verify-off switch exists"                'VERIFY|INSECURE' --
exit $fail
