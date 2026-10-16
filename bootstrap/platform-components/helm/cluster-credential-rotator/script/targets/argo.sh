#!/bin/sh

project_argo_target() (
  cluster_name=$1
  server=$2
  token=$3
  ca_data=$4
  insecure=$5
  source_labels_file=$6
  issued_at=$7
  expires_at=$8

  if [ "$TARGET_ARGO_ENABLED" != "true" ]; then
    return 0
  fi

  target_ns="$TARGET_ARGO_NAMESPACE"
  target_secret_name="${cluster_name}${TARGET_ARGO_SECRET_SUFFIX}"

  work_dir="$(mktemp -d)" || return 1
  trap 'rm -rf "$work_dir"' EXIT INT TERM

  argo_labels_file="${work_dir}/argo-labels"
  current_labels_file="${work_dir}/current-labels"
  labels_json_file="${work_dir}/labels.json"
  labels_patch_file="${work_dir}/labels-patch.json"
  argo_patch_file="${work_dir}/argo-patch.json"

  # Combine source labels with Argo CD secret type label
  {
    cat "$source_labels_file"
    printf '%s=%s\n' "argocd.argoproj.io/secret-type" "cluster"
  } | grep -v '^$' | sort -u >"$argo_labels_file"

  escaped_name="$(json_escape "$cluster_name")" || return 1
  escaped_server="$(json_escape "$server")" || return 1
  argo_config="$(
    printf \
      '{"bearerToken":"%s","tlsClientConfig":{"caData":"%s","insecure":%s}}' \
      "$token" \
      "$ca_data" \
      "$insecure"
  )"
  escaped_config="$(json_escape "$argo_config")" || return 1

  # Create secret if it does not exist yet
  if ! kubectl -n "$target_ns" get secret "$target_secret_name" >/dev/null 2>&1; then
    if ! kubectl -n "$target_ns" create secret generic "$target_secret_name" --type=Opaque >/dev/null; then
      log "failed to create Argo CD secret ${target_ns}/${target_secret_name}"
      return 1
    fi
  fi

  cat >"$argo_patch_file" <<EOF_ARGO_PATCH
{
  "metadata": {
    "annotations": {
      "kubara.io/cluster-credential-issued-at": "${issued_at}",
      "kubara.io/cluster-credential-expires-at": "${expires_at}",
      "kubara.io/cluster-credential-managed-by": "cluster-credential-rotator"
    }
  },
  "stringData": {
    "name": "${escaped_name}",
    "server": "${escaped_server}",
    "${TARGET_ARGO_CONFIG_KEY}": "${escaped_config}"
  }
}
EOF_ARGO_PATCH

  if ! kubectl \
    -n "$target_ns" \
    patch secret "$target_secret_name" \
    --type merge \
    --patch-file "$argo_patch_file" \
    >/dev/null; then
    log "failed to patch credentials for Argo CD secret ${target_ns}/${target_secret_name}"
    return 1
  fi

  if ! sync_secret_labels \
    "$target_ns" \
    "$target_secret_name" \
    "$argo_labels_file" \
    "$current_labels_file" \
    "$labels_json_file" \
    "$labels_patch_file"; then
    log "failed to sync labels for Argo CD secret ${target_ns}/${target_secret_name}"
    return 1
  fi

  log "reconciled Argo CD target secret ${target_ns}/${target_secret_name}"
)
