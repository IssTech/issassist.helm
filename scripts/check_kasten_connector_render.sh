#!/usr/bin/env bash
# Render checks for the Kasten connector's ClusterRole (IA-0031 inventory). Run from the
# chart root:   bash scripts/check_kasten_connector_render.sh
set -u
fail=0
render() { helm template t . -s templates/kasten/connector.yaml --set kastenConnector.enabled=true "$@" 2>&1; }
expect() { local what=$1 pattern=$2; shift 3
  if render "$@" | grep -qE -- "$pattern"; then echo "ok   $what"; else echo "FAIL $what"; fail=1; fi; }
expect_not() { local what=$1 pattern=$2; shift 3
  if render "$@" | grep -qE -- "$pattern"; then echo "FAIL $what"; fail=1; else echo "ok   $what"; fi; }
inv=(--set kastenConnector.inventory=true)
expect_not "no inventory rules by default"            'resources: \["pods"\]' --
expect_not "inventory yes is not true"                'resources: \["pods"\]' -- --set kastenConnector.inventory=yes
expect_not "inventory removed (older release) is off" 'resources: \["pods"\]' -- --set kastenConnector.inventory=null
expect "inventory true grants pods"                   'resources: \["pods"\]' -- "${inv[@]}"
expect "and workloads"                                'resources: \["deployments", "statefulsets", "daemonsets"\]' -- "${inv[@]}"
expect "and Kanister blueprints"                      'resources: \["blueprints"\]' -- "${inv[@]}"
expect "and blueprint bindings"                       'resources: \["blueprintbindings"\]' -- "${inv[@]}"
expect "CRDs are list only"                           'resources: \["customresourcedefinitions"\]' -- "${inv[@]}"
expect_not "never secrets"                            'secrets' -- "${inv[@]}"
expect_not "never configmaps"                         'configmaps' -- "${inv[@]}"
expect_not "never a write verb"                       '"(create|update|patch|delete|deletecollection|escalate|bind|impersonate)"' -- "${inv[@]}"
expect_not "never exec into pods"                     'pods/exec|pods/log|pods/attach' -- "${inv[@]}"
exit $fail
