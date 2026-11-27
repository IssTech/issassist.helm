---
release: 1.6.0
date: 2026/11/27
---
### Own infrastructure needs a price, a daily cap and an end date (2026/11/27)

- **What it is:** `aiAnalysis.providers.local.ownInfrastructure: true` (IssTech staging's use
  of the GPU cluster) is now priced and capped like any endpoint outside the cluster (owner
  decision D5 = C), and it ends on a date you choose (D2 = B), at most 92 days ahead. After
  that date the API keeps using the endpoint as an ordinary external one, priced and capped,
  without the Kasten, Overview and Blueprint AI features. No automatic renewal.
- **Where it is:** `values.yaml` → `aiAnalysis.providers.local.ownInfrastructureUntil`
  (new, `YYYY/MM/DD`) → `IA_AI_LOCAL_OWN_INFRASTRUCTURE_UNTIL` (ISO, e.g. `2026-12-31`) in
  the `issassist-ai-analysis` ConfigMap; and the existing `priceInEurPerMtok`,
  `priceOutEurPerMtok`, `dailyCap`, `dailyCapMax` under `aiAnalysis.providers.local`.
- **What changed for them:** with `ownInfrastructure: true` the render now **fails** unless
  both prices and both caps are above 0, and unless `ownInfrastructureUntil` is a real date
  between today (UTC) and 92 days ahead. `2026/02/30` is refused, never rolled over. The error
  says which and gives the latest allowed date, e.g. *"ownInfrastructureUntil (2026/12/31)
  has passed: own infrastructure was a staging test. Remove ownInfrastructure, or set a new
  date (at most 2027/04/04) after reviewing it."* Installations without `ownInfrastructure`
  render exactly as before (the new ConfigMap key is empty).
  **Staging: add these to staging's values on the next `helm upgrade`, or the upgrade fails:**

  ```yaml
  aiAnalysis:
    providers:
      local:
        ownInfrastructure: true
        ownInfrastructureUntil: "2026/12/31"   # at most 92 days ahead; renew by hand
        priceInEurPerMtok: "10"                # internal cost price, EUR per million tokens
        priceOutEurPerMtok: "10"
        dailyCap: 1.5                          # EUR, about 35 analyses; below the GPU's 300 000-token day
        dailyCapMax: 5
  ```
  **Diary the end date: after it the demo features (Kasten failure analysis, Overview
  summary, Blueprint drafts) stop using the GPU until a new date is set and upgraded.**
- **Where the detail is:** [issassist-api docs/projects/2026-11-27-own-infrastructure-cap-and-end-date.md](https://github.com/IssTech/issassist-api/blob/review/docs/projects/2026-11-27-own-infrastructure-cap-and-end-date.md).
