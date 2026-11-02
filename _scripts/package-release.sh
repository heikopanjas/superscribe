#!/bin/bash
# Match aranet-kit's versioned archive layout and checksum asset.
set -euo pipefail

if [[ $# != 3 ]]; then
    echo "usage: $0 <version> <binary> <new-output-directory>" >&2
    exit 64
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=_scripts/release-common.sh
source "$root/_scripts/release-common.sh"
version="$(release_version "$1")"
binary=$2
output=$3
archive_root="$(release_archive_root "$version")"
test -x "$binary"
# A fresh output directory prevents stale assets or accidental overwrites.
mkdir "$output"
staging="$(mktemp -d "$output/.package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir "$staging/$archive_root"
cp "$binary" "$staging/$archive_root/superscribe"
binary_dir="$(dirname "$binary")"
test -s "$binary_dir/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
for bundle in "$binary_dir"/*.bundle; do
    test -d "$bundle" || continue
    cp -R "$bundle" "$staging/$archive_root/"
done
cp "$root/LICENSE" "$root/README.md" "$staging/$archive_root/"
COPYFILE_DISABLE=1 tar -czf "$output/$archive_root.tar.gz" -C "$staging" "$archive_root"
(
    cd "$output"
    shasum -a 256 "$archive_root.tar.gz" > SHA256SUMS.txt
)
