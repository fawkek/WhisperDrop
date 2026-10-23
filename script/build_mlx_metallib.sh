#!/usr/bin/env bash
set -euo pipefail

# SwiftPM's command-line build does not compile MLX's Metal resources. Use
# Xcode once per dependency/toolchain version, then reuse the resulting library
# for both Debug and Release app bundles. Print only its path on stdout.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "error: MLX shaders require full Xcode; select it with xcode-select." >&2
  exit 1
fi
if [[ ! -f Package.resolved ]]; then
  echo "error: resolve Swift packages before building MLX shaders." >&2
  exit 1
fi

ARCH="$(uname -m)"
CACHE_KEY="$(
  {
    shasum -a 256 Package.swift Package.resolved "$ROOT_DIR/script/build_mlx_metallib.sh"
    xcodebuild -version
    xcrun --sdk macosx --show-sdk-version
    echo "$ARCH macOS 14.0"
  } | shasum -a 256 | cut -d ' ' -f 1
)"
CACHE_DIR="$ROOT_DIR/.build/mlx-metal/$CACHE_KEY"
METALLIB="$CACHE_DIR/mlx.metallib"
if [[ -s "$METALLIB" ]]; then
  echo "Using cached MLX Metal shaders" >&2
  echo "$METALLIB"
  exit 0
fi

mkdir -p "$CACHE_DIR"
BUILD_LOG="$CACHE_DIR/xcodebuild.log"
echo "Building MLX Metal shaders with Xcode (log: $BUILD_LOG)" >&2
if ! xcodebuild build -quiet -scheme WhisperDrop -configuration Release \
  -destination "platform=macOS,arch=$ARCH" \
  -derivedDataPath "$ROOT_DIR/.build/xcode" \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  -skipPackagePluginValidation -skipMacroValidation \
  MACOSX_DEPLOYMENT_TARGET=14.0 CODE_SIGNING_ALLOWED=NO >"$BUILD_LOG" 2>&1; then
  tail -n 60 "$BUILD_LOG" >&2
  echo "error: MLX shader build failed. Install the Metal Toolchain with: xcodebuild -downloadComponent MetalToolchain" >&2
  exit 1
fi

BUILT_LIBRARY="$ROOT_DIR/.build/xcode/Build/Products/Release/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
if [[ ! -s "$BUILT_LIBRARY" ]]; then
  echo "error: Xcode did not produce $BUILT_LIBRARY (see $BUILD_LOG)." >&2
  exit 1
fi
cp "$BUILT_LIBRARY" "$METALLIB.partial"
mv "$METALLIB.partial" "$METALLIB"
echo "$METALLIB"
