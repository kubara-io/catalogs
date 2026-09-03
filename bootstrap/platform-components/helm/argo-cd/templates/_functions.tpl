{{- define "bootstrap.tpl-param" }}
{{- $ctx := .ctx }}
{{- range $_, $parameters := .param }}
- name: {{ get $parameters "name" | squote }}
  value: {{ tpl (get $parameters "value") $ctx | squote }}
{{- end }}
{{- end }}
