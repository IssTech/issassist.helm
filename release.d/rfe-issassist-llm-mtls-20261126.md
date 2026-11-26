---
release: 1.6.0
date: 2026/11/26
---
### Mutual TLS and an internal price for the IssAssist LLM (2026/11/26)

> A first test for the Kasten demo on 2026/12/04; it will be revisited before release.

- **What it is:** Values that let the API present a client certificate to the `local`
  AI provider (for example the GPU cluster's Ollama behind ghostunnel), and give an
  endpoint outside this cluster the internal cost price it needs before it may be used.
- **Where it is:** `values.yaml` → `aiAnalysis.providers.local.clientTls.secretName`
  (a `kubernetes.io/tls` Secret: `tls.crt`, `tls.key`), `.caConfigMap` and `.caKey`
  (the public CA that signed the server), and
  `aiAnalysis.providers.local.priceInEurPerMtok` / `priceOutEurPerMtok`. The files are
  mounted read-only at `/etc/issassist-llm-client` **in the API pod only**; the prices go
  to the `issassist-ai-analysis` ConfigMap (`IA_AI_LOCAL_PRICE_IN` / `_OUT`).
- **What changed for them:** all empty by default, so nothing changes. Setting some of
  the three `clientTls` keys but not all **fails the render** with *set secretName,
  caConfigMap and caKey together, or none of them*. A missing Secret or ConfigMap keeps
  the API pod from starting, so **create them before the upgrade. In IssDev: create
  this installation's leaf certificate (one per install, e.g. CN
  `issassist-api-staging`), run its copier into this namespace, and add the CN to
  ghostunnel's `--allow-cn` list**, then make sure the CA bundle ConfigMap is synced here.
  **Also raise `aiAnalysis.providers.local.dailyCap` / `dailyCapMax` above 0 (EUR): they
  default to 0, which stops an endpoint outside the cluster even with a price set.**
- **Where the detail is:** [issassist-api docs/projects/2026-11-26-issassist-llm-mtls.md](https://github.com/IssTech/issassist-api/blob/review/docs/projects/2026-11-26-issassist-llm-mtls.md)
