#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 5 ]; then
  echo "Usage: $0 <depName> <currentVersion> <newVersion> <packageFileDir> <bumpType>"
  exit 1
fi

DEP_NAME=$1
DEP_OLD=$2
DEP_NEW=$3
CHART_DIR=$4
BUMP_TYPE=$5

CHART_FILE="$CHART_DIR/Chart.yaml"
CHANGELOG="$CHART_DIR/CHANGELOG.md"

if [ ! -f "$CHART_FILE" ]; then
  echo "Error: Chart file '$CHART_FILE' not found."
  exit 1
fi

bump_version() {
  local ver=$1
  local type=$2
  IFS='.' read -r major minor patch <<<"$ver"
  case "$type" in
    patch) patch=$((patch + 1)) ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    major) major=$((major + 1)); minor=0; patch=0 ;;
    *) echo "Unknown bump type: $type" >&2; exit 1 ;;
  esac
  echo "$major.$minor.$patch"
}

OLD_CHART_VERSION=$(grep '^version:' "$CHART_FILE" | head -n1 | awk '{print $2}')
NEW_CHART_VERSION=$(bump_version "$OLD_CHART_VERSION" "$BUMP_TYPE")
TODAY=$(date +%F)

if [ ! -f "$CHANGELOG" ]; then
  cat > "$CHANGELOG" <<'EOF'
# Changelog
All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this chart adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

EOF
fi

HEADING="## [$NEW_CHART_VERSION] - $TODAY"
BULLET="- Updated chart dependency version: $DEP_NAME $DEP_OLD → $DEP_NEW"

# Grouped runs invoke this task once per update (executionMode "update"). When a
# chart receives several updates in one branch, gather every bullet under a
# single "## [version] - date" heading instead of emitting one heading per
# update, and never write the same bullet twice (idempotent on re-runs).
awk -v heading="$HEADING" -v bullet="$BULLET" '
  { L[++n] = $0 }
  END {
    h = 0
    for (i = 1; i <= n; i++) if (L[i] == heading) { h = i; break }

    if (h > 0) {
      # Bullet already recorded under this heading? Then emit unchanged.
      for (i = h + 1; i <= n; i++) {
        if (L[i] ~ /^## \[/) break
        if (L[i] == bullet) { for (j = 1; j <= n; j++) print L[j]; exit }
      }
      for (i = 1; i <= n; i++) {
        print L[i]
        if (i == h && !(i + 1 <= n && L[i + 1] == "### Changed")) {
          print "### Changed"; print bullet
        } else if (i == h + 1 && L[i] == "### Changed") {
          print bullet
        }
      }
      exit
    }

    # No heading for this version yet: insert a fresh block before the first
    # existing version heading, or append it if there is none.
    placed = 0
    for (i = 1; i <= n; i++) {
      if (!placed && L[i] ~ /^## \[/) {
        print heading; print "### Changed"; print bullet; print ""
        placed = 1
      }
      print L[i]
    }
    if (!placed) { print heading; print "### Changed"; print bullet }
  }
' "$CHANGELOG" > "$CHANGELOG.new" && mv "$CHANGELOG.new" "$CHANGELOG"

./.scripts/renovate_bot_update_catalog_version.sh "$CHART_DIR" "$BUMP_TYPE"
