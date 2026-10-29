# IssAssist Preview (IA-0018): the chart side

Mission IssTech/isstech-issues#464; the design, the traps and the tests are in
`issassist-api/docs/projects/2026-10-29-issassist-preview.md`.

The chart adds one key, `global.preview.allowed` (default `true`), rendered as
`IA_PREVIEW_ALLOWED` on the API with the same fail-closed expression as `IA_SUPPORT_SEND`:
`true`, or the key absent (an upgrade from an older chart), renders `"true"`; anything else
renders `"false"`.

Checked by rendering, since this repo has no CI (2026/10/29):

| values | rendered |
|---|---|
| default, `preview: null`, `preview: {}`, `allowed: null` | `"true"` (upgrade from an older chart) |
| `allowed: true` | `"true"` |
| `allowed: false`, `allowed: 'True'`, `allowed: 1` | `"false"` |
| `preview: false`, `preview: 0`, `preview: true` | `"false"` |

The security review found that the first version rendered `"true"` for `preview: false`:
`default dict` turns a falsy scalar into an empty map, whose missing `.allowed` reads as the
upgrade case. The template now treats anything that is not a map as locked. **The same shape
is still in `IA_SUPPORT_SEND` (`support: false` renders `"true"`)**, pre-existing and not
changed here.

`helm template` against `origin/review` differs only by that env var. `helm lint` reports the
same pre-existing `kubernetes-secret-generator` dependency error as `review`.

Staging needs nothing new: the default allows Preview, and it is switched on there in the UI.
