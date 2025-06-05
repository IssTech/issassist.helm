{{- define "imagePullSecret" }}
{{- with .Values.imageCredentials }}
{{- printf "{\"auths\":{\"%s\":{\"username\":\"%s\",\"password\":\"%s\",\"auth\":\"%s\"}}}" .registry .username .password (printf "%s:%s" .username .password | b64enc) | b64enc }}
{{- end }}
{{- end }}

{{- define "apiUrl" }}
{{- if eq (.Values.global.publicPort | toString) "443" }}
{{- print "https://" .Values.global.publicDomainName .Values.global.basePath "/api/v1/" }}
{{- else }}
{{- print "https://" .Values.global.publicDomainName ":" .Values.global.publicPort .Values.global.basePath "/api/v1/" }}
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
