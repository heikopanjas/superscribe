#!/bin/bash
# Shared product-version validation and archive naming for release tooling.

release_version() {
    if [[ ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "error: invalid product version" >&2
        return 1
    fi
    printf '%s\n' "$1"
}

release_archive_root() {
    printf 'superscribe-%s-macos-arm64\n' "$1"
}
