---
release: 2.0.0
date: 2026/11/26
---
### IssTech's Kanister Blueprint library: where IssAssist reads it (IA-0033, #514) (2026/11/26)

- **What it is:** IssAssist 2.0 (Preview `kasten-blueprints`) offers IssTech's lab-tested Kanister
  Blueprints on the Kasten Workloads page. The library is bundled inside the API image, so an
  air-gapped Dark Site has it with no network at all.
- **Where it is:** `values.yaml` key `api.kasten.blueprintLibrary.url` (env
  `IA_KASTEN_BLUEPRINT_LIBRARY_URL` on the API).
- **What changed for them:** Nothing by default: the key is empty and the bundled library is used.
  **Set it only to an `https://` address** where a newer `index.json` lives; IssAssist reads it at
  most once a day, checks each Blueprint against the index's SHA-256, and falls back to the
  bundled copy on any failure. Nothing is ever sent to that address.
- **Detail:** issassist-api `docs/projects/2026-11-26-ia-0032-blueprint-builder.md`
