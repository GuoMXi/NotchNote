#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/notchnote-meetings.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/notchnote-clang"
swiftc -parse-as-library -swift-version 6 -default-isolation MainActor \
  Sources/NotchNote/Note.swift Sources/NotchNote/RichText.swift \
  Sources/NotchNote/Meetings.swift Sources/NotchNote/MeetingCalendar.swift Sources/NotchNote/MeetingPlan.swift \
  Sources/NotchNote/MeetingReminders.swift Tests/MeetingChecks.swift -o "$check_dir/checks"
"$check_dir/checks"
