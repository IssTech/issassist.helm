{{/*
Name of the image pull secret to reference.

Two ways to supply registry credentials:

  imageCredentials.existingSecret   a docker-registry Secret you created yourself.
                                    Preferred — the credential never becomes a Helm
                                    value, so it stays out of the release secret and
                                    out of `helm get values`.

  imageCredentials.username/password  templated into a Secret by this chart.
                                    Works, but Helm stores user-supplied values in
                                    plaintext in the release secret, where every
                                    revision keeps a copy. A live token was found
                                    sitting there in 2026-09; that is why the option
                                    above exists.
*/}}
{{- define "issassist.imagePullSecretName" -}}
{{- default "isstech-repository-auth" .Values.imageCredentials.existingSecret -}}
{{- end }}

{{- define "imagePullSecret" }}
{{- with .Values.imageCredentials }}
{{- printf "{\"auths\":{\"%s\":{\"username\":\"%s\",\"password\":\"%s\",\"auth\":\"%s\"}}}" .registry .username .password (printf "%s:%s" .username .password | b64enc) | b64enc }}
{{- end }}
{{- end }}

{{- define "webGUIOrigin" }}
{{- if eq (.Values.global.publicPort | toString) "443" }}
{{- print .Values.global.publicScheme "://" .Values.global.publicDomainName }}
{{- else }}
{{- print .Values.global.publicScheme "://" .Values.global.publicDomainName ":" .Values.global.publicPort  }}
{{- end }}
{{- end }}

{{- define "apiUrl" }}
{{- if eq (.Values.global.publicApiPort | toString) "443" }}
{{- print .Values.global.publicScheme "://" .Values.global.publicDomainName .Values.global.basePath "/api/v1/" }}
{{- else }}
{{- print .Values.global.publicScheme "://" .Values.global.publicDomainName ":" .Values.global.publicApiPort .Values.global.basePath "/api/v1/" }}
{{- end }}
{{- end }}

{{/* Follows the rules defined by
     https://github.com/pgadmin-org/pgadmin4/blob/3286b4e32faa6770e1699bd30d0a8dd4f47bd72e/web/pgadmin/utils/paths.py#L23 */}}
{{- define "pgAdminUserStorageDir" }}
{{- if regexMatch .Values.global.adminAccount.email "^[0-9]*$" }}
    {{- print "pga_user_" .Values.global.adminAccount.email }}
{{- else }}
    {{- print .Values.global.adminAccount.email
        | replace "@" "_" | replace "/" "slash" | replace "\\" "slash" }}
{{- end }}
{{- end }}

{{/*
The Secret that holds an AI provider's key set through Helm (#463 slice 1b), or ""
when Helm sets none. `apiKey` wins over `existingSecret`: the chart then renders
`issassist-ai-<id>-key` (templates/issassist/api/ai-provider-keys.yaml). Called with
(dict "id" <provider id> "p" <its values map>).
*/}}
{{- define "issassist.aiKeySecretName" -}}
{{- $p := .p | default dict -}}
{{- /* Wherever ai-provider-keys.yaml renders one: Bob's too. Whether a key is mounted
       into the API pod is decided in the Deployment, and Bob's never is. */ -}}
{{- if and (kindIs "map" $p) $p.apiKey (has .id (list "local" "claude" "gemini" "bob" "copilot")) -}}
issassist-ai-{{ .id }}-key
{{- else if and (kindIs "map" $p) (trim (toString ($p.existingSecret | default ""))) -}}
{{ trim (toString $p.existingSecret) }}
{{- end -}}
{{- end }}

{{/*
IBM Bob's gateways (decided 2026/11/04), as JSON: {"regions": {name: address},
"region": the default, "fixed": a customer's own address or ""}. The web GUI
chooses among `regions`; the admission policy admits these addresses and no other.

`regions` falls back to IBM's three: --reuse-values rebases on a release from
before the key existed. A `gatewayUrl` that is one of them (the old default) is
that region; any other is fixed, and then nothing can be chosen. Called with the
bob values map.
*/}}
{{- define "issassist.bobGateways" -}}
{{- $bob := . | default dict -}}
{{- /* A host, an optional port and an optional path: no credentials, query, fragment
       or whitespace (security review, 2026/11/04). */ -}}
{{- $plain := "^https://[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$" -}}
{{- $regions := $bob.regions | default (dict "us-east" "https://api.us-east.bob.ibm.com" "eu-de" "https://api.eu-de.bob.ibm.com" "jp-tok" "https://api.jp-tok.bob.ibm.com") -}}
{{- if not (kindIs "map" $regions) }}{{ fail "aiAnalysis.providers.bob.regions must be a map of region to https:// address" }}{{ end -}}
{{- range $name, $url := $regions -}}
{{- if not (regexMatch "^[a-z0-9][a-z0-9-]{0,31}$" $name) }}{{ fail "aiAnalysis.providers.bob.regions: a region name is lowercase letters, digits and -" }}{{ end -}}
{{- if or (not (kindIs "string" $url)) (not (regexMatch $plain $url)) }}{{ fail "aiAnalysis.providers.bob.regions: every address must be a plain https:// URL" }}{{ end -}}
{{- end -}}
{{- $fixed := $bob.gatewayUrl | default "" -}}
{{- if and $fixed (not (regexMatch $plain $fixed)) }}{{ fail "aiAnalysis.providers.bob.gatewayUrl must be a plain https:// URL" }}{{ end -}}
{{- $region := $bob.region | default "eu-de" -}}
{{- range $name, $url := $regions }}{{ if eq $url $fixed }}{{ $region = $name }}{{ $fixed = "" }}{{ end }}{{ end -}}
{{- if $fixed -}}
{{- $regions = dict -}}
{{- else if not (hasKey $regions $region) -}}
{{- /* Fails only where Bob is allowed: elsewhere an old free-text region must not
       stop an upgrade. Unlisted, nothing is chosen and Bob says it is not set up. */ -}}
{{- if eq (toString $bob.allowed) "true" }}{{ fail "aiAnalysis.providers.bob.region must be one of aiAnalysis.providers.bob.regions" }}{{ end -}}
{{- $region = "" -}}
{{- end -}}
{{- dict "regions" $regions "region" $region "fixed" $fixed | toJson -}}
{{- end }}

{{/*
Whether IBM Bob's run namespace and admission policies are rendered: "true" or "".
`aiAnalysis.providers.bob.clusterResources` true or false decides; unset, it follows
`clusterScoped.create`. Its own switch (decided 2026/11/04) so that Bob can be set up
where the restore tests' ClusterRole is not wanted. Called with the root context.
*/}}
{{- define "issassist.bobClusterResources" -}}
{{- $bob := ((.Values.aiAnalysis | default dict).providers | default dict).bob | default dict -}}
{{- $scoped := .Values.clusterScoped | default dict -}}
{{- $own := $bob.clusterResources -}}
{{- if and (hasKey $bob "clusterResources") (not (kindIs "invalid" $own)) (ne (toString $own) "") -}}
{{- if eq (toString $own) "true" }}true{{ else if ne (toString $own) "false" }}{{ fail "aiAnalysis.providers.bob.clusterResources must be true, false or empty" }}{{ end -}}
{{- else if eq (toString $scoped.create) "true" -}}
true
{{- end -}}
{{- end }}
