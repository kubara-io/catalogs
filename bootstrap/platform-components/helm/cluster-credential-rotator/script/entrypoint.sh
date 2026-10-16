#!/bin/sh

set -u
umask 077

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source configuration and modular libraries
. "${SCRIPT_DIR}/config.env"
. "${SCRIPT_DIR}/common.sh"
. "${SCRIPT_DIR}/k8s.sh"
. "${SCRIPT_DIR}/agent.sh"
. "${SCRIPT_DIR}/target-argo.sh"
. "${SCRIPT_DIR}/target-flux.sh"

TARGET_SECRET_NAME="${KUBARA_TARGET_SECRET_NAME:-}"
ISSUED_AT_ANNOTATION="kubara.io/cluster-credential-issued-at"
EXPIRES_AT_ANNOTATION="kubara.io/cluster-credential-expires-at"
MANAGED_BY_ANNOTATION="kubara.io/cluster-credential-managed-by"
MANAGED_BY_VALUE="cluster-credential-rotator"

patch_agnostic_secret_with_credentials() (
  secret_name=$1
  patch_file=$2
  cluster_name=$3
  server=$4
  kubeconfig_content=$5
  token=$6
  ca_data=$7
  insecure=$8
  issued_at=$9
  expires_at=${10}

  escaped_name="$(json_escape "$cluster_name")" || return 1
  escaped_server="$(json_escape "$server")" || return 1
  escaped_kubeconfig="$(json_escape "$kubeconfig_content")" || return 1
  escaped_token="$(json_escape "$token")" || return 1
  escaped_ca_data="$(json_escape "$ca_data")" || return 1
  escaped_insecure="$(json_escape "$insecure")" || return 1

  cat >"$patch_file" <<EOF_PATCH
{
  "metadata": {
    "annotations": {
      "${ISSUED_AT_ANNOTATION}": "${issued_at}",
      "${EXPIRES_AT_ANNOTATION}": "${expires_at}",
      "${MANAGED_BY_ANNOTATION}": "${MANAGED_BY_VALUE}"
    }
  },
  "stringData": {
    "name": "${escaped_name}",
    "server": "${escaped_server}",
    "${KUBECONFIG_KEY}": "${escaped_kubeconfig}",
    "token": "${escaped_token}",
    "caData": "${escaped_ca_data}",
    "insecure": "${escaped_insecure}"
  }
}
EOF_PATCH

  kubectl \
    -n "$RELEASE_NAMESPACE" \
    patch secret "$secret_name" \
    --type merge \
    --patch-file "$patch_file" \
    >/dev/null
)

