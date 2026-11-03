# The api-readonly login and the AvePoint run check in the chart

2026/11/03. Mockup: [docs/mockups/2026-11-03-api-readonly-role.html](../mockups/2026-11-03-api-readonly-role.html),
approved the same day. Where the build differs from it is listed under "Changed from the
mockup".

## Why

`avepoint-run-check` had failed every morning since at least 2026/10/03 with
`password authentication failed for user "api-readonly"`. The chart has generated the
login's password since 2026/08/11 (`templates/accounts/api-postgres.yaml`), but nothing ever
created the Postgres role. The CronJob was applied by hand from
`k8s-avepoint-run-check.yaml`, outside the chart, whose comment said the role "has to be
created once". That step was never done.

## What was built

- `templates/issassist/api/postgres-readonly-role.yaml`: a `post-install,post-upgrade` hook
  Job on the chart's Postgres image. It connects as `api` with `sslmode=verify-full`
  against `issassist-ca-cert`, then runs `role.sql`:
  - it refuses a role it did not create (see the traps below);
  - it creates the role if it is missing and marks it with a comment;
  - it sets `LOGIN NOSUPERUSER … CONNECTION LIMIT 3` and the password from the Secret;
  - it grants CONNECT on `api` and USAGE on schema `avepoint`;
  - it revokes everything the role holds on tables in `avepoint`;
  - it grants SELECT on the ten columns the check reads:
    - `avepoint.snapshots`: `customer_id, customer_name, record_type, service_name, tenant_id, collected_at`;
    - `avepoint.raw_responses`: `kind, http_status, attempt, collected_at`.
- `templates/issassist/api/avepoint-run-check.yaml`: the hand-applied CronJob, moved into the
  chart.
  - The script is unchanged.
  - The namespace is no longer hard-coded, and the schedule comes from values.
  - The connection now verifies the server with `verify-full`. Before, it used libpq's
    default `prefer`, which encrypts but checks nothing.
- Both pods set `automountServiceAccountToken: false`.
- `scripts/check_readonly_role.sh` runs the render checks. With `--live` it also runs the
  rendered scripts against `postgres:17` over TLS (see Tests).

## Changed from the mockup

| Mockup | Built | Why |
|---|---|---|
| Waits up to 10 minutes for the schema | Waits up to 4 minutes, for the two tables | Helm waits for hook Jobs and fails the release at `--timeout`, which is 5 minutes by default. A 10-minute wait would have failed every fresh install. |
| SELECT on all tables in `avepoint`, plus default privileges for new tables | SELECT on 10 named columns, with no default privileges | Security review. `avepoint` also holds `credentials`, with the AvePoint partner `client_id` and the encrypted secret, and `raw_responses.payload` holds AvePoint's replies verbatim. A table the API adds later must not become readable without a diff in this chart. |
| Changes any role named in the Secret | Changes only a role it marked, and none that belongs to another role | Security review: anyone who can edit the Secret could otherwise point the Job at another role and strip or reset it. |
| `SET log_min_error_statement = panic` | Also `SET log_statement = 'none'` | Security review: with DDL auditing on (`log_statement=ddl`), a successful `ALTER ROLE … PASSWORD` is logged in full. |

## Decisions and traps

- **The Job never fails the release.** A refused role or a failed `ALTER ROLE` prints
  `ERROR: could not set up the role` and exits 0. Failing an upgrade over a monitoring login
  would be the wrong trade, and the problem still shows: the next morning's check fails to
  authenticate.
  - The case the review raised is also covered. If the Secret is rotated and the reset
    fails, the old password stays valid, but the check reads the *new* one from the Secret,
    so it fails too.
- **No password on a command line.** `psql -v ro_password=…` would put it in
  `/proc/<pid>/cmdline`. `role.sql` reads it with `\getenv`, which needs psql 15 or later;
  the image is postgres:17.
- **The role name comes from the Secret** (`username: api-readonly`) and is quoted with `%I`
  and `:"ro_user"`.
  - The Job changes the role only if it doesn't exist yet, or if it carries the comment
    `managed by issassist.helm: api-postgres-readonly-role` and belongs to no other role.
  - The login `api` is therefore refused before any `ALTER ROLE` runs.
- **`REVOKE ALL ON ALL TABLES IN SCHEMA avepoint` runs on every run**, so a grant made by
  hand is taken back. Revoking a table privilege also revokes the matching column
  privileges.
- **Turning it off does not drop the role.** Dropping it would need ownership checks, and
  the role can read only ten columns.
- **If the check ever reads another column, grant it here.** Otherwise the check fails with
  `permission denied`, which `check.sh` reports as "cannot query the database", exit 2.

## Security review (2026/11/03)

Secret check clean (exit 0). Fixed before merge:

- **MEDIUM:** SELECT on the whole `avepoint` schema included `credentials` and
  `raw_responses.payload`, and RELEASE.md said otherwise. Now column grants.
- **MEDIUM:** default privileges widened the grant silently. Removed.
- **LOW:** the password was in the server log with `log_statement=ddl`. Now `log_statement = 'none'`.
- **LOW:** any role named in the Secret could be reshaped. Now refused unless marked.
- **INFO:** the ServiceAccount token was mounted. Now it is not.

Accepted, and argued above: on a failed reset the Job exits 0.

Findings that were already there before this change are tracked privately in IssTech/isstech-issues#485, not here.

## Tests

`bash scripts/check_readonly_role.sh --live` runs 18 render checks and 23 live checks. The
live server runs with `log_statement=ddl`, so the password check covers DDL auditing.

Each of these deliberate breaks made at least one check fail:

| Break | Check that failed |
|---|---|
| `log_min_error_statement` removed | the server log holds the password |
| `log_statement = 'none'` removed | the server log holds the password |
| `verify-full` changed to `require` | the Job verifies the server certificate |
| SELECT on `public` granted | the role cannot read other tables |
| SELECT on the whole `avepoint` schema | cannot read the AvePoint secret, nor its raw replies |
| the REVOKE removed | takes back a grant made by hand |
| the ownership check removed | a role this chart did not create is refused |
| the membership condition removed | a marked role that is a member of another is refused |
| the check's guard removed | the check without the role fails |
| `enabled: yes` treated as on | readonlyRole yes is not on |
| exit 1 on a failed ALTER | does not fail the release |
| the check's `automountServiceAccountToken` removed | the check mounts no ServiceAccount token |

The chart repo has no CI, so this runs by hand, as `check_ai_analysis_render.sh` does.

## Staging, once

Delete the hand-applied resources before the first upgrade that enables the check, or Helm
refuses to adopt them:

```bash
kubectl -n issassist-staging delete cronjob,configmap avepoint-run-check
helm -n issassist-staging upgrade issassist . --reuse-values \
  --set api.postgres.readonlyRole.enabled=true --set api.avepointRunCheck.enabled=true
```
