#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/notchnote-clang"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/notchnote-modules"
swift build -c release --cache-path "${TMPDIR:-/tmp}/notchnote-cache"
binary_dir=$(swift build -c release --show-bin-path --cache-path "${TMPDIR:-/tmp}/notchnote-cache")
app_dir="$PWD/build/NotchNote.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/NotchNote" "$app_dir/Contents/MacOS/NotchNote"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
echo "应用已生成：$app_dir"
