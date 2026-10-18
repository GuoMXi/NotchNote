#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/notchnote-checks.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/notchnote-clang"
swiftc -parse-as-library -swift-version 6 -default-isolation MainActor \
  Sources/NotchNote/Note.swift Sources/NotchNote/PanelGeometry.swift \
  Sources/NotchNote/NoteEditor.swift Tests/CoreChecks.swift -o "$check_dir/checks"
"$check_dir/checks"
