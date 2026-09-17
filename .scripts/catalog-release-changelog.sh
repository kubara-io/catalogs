#!/usr/bin/env bash

set -euo pipefail

die() { printf 'x %s\n' "$*" >&2; exit 1; }

catalog="${1:-}"
current_ref="${2:-}"
previous_ref="${3:-}"
repository="${GITHUB_REPOSITORY:-kubara-io/catalogs}"

[[ -n "$catalog" && -n "$current_ref" ]] || {
  die "Usage: .scripts/catalog-release-changelog.sh <catalog> <current-ref> [previous-ref]"
}

[[ -d "$catalog" ]] || die "catalog directory not found: $catalog"

git rev-parse -q --verify "${current_ref}^{commit}" >/dev/null ||
  die "current ref not found: $current_ref"

if [[ -n "$previous_ref" ]]; then
  git rev-parse -q --verify "${previous_ref}^{commit}" >/dev/null ||
    die "previous ref not found: $previous_ref"

  range="${previous_ref}..${current_ref}"
else
  range="$current_ref"
fi

breaking=""
features=""
fixes=""
dependencies=""
documentation=""
ci_build=""
other=""

breaking_re='^[a-z]+(\([^)]+\))?!:'
feature_re='^feat(\([^)]+\))?:'
fix_re='^fix(\([^)]+\))?:'
dependency_re='^[a-z]+\(deps[^)]*\)!?:|^deps(\([^)]+\))?!?:|^bump[[:space:]]'
docs_re='^docs(\([^)]+\))?!?:'
ci_build_re='^(build|ci)(\([^)]+\))?!?:'

format_entry() {
  local subject="$1"
  local pr_number="" author=""

  if [[ "$subject" =~ \(\#([0-9]+)\)$ ]]; then
    pr_number="${BASH_REMATCH[1]}"
  fi

  if [[ -n "$pr_number" && -n "${GH_TOKEN:-}" ]] &&
    command -v gh >/dev/null 2>&1; then
    if author="$(
      gh pr view "$pr_number" \
        --repo "$repository" \
        --json author \
        --jq '.author.login // empty' \
        2>/dev/null
    )" && [[ -n "$author" ]]; then
      printf '* %s by @%s\n' "$subject" "$author"
      return
    fi
  fi

  printf '* %s\n' "$subject"
}

while IFS=$'\t' read -r commit subject; do
  [[ -n "$commit" ]] || continue

  # Release automation creates this commit and points the catalog tags at it.
  # It is release bookkeeping rather than a user-facing catalog change.
  if [[ "$subject" =~ ^chore\(release\): ]]; then
    continue
  fi

  body="$(git show -s --format=%B "$commit")"
  entry="$(format_entry "$subject")"

  if [[ "$subject" =~ $breaking_re ]] ||
    grep -Eq '^BREAKING([ -])CHANGE:' <<< "$body"; then
    breaking+="${entry}"$'\n'
  elif [[ "$subject" =~ $feature_re ]]; then
    features+="${entry}"$'\n'
  elif [[ "$subject" =~ $fix_re ]]; then
    fixes+="${entry}"$'\n'
  elif [[ "$subject" =~ $dependency_re ]]; then
    dependencies+="${entry}"$'\n'
  elif [[ "$subject" =~ $docs_re ]]; then
    documentation+="${entry}"$'\n'
  elif [[ "$subject" =~ $ci_build_re ]]; then
    ci_build+="${entry}"$'\n'
  else
    other+="${entry}"$'\n'
  fi
done < <(
  git log \
    --no-merges \
    --reverse \
    --format='%H%x09%s' \
    "$range" \
    -- "$catalog/"
)

print_section() {
  local title="$1"
  local entries="$2"

  [[ -n "$entries" ]] || return 0

  printf '#### %s\n\n' "$title"
  printf '%s' "$entries"
  printf '\n'
}

print_section "Breaking changes" "$breaking"
print_section "Features" "$features"
print_section "Fixes" "$fixes"
print_section "Dependencies" "$dependencies"
print_section "Documentation" "$documentation"
print_section "CI / Build" "$ci_build"
print_section "Other changes" "$other"
