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

  BIN_PATH=$(swift build --show-bin-path 2>/dev/null)
  PROF_PATH=$(swift test --show-codecov-path 2>/dev/null)
  TEST_BINARY="$BIN_PATH/RestoreEnginePackageTests.xctest/Contents/MacOS/RestoreEnginePackageTests"

  if [ -f "$TEST_BINARY" ] && [ -f "$PROF_PATH" ]; then
    ENGINE_REPORT=$(xcrun llvm-cov report "$TEST_BINARY" -instr-profile "$PROF_PATH" -ignore-filename-regex='\.build|/Tests/')
    LINE=$(echo "$ENGINE_REPORT" | grep '^TOTAL')
    if [ -n "$LINE" ]; then
      ENGINE_PCT=$(echo "$LINE" | awk '{print $NF}')
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
