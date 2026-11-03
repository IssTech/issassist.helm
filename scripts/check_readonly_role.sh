#!/usr/bin/env bash
# Checks for api.postgres.readonlyRole and api.avepointRunCheck. Run from the chart root:
#   bash scripts/check_readonly_role.sh            # render checks only
#   bash scripts/check_readonly_role.sh --live     # also runs the rendered scripts against postgres:17
# The live part needs docker. It starts a TLS Postgres named api-postgres, runs the
# role Job's own scripts against it, and then the check's script as the new role.
# Exits non-zero if any case does the wrong thing.
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
ON=(--set api.postgres.readonlyRole.enabled=true)
expect_not "the role Job is off by default"            'name: api-postgres-readonly-role' --
expect_not "the check is off by default"               'name: avepoint-run-check' --
expect_not "readonlyRole yes is not on"                'name: api-postgres-readonly-role' -- --set api.postgres.readonlyRole.enabled=yes
expect_not "readonlyRole gone (older release) is off"  'name: api-postgres-readonly-role' -- --set api.postgres.readonlyRole=null
expect "readonlyRole true renders the Job"             'kind: Job' -- "${ON[@]}"
expect "the Job runs after install and upgrade"        'helm.sh/hook": post-install,post-upgrade' -- "${ON[@]}"
expect "the Job verifies the server certificate"       'value: "verify-full"' -- "${ON[@]}"
expect "the read-only password comes from its Secret"  'name: api-postgres-readonly-auth' -- "${ON[@]}"
expect_not "no password is passed to psql with -v"     'psql[^|]* -v ' -- "${ON[@]}"
expect_not "the role is not granted the public schema" 'ON SCHEMA public' -- "${ON[@]}"
expect "the check without the role fails, and says so" 'needs api.postgres.readonlyRole.enabled' -- --set api.avepointRunCheck.enabled=true
expect "the check with the role renders the CronJob"   'kind: CronJob' -- "${ON[@]}" --set api.avepointRunCheck.enabled=true
expect "the check verifies the server certificate"     'name: PGSSLMODE' -- "${ON[@]}" --set api.avepointRunCheck.enabled=true
expect "the check's schedule comes from values"        'schedule: "30 7 \* \* \*"' -- "${ON[@]}" --set api.avepointRunCheck.enabled=true --set 'api.avepointRunCheck.schedule=30 7 * * *'
expect "the role Job mounts no ServiceAccount token" 'automountServiceAccountToken: false' -- "${ON[@]}"
expect "the check mounts no ServiceAccount token"  'automountServiceAccountToken: false' -- "${ON[@]}" --set api.avepointRunCheck.enabled=true --show-only templates/issassist/api/avepoint-run-check.yaml
expect_not "the role gets no default privileges"   'DEFAULT PRIVILEGES' -- "${ON[@]}"
expect_not "the check is not pinned to staging"        'namespace: issassist-staging' -- "${ON[@]}" --set api.avepointRunCheck.enabled=true

if [ "${1:-}" != "--live" ]; then exit $fail; fi

# ── Live: the rendered scripts against a real postgres:17 over TLS ─────────────
img=postgres:17
run_id="ro$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
work=$(mktemp -d)
net="$run_id-net"
# Built at runtime: a password literal in the repo is what secret scanners flag.
api_pw="t$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
ro_pw="t$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
cleanup() { docker rm -f "$run_id-db" >/dev/null 2>&1; docker network rm "$net" >/dev/null 2>&1; rm -rf "$work"; }
trap cleanup EXIT

render "${ON[@]}" --set api.avepointRunCheck.enabled=true --show-only templates/issassist/api/postgres-readonly-role.yaml >"$work/role.yaml"
render "${ON[@]}" --set api.avepointRunCheck.enabled=true --show-only templates/issassist/api/avepoint-run-check.yaml >"$work/check.yaml"
python3 - "$work" <<'EOF'
import os, sys, yaml
work = sys.argv[1]
for name in ("role", "check"):
    for doc in yaml.safe_load_all(open(f"{work}/{name}.yaml")):
        if doc and doc["kind"] == "ConfigMap":
            os.makedirs(f"{work}/{name}", exist_ok=True)
            for key, text in doc["data"].items():
                open(f"{work}/{name}/{key}", "w").write(text)
