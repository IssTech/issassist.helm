#!/usr/bin/env bash
# Render checks for the Postgres and Valkey Services (IA-0044, #526). Run from the chart root:
#   bash scripts/check_datastore_services_render.sh
# They are ClusterIP by default: a NodePort opens the database on every node address.
set -u
fail=0
SVCS="api-postgres api-valkey tsm-agent-postgres tsm-agent-valkey superset-postgres superset-valkey"
render() { helm template t . --set superset.enabled=true "$@" 2>&1; }
svc() {  # svc <name> -- helm args: the rendered Service only
  local name=$1; shift
  render "$@" | awk -v n="$name" '
    /^---/ { if (doc ~ /kind: Service\n/ && doc ~ ("\n  name: " n "\n")) print doc; doc=""; next }
    { doc = doc $0 "\n" }
    END { if (doc ~ /kind: Service\n/ && doc ~ ("\n  name: " n "\n")) print doc }'
}
check() {  # check <description> <service> <pattern> <want 0|1> -- helm args
  local what=$1 name=$2 pattern=$3 want=$4; shift 5
  if svc "$name" "$@" | grep -qE -- "$pattern"; then got=1; else got=0; fi
  if [ "$got" = "$want" ]; then echo "ok   $what"; else echo "FAIL $what"; fail=1; fi
}
for s in $SVCS; do
  check "$s exists"                        "$s" "name: $s"        1 --
  check "$s is ClusterIP by default"       "$s" 'type: ClusterIP' 1 --
  check "$s has no nodePort by default"    "$s" 'nodePort'        0 --
done
check "api-postgres opt-in to NodePort"          api-postgres       'type: NodePort'  1 -- --set api.postgres.service.type=NodePort
check "api-postgres keeps its old port 30101"    api-postgres       'nodePort: 30101' 1 -- --set api.postgres.service.type=NodePort
check "api-valkey keeps its old port 30102"      api-valkey         'nodePort: 30102' 1 -- --set api.valkey.service.type=NodePort
check "tsm-agent-postgres keeps 30103"           tsm-agent-postgres 'nodePort: 30103' 1 -- --set tsmAgent.postgres.service.type=NodePort
check "tsm-agent-valkey keeps 30104"             tsm-agent-valkey   'nodePort: 30104' 1 -- --set tsmAgent.valkey.service.type=NodePort
check "superset-postgres keeps 30105"            superset-postgres  'nodePort: 30105' 1 -- --set superset.postgres.service.type=NodePort
check "superset-valkey keeps 30106"              superset-valkey    'nodePort: 30106' 1 -- --set superset.valkey.service.type=NodePort
check "a chosen nodePort is used"                api-postgres       'nodePort: 31999' 1 -- --set api.postgres.service.type=NodePort --set api.postgres.service.nodePort=31999
check "one opt-in does not open the others"      api-valkey         'type: ClusterIP' 1 -- --set api.postgres.service.type=NodePort
check "a key removed (old values) is ClusterIP"  api-postgres       'type: ClusterIP' 1 -- --set api.postgres.service=null
if render --set api.postgres.service.type=LoadBalancer | grep -q 'must be ClusterIP or NodePort'; then
  echo "ok   LoadBalancer is refused"; else echo "FAIL LoadBalancer is refused"; fail=1; fi
exit $fail