reconcile_secret() (
  set -u

  secret_name=$1

  work_dir="$(mktemp -d)" || {
    log "failed to create temporary working directory for ${secret_name}"
    return 1
  }
  trap 'rm -rf "$work_dir"' EXIT INT TERM

  bootstrap_kubeconfig_file="${work_dir}/bootstrap.kubeconfig"
  current_kubeconfig_file="${work_dir}/current.kubeconfig"
  candidate_kubeconfig_file="${work_dir}/candidate.kubeconfig"
  bootstrap_info_file="${work_dir}/bootstrap-info"
  token_request_file="${work_dir}/token-request"
  credential_patch_file="${work_dir}/credential-patch.json"
  desired_labels_file="${work_dir}/desired-labels"
  current_labels_file="${work_dir}/current-labels"
  labels_json_file="${work_dir}/labels.json"
  labels_patch_file="${work_dir}/labels-patch.json"

  if ! secret_type="$(get_secret_type "$RELEASE_NAMESPACE" "$secret_name")"; then
    log "failed to read type for secret ${secret_name}"
    return 1
  fi

  if [ "$secret_type" != "$REQUIRED_TYPE" ]; then
    if [ -n "$TARGET_SECRET_NAME" ]; then
      log "target secret ${secret_name}: expected secret type ${REQUIRED_TYPE}, found ${secret_type:-<empty>}"
      return 1
    fi

    log "skipping ${secret_name}: expected secret type ${REQUIRED_TYPE}, found ${secret_type:-<empty>}"
    return 0
  fi

  if ! cluster_name="$(get_secret_value "$RELEASE_NAMESPACE" "$secret_name" "name")"; then
    log "failed to read cluster name from secret ${secret_name}"
    return 1
  fi

  if [ -z "$cluster_name" ]; then
    case "$secret_name" in
      *-cluster-secret)
        cluster_name=${secret_name%-cluster-secret}
        ;;
      *)
        cluster_name=$secret_name
        ;;
    esac
  fi

  config_map_name="${cluster_name}${CONFIG_MAP_SUFFIX}"

  if ! get_resource_label_lines "$RELEASE_NAMESPACE" configmap "$config_map_name" "$desired_labels_file"; then
    log "failed to read authoritative labels from configmap ${config_map_name}"
    return 1
  fi

  if ! validate_cluster_config_map "$desired_labels_file" "$config_map_name" "$cluster_name"; then
    return 1
  fi

  if ! agent_namespace="$(get_secret_annotation "$RELEASE_NAMESPACE" "$secret_name" "$AGENT_NAMESPACE_ANNOTATION")"; then
    log "failed to read agent namespace annotation from secret ${secret_name}"
    return 1
  fi

  if [ -z "$agent_namespace" ]; then
    agent_namespace="$DEFAULT_AGENT_NAMESPACE"
  fi

  if ! validate_agent_namespace "$agent_namespace"; then
    log "invalid kubara-agent namespace ${agent_namespace} for ${cluster_name}"
    return 1
  fi

  if ! current_kubeconfig="$(get_secret_value "$RELEASE_NAMESPACE" "$secret_name" "$KUBECONFIG_KEY")"; then
    log "failed to read kubeconfig from secret ${secret_name}"
    return 1
  fi

  # Support migration from legacy config key if kubeconfig key is empty
  legacy_config=""
  if [ -z "$current_kubeconfig" ]; then
    legacy_config="$(get_secret_value "$RELEASE_NAMESPACE" "$secret_name" "config")" || true
  fi

  if ! current_epoch="$(date +%s)"; then
    log "failed to determine current time while reconciling ${secret_name}"
    return 1
  fi

  case "$current_epoch" in
    ''|*[!0-9]*)
      log "current time is not a valid epoch value while reconciling ${secret_name}"
      return 1
      ;;
  esac

  refresh_after_epoch=$((current_epoch + REFRESH_BEFORE_SECONDS))

  issued_at=""
  expires_at=""

  if [ -z "$current_kubeconfig" ] && [ -z "$legacy_config" ]; then
    # FIRST ONBOARDING: bootstrap is used only to establish kubara-agent and mint the first rotating credential.
    log "no credentials found for ${cluster_name}; using bootstrap credentials for initial onboarding"

    if ! bootstrap_kubeconfig="$(get_secret_value "$RELEASE_NAMESPACE" "$secret_name" "$BOOTSTRAP_KUBECONFIG_KEY")"; then
      log "failed to read bootstrap kubeconfig from secret ${secret_name}"
      return 1
    fi

    if [ -z "$bootstrap_kubeconfig" ]; then
      log "secret ${secret_name} is missing required bootstrap key ${BOOTSTRAP_KUBECONFIG_KEY}"
      return 1
    fi

    printf '%s' "$bootstrap_kubeconfig" >"$bootstrap_kubeconfig_file" || return 1

    if ! extract_bootstrap_cluster_info "$bootstrap_kubeconfig_file" "$bootstrap_info_file"; then
      log "failed to extract cluster information from bootstrap kubeconfig for ${cluster_name}"
      return 1
    fi

    server="$(sed -n '1p' "$bootstrap_info_file")"
    ca_data="$(sed -n '2p' "$bootstrap_info_file")"
    insecure="$(sed -n '3p' "$bootstrap_info_file")"

    log "provisioning kubara-agent in namespace ${agent_namespace} for ${cluster_name}"

    if ! ensure_agent_identity "$bootstrap_kubeconfig_file" "$agent_namespace"; then
      log "failed to provision kubara-agent for ${cluster_name}"
      return 1
    fi

    if ! mint_agent_token "$bootstrap_kubeconfig_file" "$agent_namespace" "$token_request_file"; then
      log "failed to mint initial kubara-agent token for ${cluster_name}"
      return 1
    fi

    token="$(sed -n '1p' "$token_request_file")"
    expiration_timestamp="$(sed -n '2p' "$token_request_file")"

    if [ -z "$token" ]; then
      log "token request returned an empty token for ${cluster_name}"
      return 1
    fi

    if ! expires_at="$(rfc3339_to_epoch "$expiration_timestamp")"; then
      log "failed to parse token expiration timestamp for ${cluster_name}: ${expiration_timestamp}"
      return 1
    fi

    issued_at="$(date +%s)" || return 1

    if ! build_kubeconfig \
      "$candidate_kubeconfig_file" \
      "$server" \
      "$ca_data" \
      "$insecure" \
      "$token"; then
      log "failed to build initial kubeconfig for ${cluster_name}"
      return 1
    fi

    if ! validate_kubeconfig "$candidate_kubeconfig_file"; then
      log "initial generated credentials for ${cluster_name} failed validation"
      return 1
    fi

    kubeconfig_content="$(cat "$candidate_kubeconfig_file")" || return 1

    if ! patch_agnostic_secret_with_credentials \
      "$secret_name" \
      "$credential_patch_file" \
      "$cluster_name" \
      "$server" \
      "$kubeconfig_content" \
      "$token" \
      "$ca_data" \
      "$insecure" \
      "$issued_at" \
      "$expires_at"; then
      log "failed to persist initial credentials in secret ${secret_name}"
      return 1
    fi

    if ! sync_secret_labels \
      "$RELEASE_NAMESPACE" \
      "$secret_name" \
      "$desired_labels_file" \
      "$current_labels_file" \
      "$labels_json_file" \
      "$labels_patch_file"; then
      return 1
    fi

    cp "$candidate_kubeconfig_file" "$current_kubeconfig_file" || return 1
    log "successfully onboarded cluster credentials for ${cluster_name}"
  else
    # NORMAL ROTATION
    if ! sync_secret_labels \
      "$RELEASE_NAMESPACE" \
      "$secret_name" \
      "$desired_labels_file" \
      "$current_labels_file" \
      "$labels_json_file" \
      "$labels_patch_file"; then
      return 1
    fi

    if ! server="$(get_secret_value "$RELEASE_NAMESPACE" "$secret_name" "server")"; then
      log "failed to read server endpoint from secret ${secret_name}"
      return 1
    fi

    token="$(get_secret_value "$RELEASE_NAMESPACE" "$secret_name" "token")" || true
    ca_data="$(get_secret_value "$RELEASE_NAMESPACE" "$secret_name" "caData")" || true
    insecure="$(get_secret_value "$RELEASE_NAMESPACE" "$secret_name" "insecure")" || true

    # Migration / reconstruction if reading legacy config
    if [ -n "$legacy_config" ] && [ -z "$current_kubeconfig" ]; then
      token="$(legacy_config_token "$legacy_config")"
      ca_data="$(legacy_config_ca_data "$legacy_config")"
      insecure="$(legacy_config_insecure "$legacy_config")"
      [ -n "$insecure" ] || insecure="false"

      if ! build_kubeconfig \
        "$current_kubeconfig_file" \
        "$server" \
        "$ca_data" \
        "$insecure" \
        "$token"; then
        log "failed to reconstruct kubeconfig from legacy credentials for ${cluster_name}"
        return 1
      fi
    else
      printf '%s' "$current_kubeconfig" >"$current_kubeconfig_file" || return 1
      [ -n "$insecure" ] || insecure="false"
    fi

    if ! validate_kubeconfig "$current_kubeconfig_file"; then
      log "current credentials for ${cluster_name} are invalid; automatic rotation cannot continue without explicit re-onboarding"
      return 1
    fi

    expires_at="$(get_secret_annotation "$RELEASE_NAMESPACE" "$secret_name" "$EXPIRES_AT_ANNOTATION")" || true
    issued_at="$(get_secret_annotation "$RELEASE_NAMESPACE" "$secret_name" "$ISSUED_AT_ANNOTATION")" || true

    if refresh_due "$expires_at" "$refresh_after_epoch"; then
      log "rotating credentials for ${cluster_name} using current kubara-agent credentials"

      if ! mint_agent_token "$current_kubeconfig_file" "$agent_namespace" "$token_request_file"; then
        log "failed to mint replacement kubara-agent token for ${cluster_name}"
        return 1
      fi

      token="$(sed -n '1p' "$token_request_file")"
      expiration_timestamp="$(sed -n '2p' "$token_request_file")"

      if [ -z "$token" ]; then
        log "token request returned an empty token for ${cluster_name}"
        return 1
      fi

      if ! expires_at="$(rfc3339_to_epoch "$expiration_timestamp")"; then
        log "failed to parse token expiration timestamp for ${cluster_name}: ${expiration_timestamp}"
        return 1
      fi

      issued_at="$(date +%s)" || return 1

      if [ "$expires_at" -le "$issued_at" ]; then
        log "token request returned an already-expired credential for ${cluster_name}"
        return 1
      fi

      actual_lifetime=$((expires_at - issued_at))
      if [ "$actual_lifetime" -le "$REFRESH_BEFORE_SECONDS" ]; then
        log "token lifetime returned for ${cluster_name} (${actual_lifetime}s) is not greater than refreshBefore (${REFRESH_BEFORE_SECONDS}s)"
        return 1
      fi

      if ! build_kubeconfig \
        "$candidate_kubeconfig_file" \
        "$server" \
        "$ca_data" \
        "$insecure" \
        "$token"; then
        log "failed to build replacement kubeconfig for ${cluster_name}"
        return 1
      fi

      if ! validate_kubeconfig "$candidate_kubeconfig_file"; then
        log "replacement credentials for ${cluster_name} failed validation"
        return 1
      fi

      kubeconfig_content="$(cat "$candidate_kubeconfig_file")" || return 1

      if ! patch_agnostic_secret_with_credentials \
        "$secret_name" \
        "$credential_patch_file" \
        "$cluster_name" \
        "$server" \
        "$kubeconfig_content" \
        "$token" \
        "$ca_data" \
        "$insecure" \
        "$issued_at" \
        "$expires_at"; then
        log "failed to update rotated credentials in secret ${secret_name}"
        return 1
      fi

      cp "$candidate_kubeconfig_file" "$current_kubeconfig_file" || return 1
      log "successfully rotated credentials for ${cluster_name}"
    else
      log "credentials for ${cluster_name} are valid"
      # If migrating from legacy, persist the canonical kubeconfig key
      if [ -n "$legacy_config" ] && [ -z "$current_kubeconfig" ]; then
        kubeconfig_content="$(cat "$current_kubeconfig_file")" || return 1
        [ -n "$issued_at" ] || issued_at="$(date +%s)"
        patch_agnostic_secret_with_credentials \
          "$secret_name" \
          "$credential_patch_file" \
          "$cluster_name" \
          "$server" \
          "$kubeconfig_content" \
          "$token" \
          "$ca_data" \
          "$insecure" \
          "$issued_at" \
          "$expires_at" || return 1
      fi
    fi
  fi

  # RECONCILE TARGETS (executed on every run for both initial onboarding and periodic runs)
  [ -n "$issued_at" ] || issued_at="$(date +%s)"

  if [ "$TARGET_ARGO_ENABLED" = "true" ]; then
    if ! project_argo_target \
      "$cluster_name" \
      "$server" \
      "$token" \
      "$ca_data" \
      "$insecure" \
      "$desired_labels_file" \
      "$issued_at" \
      "$expires_at"; then
      return 1
    fi
  fi

  if [ "$TARGET_FLUX_ENABLED" = "true" ]; then
    if ! project_flux_target \
      "$cluster_name" \
      "$current_kubeconfig_file" \
      "$desired_labels_file" \
      "$issued_at" \
      "$expires_at"; then
      return 1
    fi
  fi

  return 0
)

