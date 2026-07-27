#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <packageFileDir> <bumpType>" >&2
  exit 1
fi

PACKAGE_DIR=$1
BUMP_TYPE=$2

bump_version() {
  local ver=$1
  local type=$2
  IFS='.' read -r major minor patch <<<"$ver"
  case "$type" in
    patch)
      patch=$((patch+1))
      ;;
    minor)
      minor=$((minor+1))
      patch=0
      ;;
    major)
      major=$((major+1))
      minor=0
      patch=0
      ;;
    *)
      echo "Unknown bump type: $type" >&2
      exit 1
      ;;
  esac
  echo "$major.$minor.$patch"
}

severity_rank() {
  case "$1" in
    patch) echo 0 ;;
    minor) echo 1 ;;
    major) echo 2 ;;
    *)
      echo "Unknown bump type: $1" >&2
      exit 1
      ;;
  esac
}

catalog_root=${PACKAGE_DIR%%/*}
case "$catalog_root" in
  bootstrap|general)
    ;;
  *)
    echo "Error: unsupported catalog root '$catalog_root' for package dir '$PACKAGE_DIR'." >&2
    exit 1
    ;;
esac

catalog_file="$catalog_root/Catalog.yaml"
if [ ! -f "$catalog_file" ]; then
  echo "Error: Catalog file '$catalog_file' not found." >&2
  exit 1
fi

branch_name=$(git rev-parse --abbrev-ref HEAD | tr '/:' '__')
state_dir=".git/renovate-catalog-version-state/$branch_name"
mkdir -p "$state_dir"

base_file="$state_dir/${catalog_root}.base"
bump_file="$state_dir/${catalog_root}.bump"
current_catalog_version=$(awk '
  $1 == "spec:" { in_spec = 1; next }
  in_spec && $1 == "version:" { print $2; exit }
' "$catalog_file")

if [ -z "$current_catalog_version" ]; then
  echo "Error: unable to read catalog version from '$catalog_file'." >&2
  exit 1
fi

if [ ! -f "$base_file" ]; then
  printf '%s\n' "$current_catalog_version" > "$base_file"
fi

if [ -f "$bump_file" ] && [ "$(severity_rank "$(cat "$bump_file")")" -gt "$(severity_rank "$BUMP_TYPE")" ]; then
  highest_bump=$(cat "$bump_file")
else
  highest_bump=$BUMP_TYPE
fi
printf '%s\n' "$highest_bump" > "$bump_file"

new_catalog_version=$(bump_version "$(cat "$base_file")" "$highest_bump")
awk -v ver="$new_catalog_version" '
  $1 == "spec:" { in_spec = 1; print; next }
  in_spec && $1 == "version:" && !updated {
    print "  version: " ver
    updated = 1
    next
  }
  { print }
  END {
    if (!updated) {
      exit 1
    }
  }
' "$catalog_file" > "$catalog_file".new && mv "$catalog_file".new "$catalog_file"
