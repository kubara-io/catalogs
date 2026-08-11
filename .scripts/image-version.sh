#!/usr/bin/env bash


# pipefail that pipes break
set -euo pipefail

export PATH="$HOME/.local/bin/:$PATH"

MANAGED="${MANAGED:-${PWD}/platform-components/helm}"
CONFIG_FILE="${CONFIG_FILE:-config.yaml}"

[[ -f "$CONFIG_FILE" ]] || { echo "::error::Missing $CONFIG_FILE — run 'kubara generate' first (or cd into its output)"; exit 1; }

CLUSTER_NAME="$(yq -r '.clusters[0].name' "$CONFIG_FILE")"
CONFIGS="${CONFIGS:-platform-configs/${CLUSTER_NAME}/helm}"
IMAGE_OUTPUT_FILE="${IMAGE_OUTPUT_FILE:-}"
HELM_CHART_VERSION_FILE="${HELM_CHART_VERSION_FILE:-}"

CATALOG_ROOT="${CATALOG_ROOT:?CATALOG_ROOT must point at the catalog source tree}"
CATALOG_HELM="$CATALOG_ROOT/platform-components/helm"
[[ -d "$CATALOG_HELM" ]] || { echo "::error::No charts under $CATALOG_HELM"; exit 1; }

[[ -d "$MANAGED" ]]     || { echo "::error::Missing $MANAGED — run 'kubara generate' first"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "::error::helm not found on PATH"; exit 1; }
command -v yq   >/dev/null 2>&1 || { echo "::error::yq not found on PATH"; exit 1; }

KUBE_VERSION=$(yq -r '.clusters[0].terraform.kubernetesVersion' "$CONFIG_FILE")

PROMETHEUS_STATUS="$(yq -r '.clusters[0].services."kube-prometheus-stack".status // "disabled"' "$CONFIG_FILE")"

# helm template flags advertise the monitoring API only when
# kube-prometheus-stack is enabled, since some charts (eg. traefik) render
# ServiceMonitors guarded by a `fail` on monitoring.coreos.com/v1.
HELM_TEMPLATE_ARGS=(--kube-version "$KUBE_VERSION" --include-crds)
if [[ "$PROMETHEUS_STATUS" == enabled ]]; then
  HELM_TEMPLATE_ARGS+=(--api-versions "monitoring.coreos.com/v1")
fi


echo "Rendering charts from $MANAGED (kube-version=$KUBE_VERSION)" >&2


render_dir="$(mktemp -d)"; trap 'rm -rf "$render_dir"' EXIT
FAILED=()

kept=()
for chart_path in "$MANAGED"/*/; do
    chart=$(basename "$chart_path")
    # only look at the relevant catalog
    [[ -d "$CATALOG_HELM/$chart" ]] || continue

    [[ -f "$chart_path/Chart.yaml" ]] || continue
    kept+=("$chart_path")

    # Don't render library charts
    [[ "$(yq '.type // "application"' "$chart_path/Chart.yaml")" == library ]] && continue

    echo "Updating dependency for ${chart_path}" >&2

    if ! dep_out=$(helm dependency update "$chart_path" 2>&1 >/dev/null ); then
        echo "::error::helm dependency update failed for '$chart_path'"; echo "$dep_out" >&2
        FAILED+=("$chart:dependency-update"); continue
    fi

    values_file="$CONFIGS/$chart/values.generated.yaml"
    helm_args=("${HELM_TEMPLATE_ARGS[@]}" "$chart" "$chart_path")
    [[ ! -f "$values_file" ]] || helm_args+=(-f "$values_file")

    if ! helm template "${helm_args[@]}" \
            > "$render_dir/$chart.yaml" 2> "$render_dir/$chart.err"; then
        echo "::error::helm template for '$chart':"
        sed 's/^/    /' "$render_dir/$chart.err" >&2
        FAILED+=("$chart:template"); continue
    fi
done

# Note! This script does capture normal, init and sidecar containers, but by design
# misses out on runtime-injected images (e.g through webhooks, Kyverno etc.)
# and images refs passed via environment, this does not represent an exhaustive list of images
# captured
IMAGES="$(
  shopt -s nullglob
  rendered_files=("$render_dir"/*.yaml)
  if ((${#rendered_files[@]})); then
    cat "${rendered_files[@]}" |
      { grep -E '^[[:space:]]*image:' || true; } |
      sed -E "s/^[[:space:]]*image:[[:space:]]*//; s/[\"']//g" |
      { grep -vE '[*!]' || true; } |
      { grep -vE '^[[:space:]]*$' || true; } |
      sort -u
  fi
)"

echo "Done Rendering!"


# Incomplete rendering would produce an incomplete inventory, so fail the job.
if ((${#FAILED[@]})); then
    echo "::error::Errors during templating:"
    for err in "${FAILED[@]}"; do
        echo "- $err"
    done
    exit 1
fi


echo "$IMAGES"

### Helm dependency part
echo "Extracting Helm Dependencies"
HELM_CHART_VERSIONS="$(
  for chart_path in "${kept[@]}"; do
    yq '.dependencies[] | select(.name != "template-library") | .name + ": " + .version' \
      "$chart_path/Chart.yaml"
  done | sort -u
)"
echo "$HELM_CHART_VERSIONS"

if [[ -n "$IMAGES" && -n "$IMAGE_OUTPUT_FILE" ]]; then
    echo "$IMAGES" > "$IMAGE_OUTPUT_FILE"
    echo "::notice::Image list written to $IMAGE_OUTPUT_FILE"
elif [[ -z "$IMAGES" ]]; then
    echo "::warning::No image references found"
fi

if [[ -n "$HELM_CHART_VERSIONS" && -n "$HELM_CHART_VERSION_FILE" ]]; then
    echo "$HELM_CHART_VERSIONS" > "$HELM_CHART_VERSION_FILE"
    echo "::notice::Helm chart version list written to $HELM_CHART_VERSION_FILE"
elif [[ -z "$HELM_CHART_VERSIONS" ]]; then
    echo "::warning::No Helm chart dependencies found"
fi
