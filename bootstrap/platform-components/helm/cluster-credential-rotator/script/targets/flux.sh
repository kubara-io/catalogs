#!/bin/sh

project_flux_target() (
  cluster_name=$1
  kubeconfig_file=$2
  source_labels_file=$3
  issued_at=$4
  expires_at=$5

  if [ "$TARGET_FLUX_ENABLED" != "true" ]; then
    return 0
  fi

  target_ns="$TARGET_FLUX_NAMESPACE"
  target_secret_name="${cluster_name}${TARGET_FLUX_SECRET_SUFFIX}"

  work_dir="$(mktemp -d)" || return 1
  trap 'rm -rf "$work_dir"' EXIT INT TERM

  flux_labels_file="${work_dir}/flux-labels"
  current_labels_file="${work_dir}/current-labels"
  labels_json_file="${work_dir}/labels.json"
  labels_patch_file="${work_dir}/labels-patch.json"
  flux_patch_file="${work_dir}/flux-patch.json"

  # Copy source labels
  grep -v '^$' "$source_labels_file" | sort -u >"$flux_labels_file"

  kubeconfig_content="$(cat "$kubeconfig_file")" || return 1
  escaped_kubeconfig="$(json_escape "$kubeconfig_content")" || return 1

  # Ensure secret exists and is managed by cluster-credential-rotator
  if ! ensure_managed_target_secret "$target_ns" "$target_secret_name"; then
    return 1
  fi

  cat >"$flux_patch_file" <<EOF_FLUX_PATCH
{
  "metadata": {
    "annotations": {
      "kubara.io/cluster-credential-issued-at": "${issued_at}",
      "kubara.io/cluster-credential-expires-at": "${expires_at}",
      "kubara.io/cluster-credential-managed-by": "cluster-credential-rotator"
    }
  },
  "stringData": {
    "${TARGET_FLUX_KUBECONFIG_KEY}": "${escaped_kubeconfig}"
  }
}
EOF_FLUX_PATCH

  if ! kubectl \
    -n "$target_ns" \
    patch secret "$target_secret_name" \
    --type merge \
    --patch-file "$flux_patch_file" \
    >/dev/null; then
    log "failed to patch credentials for Flux secret ${target_ns}/${target_secret_name}"
    return 1
  fi

  if ! sync_secret_labels \
    "$target_ns" \
    "$target_secret_name" \
    "$flux_labels_file" \
    "$current_labels_file" \
    "$labels_json_file" \
    "$labels_patch_file"; then
    log "failed to sync labels for Flux secret ${target_ns}/${target_secret_name}"
    return 1
  fi

  log "reconciled Flux target secret ${target_ns}/${target_secret_name}"
)
