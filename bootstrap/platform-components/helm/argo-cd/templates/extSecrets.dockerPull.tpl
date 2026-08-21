{{- range $key, $secret := (.Values.bootstrapValues).dockerPullSecrets }}
apiVersion: external-secrets.io/v1
kind: ClusterExternalSecret
metadata:
  name: {{ $secret.name }}-ces
spec:
  externalSecretName: {{ $secret.name }}-es
  namespaceSelectors:
    {{- if $secret.matchNamespaceLabels }}
    - matchLabels:
      {{- with $secret.matchNamespaceLabels }}
        {{- toYaml . | nindent 8 }}
      {{- end }}
    {{- end }}
  refreshTime: 1m
  externalSecretSpec:
    refreshInterval: {{ default "5m" $secret.refreshInterval }}
    secretStoreRef:
      kind: {{ $secret.secretStoreRef.kind }}
      name: {{ $secret.secretStoreRef.name }}
    target:
      name: {{ $secret.name }}
      creationPolicy: Owner
      template:
        type: kubernetes.io/dockerconfigjson
        data:
          .dockerconfigjson: "{{ "{{" }} .dockerconfigjson }}"
    data:
      - secretKey: dockerconfigjson
        remoteRef:
          {{- if $secret.remoteRef }}
          key: {{ $secret.remoteRef.remoteKey }}
          {{- if $secret.remoteRef.remoteKeyProperty }}
          property: {{ $secret.remoteRef.remoteKeyProperty }}
          {{- end }}
          {{- else }}
          key: {{ $secret.name }}
          {{- end }}
          conversionStrategy: Default
          decodingStrategy: None
          metadataPolicy: None
          nullBytePolicy: Fail
---
{{- end }}
