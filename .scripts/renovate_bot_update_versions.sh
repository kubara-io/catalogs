#!/usr/bin/env bash
set -euo pipefail

DATA_FILE=${RENOVATE_POST_UPGRADE_COMMAND_DATA_FILE:-}

die() {
  echo "Error: $*" >&2
  exit 1
}

[ -n "$DATA_FILE" ] && [ -f "$DATA_FILE" ] ||
  die "RENOVATE_POST_UPGRADE_COMMAND_DATA_FILE is missing or does not point to a file."
command -v jq >/dev/null || die "jq is required to process Renovate upgrades."

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
NORMALIZED_UPGRADES="$TEMP_DIR/upgrades.json"

# Keep only the fields needed below and assign a SemVer severity. Renovate's
# non-major/minor update types (patch, digest, pin, etc.) are patch bumps.
if ! jq -e '
  if type != "array" or length == 0 then
    error("expected a non-empty upgrades array")
  else
    map(
      (.packageFileDir // (.packageFile | split("/") | .[0:-1] | join("/"))) as $dir
      | {
          dir: $dir,
          catalog: ($dir | split("/")[0]),
          depName,
          oldVersion: (.currentVersion // .currentValue),
          newVersion: (.newVersion // .newValue),
          updateType,
          rank: (if .updateType == "major" then 3 elif .updateType == "minor" then 2 else 1 end)
        }
    )
    | if all(.[];
        (.dir | type == "string" and length > 0)
        and (.catalog == "bootstrap" or .catalog == "general")
        and (.depName | type == "string" and length > 0)
        and (.oldVersion | type == "string" and length > 0)
        and (.newVersion | type == "string" and length > 0)
        and (.updateType | type == "string" and length > 0)
      ) then . else error("upgrade is missing a required field or has an unsupported catalog") end
  end
' "$DATA_FILE" > "$NORMALIZED_UPGRADES"; then
  die "unable to parse or validate Renovate upgrades data in '$DATA_FILE'."
fi

bump_version() {
  local version=$1
  local rank=$2
  local major minor patch

  [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    die "version '$version' is not a plain semantic version"
  IFS=. read -r major minor patch <<EOF
$version
EOF

  case "$rank" in
    3) printf '%s.0.0\n' "$((major + 1))" ;;
    2) printf '%s.%s.0\n' "$major" "$((minor + 1))" ;;
    1) printf '%s.%s.%s\n' "$major" "$minor" "$((patch + 1))" ;;
    *) die "invalid severity rank '$rank'" ;;
  esac
}

head_chart_version() {
  git show "HEAD:$1" | awk '
    /^version:[[:space:]]/ { version = $2; count++ }
    END { if (count == 1) print version; else exit 1 }
  ' || die "unable to read exactly one top-level version from HEAD:$1"
}

head_catalog_version() {
  git show "HEAD:$1" | awk '
    /^spec:[[:space:]]*$/ { in_spec = 1; next }
    in_spec && /^[^[:space:]]/ { in_spec = 0 }
    in_spec && /^  version:[[:space:]]/ { version = $2; count++ }
    END { if (count == 1) print version; else exit 1 }
  ' || die "unable to read exactly one spec.version from HEAD:$1"
}

set_chart_version() {
  local file=$1 version=$2 output="$TEMP_DIR/chart.yaml"
  awk -v version="$version" '
    /^version:[[:space:]]/ { print "version: " version; count++; next }
    { print }
    END { if (count != 1) exit 1 }
  ' "$file" > "$output" || die "unable to update exactly one version in '$file'"
  mv "$output" "$file"
}

set_catalog_version() {
  local file=$1 version=$2 output="$TEMP_DIR/catalog.yaml"
  awk -v version="$version" '
    /^spec:[[:space:]]*$/ { in_spec = 1; print; next }
    in_spec && /^[^[:space:]]/ { in_spec = 0 }
    in_spec && /^  version:[[:space:]]/ {
      print "  version: " version; count++; next
    }
    { print }
    END { if (count != 1) exit 1 }
  ' "$file" > "$output" || die "unable to update exactly one spec.version in '$file'"
  mv "$output" "$file"
}

