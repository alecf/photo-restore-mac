#!/bin/bash
# Generates coverage-summary.md with line coverage for the app and RestoreEngine.
set -uo pipefail

# Reads a coverage JSON file and prints the overall line coverage as a
# percentage. Supports both `xcrun xccov view --report --json` output
# (top-level "lineCoverage" fraction) and `llvm-cov export` output
# (data[0].totals.lines.percent).
line_coverage_pct() {
  jq -r 'if has("lineCoverage")
         then .lineCoverage * 100
         else .data[0].totals.lines.percent
         end' "$1"
}

APP_PCT="N/A"
ENGINE_PCT="N/A"

if [ -d TestResults.xcresult ]; then
  APP_JSON=$(mktemp)
  xcrun xccov view --report --json TestResults.xcresult > "$APP_JSON"
  APP_PERCENT=$(line_coverage_pct "$APP_JSON")
  if [ -n "$APP_PERCENT" ] && [ "$APP_PERCENT" != "null" ]; then
    APP_PCT=$(awk "BEGIN { printf \"%.2f%%\", $APP_PERCENT }")
  fi
  rm -f "$APP_JSON"
fi

if [ -d RestoreEngine ]; then
  pushd RestoreEngine > /dev/null

  COV_PATH=$(swift test --show-codecov-path 2>/dev/null)

  if [ -f "$COV_PATH" ]; then
    ENGINE_PERCENT=$(line_coverage_pct "$COV_PATH")
    if [ -n "$ENGINE_PERCENT" ] && [ "$ENGINE_PERCENT" != "null" ]; then
      ENGINE_PCT=$(awk "BEGIN { printf \"%.2f%%\", $ENGINE_PERCENT }")
    fi
  fi

  popd > /dev/null
fi

cat > coverage-summary.md <<EOF
## Test Coverage

| Module | Line Coverage |
| --- | --- |
| PhotoRestore (app) | ${APP_PCT} |
| RestoreEngine | ${ENGINE_PCT} |
EOF

cat coverage-summary.md
