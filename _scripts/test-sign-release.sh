#!/usr/bin/env bash
# Exercise signing orchestration with fake platform tools, never real credentials.
set -euo pipefail

# Symlinks let one stub serve the three external services used by the signer.
tool="${0##*/}"
case "$tool" in
    security)
        echo "security $1" >> "$SIGN_TEST_LOG"
        case "$1" in
            create-keychain) touch "${@: -1}" ;;
            import) [[ "$SIGN_TEST_CASE" != import-failure ]] || exit 1 ;;
            delete-keychain)
                [[ "$SIGN_TEST_CASE" != cleanup-failure ]] || exit 1
                rm -f "${@: -1}"
                ;;
        esac
        exit 0
        ;;
    codesign)
        echo "codesign $1" >> "$SIGN_TEST_LOG"
        if [[ "$1" == --force ]]; then
            [[ "$*" == *'--options runtime --timestamp --keychain'* ]] || exit 1
            [[ "$SIGN_TEST_CASE" != sign-failure ]] || exit 1
        else
            [[ "$*" == *'--verify --strict'* ]] || exit 1
            [[ "$SIGN_TEST_CASE" != verify-failure ]] || exit 1
        fi
        exit 0
        ;;
    xcrun)
        echo "notarytool $2" >> "$SIGN_TEST_LOG"
        if [[ "$2" == log ]]; then
            echo 'stub notarization log'
        else
            [[ "$*" == *'--wait --timeout 30m --output-format json'* ]] || exit 1
            case "$SIGN_TEST_CASE" in
                rejected) echo '{"id":"stub-id","status":"Invalid"}' ;;
                timeout) echo '{"id":"stub-id","status":"In Progress"}'; exit 1 ;;
                cancelled) kill -TERM "$PPID"; exit 143 ;;
                malformed) echo 'invalid json' ;;
                *) echo '{"id":"stub-id","status":"Accepted"}' ;;
            esac
        fi
        exit 0
        ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/superscribe-signing-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
mkdir "$test_dir/tools" "$test_dir/runner"
# Keep the signer and env-based stub shebangs on the harness's selected Bash.
ln -s "$BASH" "$test_dir/tools/bash"
for tool in security codesign xcrun; do
    ln -s "$script_dir/test-sign-release.sh" "$test_dir/tools/$tool"
done
export PATH="$test_dir/tools:$PATH"
export RUNNER_TEMP="$test_dir/runner"
export SIGN_TEST_LOG="$test_dir/calls.log"
export APPLE_CERTIFICATE_P12_BASE64=c3R1Yg==
export APPLE_CERTIFICATE_PASSWORD=stub-password
export APPLE_SIGNING_IDENTITY=stub-identity
export APPSTORE_CONNECT_KEY_ID=stub-key
export APPSTORE_CONNECT_ISSUER_ID=stub-issuer
export APPSTORE_CONNECT_KEY_P8_BASE64=c3R1Yg==
printf '#!/bin/sh\nexit 0\n' > "$test_dir/binary"
chmod 755 "$test_dir/binary"

run_case() {
    export SIGN_TEST_CASE="$1"
    local expected_exit="$2"
    shift 2
    : > "$SIGN_TEST_LOG"
    local result=0
    "$BASH" "$script_dir/sign-release.sh" "$@" > "$test_dir/output.log" 2>&1 || result=$?
    if [[ "$result" -ne "$expected_exit" ]]; then
        cat "$test_dir/output.log" >&2
        echo "FAIL: $SIGN_TEST_CASE returned $result, expected $expected_exit" >&2
        exit 1
    fi
    if [[ -n "$(ls -A "$RUNNER_TEMP")" ]]; then
        echo "FAIL: $SIGN_TEST_CASE left signing material behind" >&2
        exit 1
    fi
    echo "PASS: $SIGN_TEST_CASE"
}

run_case missing-binary 2
run_case invalid-binary 2 "$test_dir/missing"
saved_password="$APPLE_CERTIFICATE_PASSWORD"
unset APPLE_CERTIFICATE_PASSWORD
run_case missing-secret 1 "$test_dir/binary"
[[ ! -s "$SIGN_TEST_LOG" ]]
export APPLE_CERTIFICATE_PASSWORD="$saved_password"

for failure in import-failure sign-failure verify-failure; do
    run_case "$failure" 1 "$test_dir/binary"
    if grep -q 'notarytool submit' "$SIGN_TEST_LOG"; then
        echo "FAIL: notarization ran after $failure" >&2
        exit 1
    fi
    grep -q 'security delete-keychain' "$SIGN_TEST_LOG"
done
for failure in rejected timeout; do
    run_case "$failure" 1 "$test_dir/binary"
    grep -q 'notarytool log' "$SIGN_TEST_LOG"
done
run_case malformed 5 "$test_dir/binary"
run_case cancelled 143 "$test_dir/binary"
run_case cleanup-failure 0 "$test_dir/binary"
run_case accepted 0 "$test_dir/binary"
grep -q 'codesign --verify' "$SIGN_TEST_LOG"
grep -q 'notarytool submit' "$SIGN_TEST_LOG"
grep -q 'security delete-keychain' "$SIGN_TEST_LOG"
if grep -q 'notarytool log' "$SIGN_TEST_LOG"; then
    echo 'FAIL: successful notarization requested failure logs' >&2
    exit 1
fi
