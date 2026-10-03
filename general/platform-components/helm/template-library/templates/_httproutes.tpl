{{/* Render HTTPRoutes and namespace-local authentication middleware. */}}
{{- define "templateLibrary.httpRoutes" -}}
{{- with .Values.gatewayRoutes }}
{{- if .enabled }}
{{- $root := $ }}
{{- $routing := . }}
{{- if .auth }}
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: {{ $root.Release.Name }}-gateway-auth
  namespace: {{ $root.Release.Namespace }}
spec:
  forwardAuth:
    address: http://oauth2-proxy.oauth2-proxy.svc.cluster.local/oauth2/
    trustForwardHeader: true
    authResponseHeaders:
      - X-Auth-Request-User
      - X-Auth-Request-Email
      - Authorization
{{- end }}
{{- range .routes }}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ $root.Release.Name }}-{{ .name }}
  namespace: {{ $root.Release.Namespace }}
  {{- with $routing.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  parentRefs:
    - name: {{ $routing.parentRef.name | quote }}
      namespace: {{ $routing.parentRef.namespace | quote }}
      {{- with $routing.parentRef.sectionName }}
      sectionName: {{ . | quote }}
      {{- end }}
  hostnames:
    - {{ $routing.hostname | quote }}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: {{ .path | quote }}
      {{- if or $routing.auth .middlewares }}
      filters:
        {{- if $routing.auth }}
        - type: ExtensionRef
          extensionRef:
            group: traefik.io
            kind: Middleware
            name: {{ $root.Release.Name }}-gateway-auth
        {{- end }}
        {{- range .middlewares }}
        - type: ExtensionRef
          extensionRef:
            group: traefik.io
            kind: Middleware
            name: {{ . }}
        {{- end }}
      {{- end }}
      backendRefs:
        - name: {{ tpl .service $root | quote }}
          port: {{ .port }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