EOF
chmod -R a+rX "$work"

# A CA and a server certificate for the name the Job connects to.
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=test-ca" \
  -keyout "$work/ca.key" -out "$work/ca.crt" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -subj "/CN=api-postgres" \
  -keyout "$work/server.key" -out "$work/server.csr" 2>/dev/null
printf 'subjectAltName=DNS:api-postgres\n' >"$work/san.ext"
openssl x509 -req -in "$work/server.csr" -CA "$work/ca.crt" -CAkey "$work/ca.key" \
  -CAcreateserial -days 1 -extfile "$work/san.ext" -out "$work/server.crt" 2>/dev/null
# A second CA, which did not sign the server, for the refusal case.
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=other-ca" \
  -keyout "$work/other-ca.key" -out "$work/other-ca.crt" 2>/dev/null
chmod a+r "$work"/*.crt "$work"/server.key

docker network create "$net" >/dev/null
docker run -d --name "$run_id-db" --network "$net" --network-alias api-postgres \
  -e POSTGRES_USER=api -e POSTGRES_DB=api -e POSTGRES_PASSWORD="$api_pw" \
  -v "$work:/certs:ro" --entrypoint sh "$img" -c '
    cp /certs/server.crt /certs/server.key /tmp/ && chown postgres /tmp/server.key && chmod 600 /tmp/server.key
    exec docker-entrypoint.sh postgres -c log_statement=ddl -c ssl=on -c ssl_cert_file=/tmp/server.crt -c ssl_key_file=/tmp/server.key' >/dev/null
db() { docker exec -e PGPASSWORD="$api_pw" "$run_id-db" psql -X -q -t -A -h localhost -U api -d api -c "$1" 2>&1; }
for _ in $(seq 60); do db "SELECT 1" | grep -qx 1 && break; sleep 1; done

# The pod the chart renders, as near as docker gets: uid 999, read-only root, its env.
job() {  # job <dir> <script> [extra docker args]
  local dir=$1 script=$2; shift 2
  docker run --rm --network "$net" --user 999 --read-only --tmpfs /tmp \
    -v "$work/$dir:/scripts:ro" -v "$work/ca.crt:/etc/issassist/ca.crt:ro" \
    -e PGHOST=api-postgres -e PGDATABASE=api -e PGSSLMODE=verify-full \
    -e PGSSLROOTCERT=/etc/issassist/ca.crt -e PGCONNECT_TIMEOUT=10 -e HOME=/tmp \
    "$@" "$img" sh "/scripts/$script" 2>&1
}
role_job() { job role run.sh -e PGUSER=api -e PGPASSWORD="$api_pw" -e RO_USER=api-readonly -e RO_PASSWORD="$ro_pw" "$@"; }
as_ro() { docker run --rm --network "$net" -e PGPASSWORD="$ro_pw" -e PGSSLMODE=verify-full \
  -e PGSSLROOTCERT=/etc/issassist/ca.crt -v "$work/ca.crt:/etc/issassist/ca.crt:ro" \
  "$img" psql -X -q -t -A -h api-postgres -U api-readonly -d api -c "$1" 2>&1; }
live() {  # live <description> <grep pattern> <output>
  if printf '%s' "$3" | grep -qE -- "$2"; then echo "ok   $1"; else echo "FAIL $1"; printf '%s\n' "$3" | sed 's/^/       /' | head -5; fail=1; fi
}
live_not() {
  if printf '%s' "$3" | grep -qE -- "$2"; then echo "FAIL $1"; printf '%s\n' "$3" | sed 's/^/       /' | head -5; fail=1; else echo "ok   $1"; fi
}

out=$(role_job -e WAIT_SECONDS=10)
live "before the API migrates, the Job waits and says why" 'schema avepoint not there yet' "$out"
live "and ends with a warning, not a failure"   'still missing after' "$out"

db "CREATE TABLE users (id int, password_hash text); INSERT INTO users VALUES (1, 'x');
    CREATE SCHEMA avepoint;
    CREATE TABLE avepoint.snapshots (customer_id text, customer_name text, record_type text,
      service_name text, tenant_id text, collected_at timestamptz);
    CREATE TABLE avepoint.raw_responses (kind text, http_status int, attempt int, collected_at timestamptz,
      payload jsonb);
    CREATE TABLE avepoint.credentials (id int, client_id text, client_secret_encrypted text);
    INSERT INTO avepoint.snapshots VALUES ('c1','Kund','Service','Exchange','t1', now());
    INSERT INTO avepoint.raw_responses VALUES ('jobs', 200, 1, now(), '{}');
    INSERT INTO avepoint.credentials VALUES (1, 'partner', 'ciphertext');" >/dev/null

out=$(role_job)
live "the Job creates the role and reports the grant" 'api-readonly: role ready; reads 10 columns' "$out"
live "the role reads the schema avepoint"       '^1$' "$(as_ro 'SELECT count(*) FROM avepoint.snapshots')"
live "the role cannot read other tables"        'permission denied' "$(as_ro 'SELECT * FROM public.users')"
live "the role cannot read the AvePoint secret"  'permission denied' "$(as_ro 'SELECT client_id FROM avepoint.credentials')"
live "the role cannot read AvePoint's raw replies" 'permission denied' "$(as_ro 'SELECT payload FROM avepoint.raw_responses')"
live "the role cannot write"                    'permission denied' "$(as_ro "INSERT INTO avepoint.raw_responses VALUES ('x', 1, 1, now())")"
live "the role is not a superuser"              '^f$' "$(db "SELECT rolsuper FROM pg_roles WHERE rolname = 'api-readonly'")"

db "CREATE TABLE avepoint.later (id int); INSERT INTO avepoint.later VALUES (7);" >/dev/null
live "a table the API creates later is not readable" 'permission denied' "$(as_ro 'SELECT id FROM avepoint.later')"

out=$(role_job)
db "GRANT SELECT ON avepoint.credentials TO \"api-readonly\"" >/dev/null
out=$(role_job)
live "running it again succeeds"                 'role ready; reads 10 columns' "$out"
live "and takes back a grant made by hand"       'permission denied' "$(as_ro 'SELECT client_id FROM avepoint.credentials')"

db "CREATE ROLE handmade LOGIN CREATEDB; CREATE ROLE other; CREATE ROLE member_of LOGIN; GRANT other TO member_of;" >/dev/null
out=$(role_job -e RO_USER=handmade)
live "a role this chart did not create is refused" 'ERROR: could not set up the role' "$out"
live "and left as it was"                        '^t$' "$(db "SELECT rolcreatedb FROM pg_roles WHERE rolname = 'handmade'")"
db "COMMENT ON ROLE member_of IS 'managed by issassist.helm: api-postgres-readonly-role'" >/dev/null
out=$(role_job -e RO_USER=member_of)
live "a marked role that is a member of another is refused" 'ERROR: could not set up the role' "$out"

first_pw=$ro_pw
ro_pw="t$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
role_job >/dev/null
live "a new password in the Secret is applied"   '^1$' "$(as_ro 'SELECT 1')"

out=$(job check check.sh -e DB_USERNAME=api-readonly -e DB_PASSWORD="$ro_pw")
live "the check passes as the new role, over TLS" 'PASS — collection wrote 1 row' "$out"

out=$(docker run --rm --network "$net" -e PGPASSWORD="$api_pw" -e PGSSLMODE=verify-full \
  -e PGSSLROOTCERT=/etc/issassist/ca.crt -v "$work/other-ca.crt:/etc/issassist/ca.crt:ro" \
  "$img" psql -X -h api-postgres -U api -d api -c 'SELECT 1' 2>&1)
live "a server our CA did not sign is refused"  'certificate verify failed' "$out"

# The bootstrap superuser exists and carries no mark, so the Job must refuse it
# before its ALTER ROLE could run.
err_pw="t$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
out=$(job role run.sh -e PGUSER=api -e PGPASSWORD="$api_pw" -e RO_USER=api -e RO_PASSWORD="$err_pw"; echo "exit=$?")
live "the bootstrap superuser is refused"         'ERROR: could not set up the role' "$out"
live "and does not fail the release"             'exit=0' "$out"
live_not "nor echo the password in its output"   "$err_pw" "$out"

logs=$(docker logs "$run_id-db" 2>&1)
live "the server logs DDL, so the check below means something" 'LOG:  statement: (CREATE|GRANT)' "$logs"
live_not "the server log never holds the read-only password" "$ro_pw|$first_pw|$err_pw" "$logs"
exit $fail
