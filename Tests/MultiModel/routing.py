#!/usr/bin/env python3
"""Exercise actual socket registration and accumulation with synthetic callbacks."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--revision", help="Read old routing without switching branches")
args = parser.parse_args()
path = "Open UI/Features/Chat/ViewModels/ChatViewModel.swift"
source = (subprocess.check_output(["git", "show", f"{args.revision}:{path}"], cwd=root, text=True)
          if args.revision else (root / path).read_text())
start = source.index("    private func registerSocketHandlers(")
end = source.index("\n    }", start) + len("\n    }")
registration = source[start:end].replace("private func", "func", 1)
start = source.index("    private func isReceivingResponse(") if "private func isReceivingResponse(" in source else -1
receiving = (source[start:source.index("\n    }", start) + len("\n    }")].replace("private func", "func", 1)
             if start >= 0 else "")
accumulator = source[source.index("final class ContentAccumulator:"):]
template = (root / "Tests/MultiModel/RoutingChecks.swift").read_text()
if "responseTargets:" not in registration:
    # The old registration had only one destination; the test still sends both IDs.
    template = template.replace(", responseTargets: targets", "")
output = Path(tempfile.mkdtemp(prefix="multi-routing-", dir=os.environ.get("TMPDIR", "/tmp")))
harness = output / "Checks.swift"
uses_group = "responseGroup?.accumulators" in registration
group_stub = "" if uses_group else "\n@MainActor final class ChatResponseGroup {}\n"
harness.write_text(template.replace("    // REGISTRATION", registration).replace("    // RECEIVING", receiving) + "\n" + accumulator + group_stub)
paths = ["Core/Models/ChatMessage.swift", "Core/Models/MessageHistory.swift", "Core/Networking/APIModels.swift",
         "Core/Networking/WebSearchConfig.swift", "Core/Models/AdminUser.swift", "Core/Models/User.swift",
         "Core/Extensions/Date+Extensions.swift"]
if uses_group:
    paths.append("Core/Services/ChatResponseGroup.swift")
subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", *[str(root / "Open UI" / p) for p in paths],
                str(harness), "-o", str(output / "checks")], check=True)
subprocess.run([str(output / "checks")], check=True)
