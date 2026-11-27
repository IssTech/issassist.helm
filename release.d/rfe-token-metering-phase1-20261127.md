---
release: 1.6.0
date: 2026/11/27
---
### How long IssAssist keeps each counted AI call (2026/11/27)

- **What it is:** IssAssist (API 1.6.0) counts the tokens of every AI call in the
  installation, for the IssAssist LLM licence page. This value sets how long each counted
  call is kept. The per-day sums the page shows are kept regardless.
- **Where it is:** `aiAnalysis.metering.keepDays` in `values.yaml` (default **400**,
  31 to 3650), rendered as `IA_AI_METERING_KEEP_DAYS` in the `issassist-ai-analysis`
  ConfigMap. The daily job *Token usage per day* (00:20 UTC) removes older calls.
- **What changed for them:** nothing to set. An upgrade with `--reuse-values` from an
  older release renders 400. A value the API cannot read is treated as 400, and below 31
  as 31, so a typo never deletes more than meant. Nothing is sent to IssTech by this.
- **Where the detail is:** issassist-api `docs/projects/2026-11-27-token-metering.md`
