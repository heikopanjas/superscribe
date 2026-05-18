#!/usr/bin/env bash
# Build whisper.cpp as a static arm64 xcframework for use via SPM binaryTarget.
#
# Requirements: cmake, ninja  (brew install cmake ninja)
# Output:       whisper-build/whisper.xcframework  (gitignored)
#
# Idempotent: re-running when the xcframework already exists is a no-op.
# To force a rebuild, delete whisper-build/ and re-run.

set -euo pipefail

WHISPER_VERSION="1.7.5"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC_DIR="$REPO_ROOT/whisper-src"
BUILD_ROOT="$REPO_ROOT/whisper-build"
BUILD_DIR="$BUILD_ROOT/cmake"
COMBINED_LIB="$BUILD_ROOT/libwhisper.a"
XCFW_DIR="$BUILD_ROOT/whisper.xcframework"

# ── prerequisite checks ────────────────────────────────────────────────────────
for tool in cmake ninja curl tar libtool xcodebuild; do
    if ! command -v "$tool" &>/dev/null; then
        echo "error: '$tool' not found on PATH."
        [[ "$tool" == "cmake" || "$tool" == "ninja" ]] && \
            echo "       Install with: brew install cmake ninja"
        exit 1
    fi
done

# ── idempotency ────────────────────────────────────────────────────────────────
if [[ -d "$XCFW_DIR" ]]; then
    echo "whisper.xcframework already exists at:"
    echo "  $XCFW_DIR"
    echo "Delete whisper-build/ and re-run to rebuild."
    exit 0
fi

mkdir -p "$BUILD_ROOT"

# ── download ───────────────────────────────────────────────────────────────────
if [[ ! -d "$SRC_DIR" ]]; then
    TARBALL="$BUILD_ROOT/whisper-v${WHISPER_VERSION}.tar.gz"
    echo "==> Downloading whisper.cpp v${WHISPER_VERSION}..."
    curl -L --fail --progress-bar \
        "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v${WHISPER_VERSION}.tar.gz" \
        -o "$TARBALL"
    echo "==> Extracting..."
    mkdir -p "$SRC_DIR"
    tar -xf "$TARBALL" --strip-components=1 -C "$SRC_DIR"
    rm "$TARBALL"
else
    echo "==> Source already at $SRC_DIR — skipping download."
fi

# ── cmake configure ────────────────────────────────────────────────────────────
echo "==> Configuring (CMake + Ninja, arm64, Release)..."
cmake -B "$BUILD_DIR" -S "$SRC_DIR" \
    -G Ninja \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    --log-level=WARNING

# ── build ──────────────────────────────────────────────────────────────────────
echo "==> Building..."
cmake --build "$BUILD_DIR" --config Release

# ── combine static libs ────────────────────────────────────────────────────────
echo "==> Combining static libraries..."

# Collect all .a files produced by the build (whisper + ggml family).
mapfile -t LIBS < <(find "$BUILD_DIR" \
    \( -name "libwhisper.a" -o -name "libggml*.a" \) \
    | sort)

if [[ ${#LIBS[@]} -eq 0 ]]; then
    echo "error: no .a files found under $BUILD_DIR"
    exit 1
fi

echo "  Found:"
for lib in "${LIBS[@]}"; do
    echo "    $lib"
done

# libtool -static warns about duplicate symbols from ggml internals; suppress.
libtool -static -o "$COMBINED_LIB" "${LIBS[@]}" 2>/dev/null

# ── merge headers ─────────────────────────────────────────────────────────────
# whisper.h includes ggml.h and ggml-cpu.h from ggml/include/ — combine both
# header directories so SPM can resolve all transitive includes.
HEADERS_MERGED="$BUILD_ROOT/headers"
rm -rf "$HEADERS_MERGED"
mkdir -p "$HEADERS_MERGED"
cp "$SRC_DIR"/include/*.h     "$HEADERS_MERGED/"
cp "$SRC_DIR"/ggml/include/*.h "$HEADERS_MERGED/"

# ── create xcframework ─────────────────────────────────────────────────────────
echo "==> Creating xcframework..."
xcodebuild -create-xcframework \
    -library "$COMBINED_LIB" \
    -headers "$HEADERS_MERGED/" \
    -output "$XCFW_DIR"

# ── write module.modulemap ─────────────────────────────────────────────────────
# SPM needs a modulemap adjacent to the headers so `import whisper` works.
HEADERS_DIR="$(find "$XCFW_DIR" -type d -name "Headers" | head -1)"
if [[ -z "$HEADERS_DIR" ]]; then
    echo "error: could not locate Headers/ inside $XCFW_DIR"
    exit 1
fi

cat > "$HEADERS_DIR/module.modulemap" << 'MODULEMAP'
module whisper {
    header "whisper.h"
    export *
}
MODULEMAP

# ── done ───────────────────────────────────────────────────────────────────────
echo ""
echo "Done. whisper.xcframework built at:"
echo "  $XCFW_DIR"
echo ""
echo "Next: swift build"
