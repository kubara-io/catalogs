#!/usr/bin/env bash
set -uo pipefail

# Validate checked-in Terraform modules in isolated temporary directories so
# provider downloads and lock files never modify the catalog source tree.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${CATALOG_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
WORK_DIR="$(mktemp -d)"
FAILED=()

export TF_PLUGIN_CACHE_DIR="$WORK_DIR/plugin-cache"
mkdir -p "$TF_PLUGIN_CACHE_DIR"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

record_failure() {
  FAILED+=("$1:$2")
}

if ! terraform fmt -check -recursive "$REPO_ROOT/bootstrap" "$REPO_ROOT/general"; then
  record_failure catalog terraform-fmt
fi

module_index=0
while IFS= read -r module_dir; do
  module_index=$((module_index + 1))
  module_name="${module_dir#"$REPO_ROOT/"}"
  check_dir="$WORK_DIR/module-$module_index"
  cp -R "$module_dir" "$check_dir"

  echo "::group::Terraform module: $module_name"
  if ! terraform -chdir="$check_dir" init -backend=false -input=false; then
    echo "::error file=$module_dir::terraform init failed"
    record_failure "$module_name" terraform-init
    echo "::endgroup::"
    continue
  fi

  if grep -RqE 'configuration_aliases[[:space:]]*=' "$check_dir"; then
    echo "Skipping standalone validate: module requires a provider alias from its caller"
  elif ! terraform -chdir="$check_dir" validate; then
    echo "::error file=$module_dir::terraform validate failed"
    record_failure "$module_name" terraform-validate
  fi

  if ! tflint --chdir="$check_dir"; then
    echo "::error file=$module_dir::tflint failed"
    record_failure "$module_name" tflint
  fi
  echo "::endgroup::"
done < <(
  find "$REPO_ROOT/bootstrap" "$REPO_ROOT/general" -type f -name '*.tf' -print0 \
    | xargs -0 -n1 dirname \
    | sort -u
)

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "::error::Terraform checks failed: ${FAILED[*]}"
  exit 1
fi

echo "All Terraform source checks passed."

