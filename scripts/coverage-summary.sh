#!/bin/bash
# Generates coverage-summary.md with line coverage for the app and RestoreEngine.
set -uo pipefail

APP_PCT="N/A"
ENGINE_PCT="N/A"

if [ -d TestResults.xcresult ]; then
  APP_COVERAGE=$(xcrun xccov view --report --json TestResults.xcresult | jq -r '.lineCoverage')
  if [ -n "$APP_COVERAGE" ] && [ "$APP_COVERAGE" != "null" ]; then
    APP_PCT=$(awk "BEGIN { printf \"%.2f%%\", $APP_COVERAGE * 100 }")
  fi
fi

if [ -d RestoreEngine ]; then
  pushd RestoreEngine > /dev/null

  COV_PATH=$(swift test --show-codecov-path 2>/dev/null)

  if [ -f "$COV_PATH" ]; then
    ENGINE_PERCENT=$(jq -r '.data[0].totals.lines.percent' "$COV_PATH")
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
