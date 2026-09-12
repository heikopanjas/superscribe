#!/bin/bash
# Publish already-tested assets using aranet-kit's tag and title conventions.
set -euo pipefail

if [[ $# != 2 ]]; then
    echo "usage: $0 <version> <asset-directory>" >&2
    exit 64
fi
root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=_scripts/release-common.sh
source "$root/_scripts/release-common.sh"
version="$(release_version "$1")"
assets=$2
[[ "${GITHUB_EVENT_NAME:-}" == push ]] || { echo "error: only pushes publish releases" >&2; exit 1; }
: "${GITHUB_REPOSITORY:?}" "${GITHUB_SHA:?}" "${GH_TOKEN:?}"
[[ "$GITHUB_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "error: expected a full commit SHA" >&2; exit 1; }

case "${GITHUB_REF:-}" in
    refs/heads/main)
        tag="v$version"
        title="$tag"
        files=("$assets/$(release_archive_root "$version").tar.gz" "$assets/SHA256SUMS.txt")
        flags=()
        notes="Developer ID-signed and notarized executable for Apple Silicon Macs. Extract the archive and verify it with SHA256SUMS.txt."
        (cd "$assets" && shasum -a 256 --check SHA256SUMS.txt)
        ;;
    refs/heads/develop|refs/heads/feature/?*)
        [[ "${GITHUB_RUN_NUMBER:-}" =~ ^[0-9]+$ ]] || { echo "error: invalid run number" >&2; exit 1; }
        datetime="$(date -u +'%Y%m%d_%H%M%S')"
        tag="R${version}_BUILD_${GITHUB_RUN_NUMBER}_${datetime}"
        title="superscribe-build-${GITHUB_RUN_NUMBER}-${datetime/_/-}"
        files=("$assets/superscribe")
        flags=(--prerelease --latest=false)
        notes="Unsigned development build from ${GITHUB_REF#refs/heads/} at $GITHUB_SHA. Not signed or notarized; run chmod +x superscribe after downloading."
        ;;
    *) echo "error: branch is not eligible for release publication" >&2; exit 1 ;;
esac

for asset in "${files[@]}"; do
    test -s "$asset"
done
# Fail on API errors and existing tags; never move a tag or replace a release.
existing="$(gh api "repos/$GITHUB_REPOSITORY/git/matching-refs/tags/$tag" \
    --jq ".[] | select(.ref == \"refs/tags/$tag\") | .ref")"
if [[ -n "$existing" ]]; then
    echo "error: tag $tag already exists; use a new product version for a stable release" >&2
    exit 1
fi
gh release create "$tag" "${files[@]}" \
    --repo "$GITHUB_REPOSITORY" --target "$GITHUB_SHA" \
    --title "$title" --notes "$notes" --generate-notes \
    ${flags[@]+"${flags[@]}"}
