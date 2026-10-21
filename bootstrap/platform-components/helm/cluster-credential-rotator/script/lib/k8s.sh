#!/bin/sh

get_secret_annotation() (
  namespace=$1
  secret_name=$2
  annotation_key=$3

  open_braces="$(printf '%s%s' '{' '{')"
  close_braces="$(printf '%s%s' '}' '}')"

  template_string="${open_braces} index .metadata.annotations \"${annotation_key}\" ${close_braces}"

  if ! value="$(
    kubectl \
      -n "$namespace" \
      get secret "$secret_name" \
      -o "go-template=${template_string}"
  )"; then
    return 1
  fi

  case "$value" in
    "<no value>"|"<nil>")
      return 0
      ;;
  esac

  printf '%s' "$value"
)

validate_agent_namespace() (
  namespace=$1

  if [ -z "$namespace" ]; then
    return 1
  fi

  if [ "${#namespace}" -gt 63 ]; then
    return 1
  fi

  printf '%s' "$namespace" |
    grep -Eq '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$'
)

get_secret_data() (
  kubectl \
    -n "$1" \
    get secret "$2" \
    -o "jsonpath={.data['$3']}"
)

get_secret_value() (
  encoded_value="$(get_secret_data "$1" "$2" "$3")" || return 1

  if [ -z "$encoded_value" ]; then
    return 0
  fi

  printf '%s' "$encoded_value" | base64 -d
)

get_secret_type() (
  kubectl \
    -n "$1" \
    get secret "$2" \
    -o jsonpath='{.type}'
)

get_resource_label_lines() (
  namespace=$1
  resource_kind=$2
  resource_name=$3
  output_file=$4

  raw_labels_file="$(mktemp)" || return 1
  trap 'rm -f "$raw_labels_file"' EXIT INT TERM

  open_braces="$(printf '%s%s' '{' '{')"
  close_braces="$(printf '%s%s' '}' '}')"
  template_string="${open_braces}range \$key, \$value := .metadata.labels${close_braces}${open_braces}printf \"%s=%s\\n\" \$key \$value${close_braces}${open_braces}end${close_braces}"

  if ! kubectl \
    -n "$namespace" \
    get "$resource_kind" "$resource_name" \
    -o "go-template=${template_string}" \
    >"$raw_labels_file"; then
    return 1
  fi

  sort "$raw_labels_file" >"$output_file"
)

get_label_value() (
  labels_file=$1
  expected_key=$2

  while IFS= read -r line || [ -n "$line" ]; do
    key=${line%%=*}
    if [ "$key" = "$expected_key" ]; then
      printf '%s' "${line#*=}"
      return 0
    fi
  done <"$labels_file"

  return 1
)

validate_cluster_config_map() (
  labels_file=$1
  config_map_name=$2
  expected_cluster_name=$3

  if ! cluster_label="$(get_label_value "$labels_file" "kubara.io/cluster-name")"; then
    log "configmap ${config_map_name} is missing label kubara.io/cluster-name"
    return 1
  fi

  if [ "$cluster_label" != "$expected_cluster_name" ]; then
    log "configmap ${config_map_name} has invalid kubara.io/cluster-name label: ${cluster_label} (expected ${expected_cluster_name})"
    return 1
  fi
)

write_labels_json() (
  labels_file=$1
  output_file=$2
  first=1

  printf '{' >"$output_file" || return 1

  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue

    key=${line%%=*}
    value=${line#*=}

    escaped_key="$(json_escape "$key")" || return 1
    escaped_value="$(json_escape "$value")" || return 1

    if [ "$first" -eq 0 ]; then
      printf ',' >>"$output_file" || return 1
    fi

    printf '"%s":"%s"' "$escaped_key" "$escaped_value" >>"$output_file" || return 1
    first=0
  done <"$labels_file"

  printf '}' >>"$output_file" || return 1
)

sync_secret_labels() (
  namespace=$1
  secret_name=$2
  desired_labels_file=$3
  current_labels_file=$4
  labels_json_file=$5
  labels_patch_file=$6

  if ! get_resource_label_lines "$namespace" secret "$secret_name" "$current_labels_file"; then
    log "failed to read labels from secret ${namespace}/${secret_name}"
    return 1
  fi

  desired_labels="$(cat "$desired_labels_file")" || return 1
  current_labels="$(cat "$current_labels_file")" || return 1

  if [ "$desired_labels" = "$current_labels" ]; then
    return 0
  fi

  if ! write_labels_json "$desired_labels_file" "$labels_json_file"; then
    log "failed to encode desired labels for secret ${namespace}/${secret_name}"
    return 1
  fi

  labels_json="$(cat "$labels_json_file")" || return 1

  cat >"$labels_patch_file" <<EOF_LABEL_PATCH
[
  {
    "op": "add",
    "path": "/metadata/labels",
    "value": ${labels_json}
  }
]
EOF_LABEL_PATCH

  if ! kubectl \
    -n "$namespace" \
    patch secret "$secret_name" \
    --type json \
    --patch-file "$labels_patch_file" \
    >/dev/null; then
    log "failed to replace labels on secret ${namespace}/${secret_name}"
    return 1
  fi

  log "synchronized labels for ${namespace}/${secret_name}"
)
