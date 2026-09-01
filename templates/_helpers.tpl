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
