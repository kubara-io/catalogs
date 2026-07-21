#!/usr/bin/env bash
set -uo pipefail

# Validate the catalog's Helm source without generated kubara values. Both
# catalogs are merged into one temporary component tree because general charts
# can reference the bootstrap template library through file:// dependencies.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${CATALOG_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
KUBE_VERSION="${KUBE_VERSION:-1.35.0}"
WORK_DIR="$(mktemp -d)"
CHART_ROOT="$WORK_DIR/platform-components/helm"
FAILED=()

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$CHART_ROOT"
for catalog in bootstrap general; do
  source_dir="$REPO_ROOT/$catalog/platform-components/helm"
  [[ -d $source_dir ]] || continue
  cp -R "$source_dir/." "$CHART_ROOT/"
done

while IFS= read -r chart_file; do
  chart_dir="$(dirname "$chart_file")"
  chart="$(basename "$chart_dir")"

  echo "::group::Helm chart: $chart"
  if ! helm dependency update "$chart_dir"; then
    echo "::error file=$chart_file::helm dependency update failed"
    FAILED+=("$chart:dependency-update")
    echo "::endgroup::"
    continue
  fi

  chart_type="$(awk '$1 == "type:" { print $2; exit }' "$chart_file")"
  if [[ $chart_type == library ]]; then
    echo "Library chart: dependency validation complete"
    echo "::endgroup::"
    continue
  fi

  if ! helm lint --quiet --kube-version "$KUBE_VERSION" "$chart_dir"; then
    echo "::error file=$chart_file::helm lint failed"
    FAILED+=("$chart:lint")
  fi

  echo "::endgroup::"
done < <(find "$CHART_ROOT" -mindepth 2 -maxdepth 2 -name Chart.yaml -type f | sort)

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "::error::Helm checks failed: ${FAILED[*]}"
  exit 1
fi

echo "All Helm source checks passed."

