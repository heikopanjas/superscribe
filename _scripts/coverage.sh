#!/usr/bin/env bash
# Measure SuperscribeKit line coverage and fail if below COVERAGE_MIN (default 100).
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

run_tests=false
for arg in "$@"; do
    case "$arg" in
        --run-tests) run_tests=true ;;
        -h|--help)
            echo "Usage: $0 [--run-tests]"
            echo "  COVERAGE_MIN  Minimum line coverage % (default: 100)"
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

# Per-file summary (line coverage = 4th percentage column in llvm-cov report)
xcrun llvm-cov report "$BINARY" \
    -instr-profile="$PROFILE" \
    "$SCOPE" \
    | tee /tmp/superscribe-coverage-report.txt

echo

# Parse TOTAL line coverage (10th field = line Cover %)
TOTAL_LINE=$(awk '/^TOTAL/ { gsub(/%/, "", $10); print $10 }' /tmp/superscribe-coverage-report.txt)

if [[ -z "$TOTAL_LINE" ]]; then
    echo "error: could not parse TOTAL line coverage from llvm-cov report" >&2
    exit 1
fi

echo "==> SuperscribeKit line coverage: ${TOTAL_LINE}% (minimum: ${COVERAGE_MIN}%)"

below_min=$(echo "$TOTAL_LINE < $COVERAGE_MIN" | bc -l)
if [[ "$below_min" == 1 ]]; then
    echo "FAIL: coverage ${TOTAL_LINE}% is below minimum ${COVERAGE_MIN}%" >&2
    echo
    echo "Uncovered files (0% line coverage):"
    awk '$10 == "0.00%" && /\.swift/ { print "  " $1 }' /tmp/superscribe-coverage-report.txt || true
    exit 1
fi

echo "PASS: coverage meets minimum ${COVERAGE_MIN}%"
exit 0
