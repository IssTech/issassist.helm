# API ↔ TSM agent over mutual TLS (2026/11/02)

Decided by the product owner on 2026/10/30, "encrypted communication only, never
unencrypted". It was found while drawing the #463 data-flow mockup, and approved as its own
change on 2026/11/02.

## What was wrong

Both ends could do mTLS. `issassist-utils/grpc/server.py` calls `ssl_server_credentials(...,
require_client_auth=True)`, the API's `tsm/__init__.py` builds client credentials, the
certificates existed, and both ConfigMaps already named the certificate paths. The chart
still set `tls = false` on both sides.

The likely reason: the TSM agent's `livenessProbe` used the kubelet's built-in `grpc:` probe,
which has no TLS support. With TLS on, every probe would have failed and the agent would
have been restarted in a loop.

## What changed

- `templates/issassist/api/configmap.yaml`: `[tsm_agent] tls = true`.
- `templates/issassist/tsm-agent/configmap.yaml`: `[connection] tls = true`.
- `templates/issassist/tsm-agent/deployment.yaml`: an `exec` liveness probe that runs the
  image's Python (`/app/.venv/bin` is on `PATH`) and calls `grpc.health.v1.Health/Check` on
  `localhost:50051` over mTLS. It uses the agent's own certificate, which carries
  `client auth` and has `localhost` in its `dnsNames`. It exits 0 only for SERVING.
  `periodSeconds: 30` because each run starts a Python process.
- `checksum/config` pod annotations on the API and TSM agent deployments. Without them a
  ConfigMap-only upgrade left the pods on their old `config.toml`, and this change would not
  have taken effect until some unrelated restart.

No `values.yaml` switch, on purpose: a switch to turn encryption off is the thing the rule
forbids.

## Verified on staging (helm revision 148, API 1.5.0-197)

- The TSM agent logged `Listening on 0.0.0.0:50051 ...` with no "TLS is disabled" line.
- From inside the API pod against `tsm-agent:50051`:
  - mTLS with `api-cert`: `SERVING`;
  - TLS without a client certificate: refused (`UNAVAILABLE`; the agent logged
    `PEER_DID_NOT_RETURN_A_CERTIFICATE`);
  - plaintext: refused (`UNAVAILABLE`; the agent logged `WRONG_VERSION_NUMBER`).
- The exec probe passed. All three agent replicas showed 0 restarts after 108 s.
- A real call: at 12:08:46 the API logged `tsm-oc.backup.sto1.safedc.net synced.`, the
  scheduled Operations Center sync going through the agent.
- The API logged `Could not connect to TSM agent` once, at 11:58:17, three seconds before the
  agents were listening. That is the startup info call. The gRPC channel reconnects by
  itself, and the sync above went through.

Rollback: `helm rollback issassist 147` restores the plaintext configuration.

## Not covered

- No test in this repo renders the chart; there is no chart test suite yet. The
  verification is the staging run above.
- Customer upgrades get the same brief reconnect window, which RELEASE.md states.
- The messaging certificates (`messaging.crt`) and the database and Valkey connections are
  unchanged. Those already use TLS (`[database] tls = true`).
