#!/usr/bin/env bash
# Sign and notarize a staged macOS executable using repository-secret variables.
# Usage: bash _scripts/sign-release.sh <binary>
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" || ! -x "$1" ]]; then
    echo "Usage: $0 <executable binary>" >&2
    exit 2
fi
binary="$1"

for variable in \
    APPLE_CERTIFICATE_P12_BASE64 APPLE_CERTIFICATE_PASSWORD APPLE_SIGNING_IDENTITY \
    APPSTORE_CONNECT_KEY_ID APPSTORE_CONNECT_ISSUER_ID APPSTORE_CONNECT_KEY_P8_BASE64
do
    if [[ -z "${!variable:-}" ]]; then
        echo "error: repository secret $variable is missing" >&2
        exit 1
    fi
done

umask 077
# Preserve the caller's keychains while adding the temporary signing keychain.
original_keychains=()
keychain_list="$(security list-keychains -d user)"
while IFS= read -r existing_keychain; do
    [[ -n "$existing_keychain" ]] || continue
    existing_keychain="${existing_keychain#*\"}"
    existing_keychain="${existing_keychain%\"*}"
    original_keychains+=("$existing_keychain")
done <<< "$keychain_list"
signing_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/superscribe-signing.XXXXXX")"
keychain="$signing_dir/release.keychain-db"
cleanup() {
    security list-keychains -d user -s ${original_keychains[@]+"${original_keychains[@]}"} >/dev/null 2>&1 || true
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
    rm -f "$signing_dir/certificate.p12" "$signing_dir/AuthKey.p8" \
        "$signing_dir/notarization.zip" "$signing_dir/result.json" \
        "$keychain" "$keychain-shm" "$keychain-wal"
    rmdir "$signing_dir" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

keychain_password="$(openssl rand -hex 32)"
printf '%s' "$APPLE_CERTIFICATE_P12_BASE64" | base64 -D > "$signing_dir/certificate.p12"
printf '%s' "$APPSTORE_CONNECT_KEY_P8_BASE64" | base64 -D > "$signing_dir/AuthKey.p8"

security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$signing_dir/certificate.p12" -P "$APPLE_CERTIFICATE_PASSWORD" \
    -A -t cert -f pkcs12 -k "$keychain" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" ${original_keychains[@]+"${original_keychains[@]}"}

signing_identities="$(security find-identity -v -p codesigning "$keychain")"
if ! printf '%s\n' "$signing_identities" | grep -Eq '^[[:space:]]*[0-9]+\) [[:xdigit:]]{40} '; then
    echo 'error: the imported P12 has no valid code-signing identity; check that it includes the private key and a valid Developer ID Application certificate and chain' >&2
    exit 1
fi

if ! codesign --force --options runtime --timestamp --sign "$APPLE_SIGNING_IDENTITY" "$binary"; then
    echo 'error: signing failed; verify APPLE_SIGNING_IDENTITY matches the imported certificate name or SHA-1 fingerprint' >&2
    exit 1
fi
codesign --verify --strict --verbose=2 "$binary"

ditto -c -k --keepParent "$binary" "$signing_dir/notarization.zip"
notary_auth=(--key "$signing_dir/AuthKey.p8" --key-id "$APPSTORE_CONNECT_KEY_ID" --issuer "$APPSTORE_CONNECT_ISSUER_ID")
submission_exit=0
xcrun notarytool submit "$signing_dir/notarization.zip" "${notary_auth[@]}" \
    --wait --timeout 30m --output-format json > "$signing_dir/result.json" || submission_exit=$?

notary_status="$(jq -r '.status // empty' "$signing_dir/result.json")"
if [[ "$submission_exit" -ne 0 || "$notary_status" != Accepted ]]; then
    echo "error: notarization did not succeed (status: ${notary_status:-unknown}, exit: $submission_exit)" >&2
    submission_id="$(jq -r '.id // empty' "$signing_dir/result.json")"
    if [[ -n "$submission_id" ]]; then
        xcrun notarytool log "$submission_id" "${notary_auth[@]}" || true
    fi
    exit 1
fi

# Bare executables cannot be stapled; Apple's ticket is associated with the signature.
echo "Developer ID signature verified; notarization accepted."
