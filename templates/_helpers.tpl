{{- define "imagePullSecret" }}
{{- with .Values.imageCredentials }}
{{- printf "{\"auths\":{\"%s\":{\"username\":\"%s\",\"password\":\"%s\",\"auth\":\"%s\"}}}" .registry .username .password (printf "%s:%s" .username .password | b64enc) | b64enc }}
{{- end }}
{{- end }}

{{- define "apiUrl" }}
{{- if eq (.Values.global.publicPort | toString) "443" }}
{{- print "https://" .Values.global.publicDomainName "/api/v1/" }}
{{- else }}
{{- print "https://" .Values.global.publicDomainName ":" .Values.global.publicPort "/api/v1/" }}
{{- end }}
{{- end }}