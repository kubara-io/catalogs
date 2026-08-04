#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$SCRIPT_DIR/renovate_bot_update_versions.sh"
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p \
  "$FIXTURE/bootstrap/platform-components/helm/alpha" \
  "$FIXTURE/bootstrap/platform-components/helm/beta"

printf '%s\n' \
  'apiVersion: kubara.io/v1alpha1' \
  'kind: Catalog' \
  'spec:' \
  '  version: 1.0.0' > "$FIXTURE/bootstrap/Catalog.yaml"
printf '%s\n' 'apiVersion: v2' 'name: alpha' 'version: 1.2.3' > \
  "$FIXTURE/bootstrap/platform-components/helm/alpha/Chart.yaml"
printf '%s\n' '# Changelog' '' '## [1.2.3] - 2026-01-01' '### Changed' '- Previous change' > \
  "$FIXTURE/bootstrap/platform-components/helm/alpha/CHANGELOG.md"
printf '%s\n' 'apiVersion: v2' 'name: beta' 'version: 2.0.0' > \
  "$FIXTURE/bootstrap/platform-components/helm/beta/Chart.yaml"
printf '%s\n' '# Changelog' '' '## [2.0.0] - 2026-01-01' '### Changed' '- Previous change' > \
  "$FIXTURE/bootstrap/platform-components/helm/beta/CHANGELOG.md"

git -C "$FIXTURE" init -q
git -C "$FIXTURE" add .
git -C "$FIXTURE" -c user.name='Renovate Test' -c user.email='test@example.invalid' \
  commit -qm 'test fixture'

printf '%s\n' '[
  {"depName":"alpha-one","currentVersion":"1.0.0","newVersion":"1.0.1","packageFileDir":"bootstrap/platform-components/helm/alpha","updateType":"patch"},
  {"depName":"alpha-two","currentVersion":"2.0.0","newVersion":"2.0.1","packageFileDir":"bootstrap/platform-components/helm/alpha","updateType":"patch"},
  {"depName":"beta-minor","currentVersion":"3.1.0","newVersion":"3.2.0","packageFileDir":"bootstrap/platform-components/helm/beta","updateType":"minor"},
  {"depName":"beta-patch","currentVersion":"4.0.0","newVersion":"4.0.1","packageFileDir":"bootstrap/platform-components/helm/beta","updateType":"patch"},
  {"depName":"config-image","currentVersion":"5.0.0","newVersion":"5.0.1","packageFileDir":"bootstrap/platform-configs/helm/config","updateType":"patch"}
]' > "$FIXTURE/helm-upgrades.json"

echo 'helm aggregation:'
(
  cd "$FIXTURE"
  RENOVATE_POST_UPGRADE_COMMAND_DATA_FILE="$FIXTURE/helm-upgrades.json" "$SCRIPT"
)
grep -q '^version: 1.2.4$' "$FIXTURE/bootstrap/platform-components/helm/alpha/Chart.yaml"
grep -q '^version: 2.1.0$' "$FIXTURE/bootstrap/platform-components/helm/beta/Chart.yaml"
grep -q '^  version: 1.1.0$' "$FIXTURE/bootstrap/Catalog.yaml"
[ "$(grep -c '^## \[1.2.4\]' "$FIXTURE/bootstrap/platform-components/helm/alpha/CHANGELOG.md")" -eq 1 ]
[ "$(grep -c 'alpha-one 1.0.0 → 1.0.1' "$FIXTURE/bootstrap/platform-components/helm/alpha/CHANGELOG.md")" -eq 1 ]
[ "$(grep -c 'alpha-two 2.0.0 → 2.0.1' "$FIXTURE/bootstrap/platform-components/helm/alpha/CHANGELOG.md")" -eq 1 ]
[ "$(grep -c '^## \[2.1.0\]' "$FIXTURE/bootstrap/platform-components/helm/beta/CHANGELOG.md")" -eq 1 ]
[ "$(grep -c 'beta-minor 3.1.0 → 3.2.0' "$FIXTURE/bootstrap/platform-components/helm/beta/CHANGELOG.md")" -eq 1 ]
[ "$(grep -c 'beta-patch 4.0.0 → 4.0.1' "$FIXTURE/bootstrap/platform-components/helm/beta/CHANGELOG.md")" -eq 1 ]

first_diff=$(git -C "$FIXTURE" diff)
echo 'idempotent rerun:'
(
  cd "$FIXTURE"
  RENOVATE_POST_UPGRADE_COMMAND_DATA_FILE="$FIXTURE/helm-upgrades.json" "$SCRIPT"
)
[ "$(git -C "$FIXTURE" diff)" = "$first_diff" ]

git -C "$FIXTURE" restore .
printf '%s\n' '[
  {"depName":"hashicorp/example","currentVersion":"1.0.0","newVersion":"1.0.1","packageFileDir":"bootstrap/terraform","updateType":"patch"}
]' > "$FIXTURE/terraform-upgrades.json"
echo 'independent terraform aggregation after helm aggregation:'
(
  cd "$FIXTURE"
  RENOVATE_POST_UPGRADE_COMMAND_DATA_FILE="$FIXTURE/terraform-upgrades.json" "$SCRIPT"
)
grep -q '^  version: 1.0.1$' "$FIXTURE/bootstrap/Catalog.yaml"

printf '%s\n' 'not json' > "$FIXTURE/invalid.json"
if (cd "$FIXTURE" && RENOVATE_POST_UPGRADE_COMMAND_DATA_FILE="$FIXTURE/invalid.json" "$SCRIPT") 2>/dev/null; then
  echo 'Expected invalid JSON to fail.' >&2
  exit 1
fi
if (cd "$FIXTURE" && RENOVATE_POST_UPGRADE_COMMAND_DATA_FILE='' "$SCRIPT") 2>/dev/null; then
  echo 'Expected a missing data file to fail.' >&2
  exit 1
fi

echo 'PASS: all synthetic Renovate aggregation tests passed'