if ! TOKEN_DURATION_SECONDS="$(duration_to_seconds "$TOKEN_DURATION")"; then
  log "invalid token duration: ${TOKEN_DURATION}"
  exit 1
fi

if ! REFRESH_BEFORE_SECONDS="$(duration_to_seconds "$REFRESH_BEFORE")"; then
  log "invalid refresh-before duration: ${REFRESH_BEFORE}"
  exit 1
fi

if [ "$TOKEN_DURATION_SECONDS" -le 0 ]; then
  log "token duration must be greater than zero"
  exit 1
fi

if [ "$REFRESH_BEFORE_SECONDS" -lt 0 ]; then
  log "refreshBefore must not be negative"
  exit 1
fi

if [ "$REFRESH_BEFORE_SECONDS" -ge "$TOKEN_DURATION_SECONDS" ]; then
  log "refreshBefore (${REFRESH_BEFORE}) must be smaller than token duration (${TOKEN_DURATION})"
  exit 1
fi

if [ -z "$REQUIRED_TYPE" ]; then
  log "required cluster credential secret type must not be empty"
  exit 1
fi

if [ -n "$TARGET_SECRET_NAME" ]; then
  managed_secrets="$TARGET_SECRET_NAME"
else
  if ! managed_secrets="$(
    kubectl \
      -n "$RELEASE_NAMESPACE" \
      get secrets \
      --field-selector "type=${REQUIRED_TYPE}" \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
  )"; then
    log "failed to list cluster credential secrets in namespace ${RELEASE_NAMESPACE}"
    exit 1
  fi
fi

if [ -z "$managed_secrets" ]; then
  log "no cluster credential secrets found in namespace ${RELEASE_NAMESPACE}"
  exit 0
fi

failure_count=0

for secret_name in $managed_secrets; do
  if ! reconcile_secret "$secret_name"; then
    failure_count=$((failure_count + 1))
  fi
done

if [ "$failure_count" -gt 0 ]; then
  log "${failure_count} secret reconciliation(s) failed"
  exit 1
fi

log "cluster credential rotation completed successfully"
