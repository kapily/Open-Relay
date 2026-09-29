#!/bin/sh
set -eu
root=$(git rev-parse --show-toplevel)
test_output=$(mktemp -d "${TMPDIR:-/tmp}/relay-multimodel.XXXXXX")
swiftc -swift-version 5 -parse-as-library \
  "$root/Open UI/Core/Models/ChatMessage.swift" \
  "$root/Open UI/Core/Models/MessageHistory.swift" \
  "$root/Open UI/Core/Networking/APIModels.swift" \
  "$root/Open UI/Core/Networking/WebSearchConfig.swift" \
  "$root/Open UI/Core/Models/AdminUser.swift" \
  "$root/Open UI/Core/Models/User.swift" \
  "$root/Open UI/Core/Extensions/Date+Extensions.swift" \
  "$root/Tests/MultiModel/Checks.swift" -o "$test_output/checks"
"$test_output/checks"
