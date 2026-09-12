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
SCOPE="Sources/SuperscribeKit"
# whisper.cpp C API paths in WhisperLiveAPI.swift require a real GGML model;
# unit tests use stub hooks instead — exclude from the 100% gate.
IGNORE_LIVE_API='WhisperLiveAPI\.swift|AppleSpeechLiveAPI\.swift|AppleSpeechTranscriberBridge\.swift'
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/superscribe-coverage.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
REPORT="$WORK_DIR/report.txt"
DIAGNOSTICS="$WORK_DIR/diagnostics.txt"

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

# Use exactly the SwiftPM configuration executed below; never select Xcode artifacts.
BUILD_DIR="$(swift build --show-bin-path)"
PROFILE="$BUILD_DIR/codecov/default.profdata"
# Swift Build (Swift 6.4+) emits the target name; native SwiftPM emits the package name.
if [[ "$BUILD_DIR" == */Products/* ]]; then
    TEST_NAME="superscribeTests"
else
    TEST_NAME="superscribePackageTests"
fi
BINARY="$BUILD_DIR/$TEST_NAME.xctest/Contents/MacOS/$TEST_NAME"
RECEIPT="$BUILD_DIR/codecov/superscribe-coverage.sha256"
INPUT_LIST="$BUILD_DIR/codecov/superscribe-coverage-inputs.txt"
rg --files Sources Tests Package.swift Package.resolved | LC_ALL=C sort > "$WORK_DIR/inputs-before.txt"

if [[ "$run_tests" == true ]]; then
    touch "$WORK_DIR/started"
    # Record the exact owned inputs before the build, and reject edits during testing.
    rg --files -0 Sources Tests | xargs -0 shasum -a 256 > "$WORK_DIR/sources.sha256"
    shasum -a 256 Package.swift Package.resolved >> "$WORK_DIR/sources.sha256"
    echo "==> Running tests with code coverage..."
    swift test --enable-code-coverage --no-parallel -Xswiftc -strict-concurrency=complete
    if [[ ! -f "$PROFILE" || ! "$PROFILE" -nt "$WORK_DIR/started" ]]; then
        echo "error: this test run did not produce a fresh profile at $PROFILE" >&2
        exit 1
    fi
    if [[ ! -f "$BINARY" ]]; then
        echo "error: this test run did not produce $BINARY" >&2
        exit 1
    fi
    rg --files Sources Tests Package.swift Package.resolved | LC_ALL=C sort > "$WORK_DIR/inputs-after.txt"
    if ! cmp -s "$WORK_DIR/inputs-before.txt" "$WORK_DIR/inputs-after.txt" || ! shasum -a 256 --check --status "$WORK_DIR/sources.sha256"; then
        echo "error: source inputs changed during the test run; rerun coverage" >&2
        exit 1
    fi
    shasum -a 256 "$BINARY" "$PROFILE" > "$RECEIPT"
    cat "$WORK_DIR/sources.sha256" >> "$RECEIPT"
    cp "$WORK_DIR/inputs-before.txt" "$INPUT_LIST"
fi

if [[ ! -f "$RECEIPT" || ! -f "$INPUT_LIST" ]] || ! cmp -s "$WORK_DIR/inputs-before.txt" "$INPUT_LIST" || ! shasum -a 256 --check --status "$RECEIPT"; then
    echo "error: missing or mismatched coverage artifacts; run $0 --run-tests" >&2
    exit 1
fi

echo "==> SuperscribeKit coverage report"
echo

# Per-file summary (region cover = 4th column; line cover = 10th column)
xcrun llvm-cov report "$BINARY" \
    -instr-profile="$PROFILE" \
    -ignore-filename-regex="$IGNORE_LIVE_API" \
    "$SCOPE" 2> "$DIAGNOSTICS" \
    | tee "$REPORT"

if [[ -s "$DIAGNOSTICS" ]]; then
    cat "$DIAGNOSTICS" >&2
    echo "error: llvm-cov reported profile diagnostics" >&2
    exit 1
fi

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
