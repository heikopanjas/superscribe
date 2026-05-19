#!/usr/bin/env bash
# Measure SuperscribeKit line + region coverage; fail if below COVERAGE_MIN (default 100).
#
# Usage:
#   _scripts/coverage.sh              # report only (uses existing profdata)
#   _scripts/coverage.sh --run-tests  # swift test --enable-code-coverage first
#
# Baseline (2026-05-19): SuperscribeKit line coverage 43.32% (1715/3026 lines).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

COVERAGE_MIN="${COVERAGE_MIN:-100}"
BUILD_DIR="${BUILD_DIR:-.build/arm64-apple-macosx/debug}"
PROFILE="${BUILD_DIR}/codecov/default.profdata"
BINARY="${BUILD_DIR}/superscribePackageTests.xctest/Contents/MacOS/superscribePackageTests"
SCOPE="Sources/SuperscribeKit"
# whisper.cpp C API paths in WhisperBackend+LiveAPI.swift require a real GGML model;
# unit tests use stub hooks instead — exclude from the 100% gate.
IGNORE_LIVE_API='WhisperBackend\+LiveAPI\.swift'
REPORT="/tmp/superscribe-coverage-report.txt"

run_tests=false
for arg in "$@"; do
    case "$arg" in
        --run-tests) run_tests=true ;;
        -h|--help)
            echo "Usage: $0 [--run-tests]"
            echo "  COVERAGE_MIN  Minimum line and region coverage % (default: 100)"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done

if [[ "$run_tests" == true ]]; then
    echo "==> Running tests with code coverage..."
    swift test --enable-code-coverage --no-parallel -Xswiftc -strict-concurrency=complete
fi

if [[ ! -f "$PROFILE" ]]; then
    echo "error: profile not found at $PROFILE" >&2
    echo "Run: swift test --enable-code-coverage" >&2
    exit 1
fi

if [[ ! -f "$BINARY" ]]; then
    echo "error: test binary not found at $BINARY" >&2
    exit 1
fi

echo "==> SuperscribeKit coverage report"
echo

# Per-file summary (region cover = 4th column; line cover = 10th column)
xcrun llvm-cov report "$BINARY" \
    -instr-profile="$PROFILE" \
    -ignore-filename-regex="$IGNORE_LIVE_API" \
    "$SCOPE" \
    | tee "$REPORT"

echo

TOTAL_REGION=$(awk '/^TOTAL/ { gsub(/%/, "", $4); print $4 }' "$REPORT")
TOTAL_LINE=$(awk '/^TOTAL/ { gsub(/%/, "", $10); print $10 }' "$REPORT")

if [[ -z "$TOTAL_REGION" || -z "$TOTAL_LINE" ]]; then
    echo "error: could not parse TOTAL coverage from llvm-cov report" >&2
    exit 1
fi

echo "==> SuperscribeKit region coverage: ${TOTAL_REGION}% (minimum: ${COVERAGE_MIN}%)"
echo "==> SuperscribeKit line coverage:   ${TOTAL_LINE}% (minimum: ${COVERAGE_MIN}%)"

below_region=$(echo "$TOTAL_REGION < $COVERAGE_MIN" | bc -l)
below_line=$(echo "$TOTAL_LINE < $COVERAGE_MIN" | bc -l)

if [[ "$below_region" == 1 || "$below_line" == 1 ]]; then
    echo "FAIL: coverage below minimum ${COVERAGE_MIN}%" >&2
    echo
    echo "Files with missed regions:"
    awk '$3 > 0 && /\.swift/ { printf "  %s (%s regions missed, %s covered)\n", $1, $3, $4 }' "$REPORT" || true
    echo
    echo "Files with missed lines:"
    awk '$9 > 0 && /\.swift/ { printf "  %s (%s lines missed, %s covered)\n", $1, $9, $10 }' "$REPORT" || true
    exit 1
fi

echo "PASS: line and region coverage meet minimum ${COVERAGE_MIN}%"
exit 0
