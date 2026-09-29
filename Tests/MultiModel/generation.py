#!/usr/bin/env python3
"""Compile the production group lifecycle with synthetic transport/display doubles."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / "Open UI/Features/Chat/ViewModels/ChatViewModel.swift").read_text()
methods = []
for name in ["streamingStore", "isReceivingResponse", "prepareResponseStores", "submitComparisonRequest",
             "finishComparisonResponse", "commitComparisonResponse", "finishComparisonGroupIfReady",
             "recoverComparisonGroup", "startComparisonRecovery", "failResponse", "buildSimpleAPIMessages",
             "updateAssistantMessage", "stopStreaming", "adoptServerMessages",
             "regenerateResponse", "continueLastResponse", "populateCommonRequestFields",
             "editMessage", "regenerateIntoExistingMessage"]:
    signature = source.index("func " + name + "(")
    start = source.rfind("\n", 0, signature) + 1
    end = source.index("\n    }", signature) + len("\n    }")
    methods.append(source[start:end].replace("private ", "", 1))
accumulator = source[source.index("final class ContentAccumulator:"):]
output = Path(tempfile.mkdtemp(prefix="multi-generation-", dir=os.environ.get("TMPDIR", "/tmp")))
harness = output / "Checks.swift"
harness.write_text((root / "Tests/MultiModel/GenerationChecks.swift").read_text()
                  .replace("    // METHODS", "\n".join(methods)) + "\n" + accumulator)
paths = ["Core/Models/ChatMessage.swift", "Core/Models/MessageHistory.swift", "Core/Networking/APIModels.swift",
         "Core/Networking/WebSearchConfig.swift", "Core/Models/AdminUser.swift", "Core/Models/User.swift",
         "Core/Extensions/Date+Extensions.swift", "Core/Models/Conversation.swift", "Core/Models/ChatAdvancedParams.swift",
         "Core/Services/ChatResponseGroup.swift"]
subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", *[str(root / "Open UI" / p) for p in paths],
                str(harness), "-o", str(output / "checks")], check=True)
subprocess.run([str(output / "checks")], check=True)
