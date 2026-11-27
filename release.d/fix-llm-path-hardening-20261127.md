---
release: 1.6.0
date: 2026/11/27
---
### The IssAssist LLM client key is readable by the API only, and the model's context size is a value (2026/11/27)

- **What it is:** two changes to the *IssAssist LLM / own LLM* settings. (1) The client
  certificate's private key, mounted for mutual TLS, was readable by every user id in the
  API container (mode 0444). It is now mode 0440, owned by root and the API pod's group,
  so only the API reads it. (2) A new value tells the API how many tokens the model can
  read at once, so the API refuses a request the model would cut without saying so.
- **Where it is:** `values.yaml` → `aiAnalysis.providers.local.clientTls.fsGroup` (default
  `1000`, the API image's own group) and `aiAnalysis.providers.local.contextTokens`
  (default `4096`) → `IA_AI_LOCAL_CONTEXT_TOKENS` in the `issassist-ai-analysis`
  ConfigMap. The API Deployment gets `securityContext.fsGroup` **only when `clientTls` is
  set**; without it nothing renders differently there.
- **What changed for them:** with `clientTls` set, the API pod restarts on upgrade with the
  new group and file mode; nothing else to do. `fsGroup` 0, negative or not a number
  **fails the render**. **Where a policy fixes the allowed groups (an OpenShift SCC
  range), set `fsGroup` to a group inside it.** `contextTokens` that is 0 or not a number
  **fails the render**. **Set `contextTokens` to what the model server really runs
  (Ollama: `OLLAMA_CONTEXT_LENGTH`, or Ollama's own default, 4096 on the GPU cluster
  today), never higher.**
- **Where the detail is:** [issassist-api docs/projects/2026-11-26-issassist-llm-mtls.md](https://github.com/IssTech/issassist-api/blob/review/docs/projects/2026-11-26-issassist-llm-mtls.md), section *Hardening 2026/11/27*.
