#!/usr/bin/env bash
# Render checks for tsmAgent.tasks.heartbeatTimeout (#344). Run from the chart root:
#   bash scripts/check_tsm_agent_tasks_render.sh
# The key reaches the agent's config.toml in the tsm-agent-config ConfigMap. The
# agent closes a dead worker's process row after 2 x this value.
set -u
fail=0
render() { helm template t . "$@" 2>&1; }
line() { render "$@" | grep -E '^    heartbeat_timeout = ' ; }
check() {  # check <description> <expected line> -- helm args
  local what=$1 want=$2; shift 3
  got=$(line "$@")
  if [ "$got" = "    heartbeat_timeout = $want" ]; then echo "ok   $what"
  else echo "FAIL $what (got: ${got:-nothing})"; fail=1; fi
}
check "default is 300 s"                         "300.0" --
check "a chosen value reaches the ConfigMap"     "450.0" -- --set tsmAgent.tasks.heartbeatTimeout=450
check "a fractional value is kept"               "90.5"  -- --set tsmAgent.tasks.heartbeatTimeout=90.5
check "old values without tasks still render"    "300.0" -- --set tsmAgent.tasks=null
if [ "$(render | grep -cE '^    heartbeat_timeout = ')" = "1" ]; then
  echo "ok   exactly one heartbeat_timeout line"; else echo "FAIL exactly one heartbeat_timeout line"; fail=1; fi
for bad in 0 -5; do
  if render --set tsmAgent.tasks.heartbeatTimeout=$bad | grep -q 'must be a number of seconds above 0'; then
    echo "ok   $bad is refused"; else echo "FAIL $bad is refused"; fail=1; fi
done
exit $fail
