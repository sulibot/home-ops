{{- define "app-scaffolder.appName" -}}
{{- replace "_" "-" . | lower -}}
{{- end }}

{{- define "app-scaffolder.hostname" -}}
{{- $name := include "app-scaffolder.appName" .name -}}
{{- if .custom }}
{{- .custom -}}
{{- else -}}
{{- printf "%s.%s" $name .domain -}}
{{- end -}}
{{- end }}