update_changelog() {
  local file=$1 version=$2 group_json=$3
  local base="$TEMP_DIR/changelog.md" bullets="$TEMP_DIR/bullets.txt"
  local output="$TEMP_DIR/changelog-new.md" heading_count

  if git cat-file -e "HEAD:$file" 2>/dev/null; then
    git show "HEAD:$file" > "$base"
  else
    printf '%s\n' \
      '# Changelog' \
      'All notable changes to this chart will be documented in this file.' \
      '' \
      'The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),' \
      'and this chart adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).' \
      '' > "$base"
  fi

  printf '%s' "$group_json" | jq -r '
    sort_by(.depName, .oldVersion, .newVersion)
    | unique_by([.depName, .oldVersion, .newVersion])[]
    | "- Updated chart dependency version: \(.depName) \(.oldVersion) → \(.newVersion)"
  ' > "$bullets"

  heading_count=$(grep -Ec "^## \\[$(printf '%s' "$version" | sed 's/\./\\./g')\\]( - .*)?$" "$base" || true)
  [ "$heading_count" -le 1 ] || die "changelog '$file' contains multiple headings for version $version"

  if [ "$heading_count" -eq 1 ]; then
    awk -v heading="## [$version]" '
      NR == FNR { bullets[++bullet_count] = $0; next }
      index($0, heading) == 1 && !found {
        print; found = 1; target = 1; next
      }
      target {
        if ($0 == "### Changed") {
          print
          for (i = 1; i <= bullet_count; i++) print bullets[i]
          target = 0
          next
        }
        print "### Changed"
        for (i = 1; i <= bullet_count; i++) print bullets[i]
        target = 0
      }
      { print }
      END {
        if (target) {
          print "### Changed"
          for (i = 1; i <= bullet_count; i++) print bullets[i]
        }
      }
    ' "$bullets" "$base" > "$output"
  else
    awk -v version="$version" -v today="$(date +%F)" '
      NR == FNR { bullets[++bullet_count] = $0; next }
      function block() {
        print "## [" version "] - " today
        print "### Changed"
        for (i = 1; i <= bullet_count; i++) print bullets[i]
        print ""
      }
      !inserted && /^## \[/ { block(); inserted = 1 }
      { print }
      END { if (!inserted) block() }
    ' "$bullets" "$base" > "$output"
  fi
  mv "$output" "$file"
}

# Each directory containing a Chart.yaml gets one bump and one changelog block.
jq -r 'sort_by(.dir) | group_by(.dir)[] | @base64' "$NORMALIZED_UPGRADES" |
while IFS= read -r encoded_group; do
  group_json=$(printf '%s' "$encoded_group" | base64 --decode)
  chart_dir=$(printf '%s' "$group_json" | jq -r '.[0].dir')
  chart_file="$chart_dir/Chart.yaml"
  [ -f "$chart_file" ] || continue

  rank=$(printf '%s' "$group_json" | jq '[.[].rank] | max')
  old_version=$(head_chart_version "$chart_file")
  new_version=$(bump_version "$old_version" "$rank")
  set_chart_version "$chart_file" "$new_version"
  update_changelog "$chart_dir/CHANGELOG.md" "$new_version" "$group_json"
  echo "Updated $chart_file: $old_version → $new_version"
done

# The highest severity across every update in a catalog determines one bump.
jq -r 'sort_by(.catalog) | group_by(.catalog)[] | @base64' "$NORMALIZED_UPGRADES" |
while IFS= read -r encoded_group; do
  group_json=$(printf '%s' "$encoded_group" | base64 --decode)
  catalog=$(printf '%s' "$group_json" | jq -r '.[0].catalog')
  catalog_file="$catalog/Catalog.yaml"
  [ -f "$catalog_file" ] || die "catalog file '$catalog_file' does not exist"

  rank=$(printf '%s' "$group_json" | jq '[.[].rank] | max')
  old_version=$(head_catalog_version "$catalog_file")
  new_version=$(bump_version "$old_version" "$rank")
  set_catalog_version "$catalog_file" "$new_version"
  echo "Updated $catalog_file: $old_version → $new_version"
done
