#!/usr/bin/env bash
# Run the full superscribe test suite.
#
# Swift Testing parallelizes by default; shared test hooks require serial runs.
#
# Usage:
#   _scripts/test.sh              # all tests (recommended)
#   _scripts/test.sh --filter Foo # single test/suite
#
# Equivalent: swift test --no-parallel -Xswiftc -strict-concurrency=complete "$@"

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

exec swift test --no-parallel -Xswiftc -strict-concurrency=complete "$@"
