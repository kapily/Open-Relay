#!/usr/bin/env python3
"""Compile actual conversation serializers with a synthetic transport."""
import os
import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--metadata-revision", help="Reproduce old response-metadata handling without switching branches")
args = parser.parse_args()
source = (root / "Open UI/Core/Networking/APIClient.swift").read_text()
methods = []
for name in ["parseFullConversation", "parseFolderChatItem", "buildHistoryFromFlatMessages",
             "syncConversationHistory", "createConversationWithHistory", "parseConversationSummary",
             "buildChatPayload", "createConversation", "syncConversationMessages"]:
    signature = source.index("func " + name + "(")
    start = source.rfind("\n", 0, signature) + 1
    end = source.index("\n    }", signature) + len("\n    }")
    methods.append(source[start:end].replace("private ", "", 1))
models_arg = ", models: conversation.models" if "models: [String]?" in source else ""
methods.append("""
    func saveFixture(_ conversation: Conversation) async throws {
        try await syncConversationHistory(id: conversation.id, history: conversation.history,
            model: conversation.model, chatParams: conversation.chatParams""" + models_arg + """)
    }
    func createFixture(_ conversation: Conversation) async throws -> Conversation {
        try await createConversationWithHistory(id: conversation.id, title: conversation.title,
            model: conversation.model, history: conversation.history, messages: conversation.messages,
            chatParams: conversation.chatParams""" + models_arg + """)
    }
    func createEmptyFixture(_ conversation: Conversation) async throws -> Conversation {
        try await createConversation(title: conversation.title, messages: [], model: conversation.model""" + models_arg + """)
    }
    func saveFlatFixture(_ conversation: Conversation) async throws {
        try await syncConversationMessages(id: conversation.id, messages: conversation.messages,
            model: conversation.model""" + models_arg + """)
    }
""")
manager_source = (root / "Open UI/Core/Services/ConversationManager.swift").read_text()
manager_methods = []
for name in ["saveConversation", "syncConversationHistory"]:
    start = manager_source.index("    func " + name + "(")
    end = manager_source.index("\n    }", start) + len("\n    }")
    manager_methods.append(manager_source[start:end])
vm_source = (root / "Open UI/Features/Chat/ViewModels/ChatViewModel.swift").read_text()
start = vm_source.index("    var selectedModelIds:")
end = vm_source.index("    var isStreaming:", start)
selection = vm_source[start:end]
start = vm_source.index("    private func restoreModelSelection(")
end = vm_source.index("\n    }", start) + len("\n    }")
selection += vm_source[start:end].replace("private func", "func", 1)
start = vm_source.index("    func saveAssistantMessageContent(")
end = vm_source.index("\n    }", start) + len("\n    }")
editing = vm_source[start:end]
metadata_source = (subprocess.check_output(["git", "show", f"{args.metadata_revision}:Open UI/Features/Chat/ViewModels/ChatViewModel.swift"], cwd=root, text=True)
                   if args.metadata_revision else vm_source)
metadata = []
for name in ["appendSources", "appendStatusUpdate", "appendFollowUps", "refreshConversationMetadata"]:
    start = metadata_source.index("    private func " + name + "(")
    end = metadata_source.index("\n    }", start) + len("\n    }")
    metadata.append(metadata_source[start:end].replace("private func", "func", 1))
output = Path(tempfile.mkdtemp(prefix="multi-storage-", dir=os.environ.get("TMPDIR", "/tmp")))
harness = output / "Checks.swift"
harness.write_text((root / "Tests/MultiModel/StorageChecks.swift").read_text()
                  .replace("    // PRODUCTION_METHODS", "\n".join(methods))
                  .replace("    // MANAGER_METHODS", "\n".join(manager_methods))
                  .replace("    // SELECTION_METHODS", selection)
                  .replace("    // EDITING_METHODS", editing)
                  .replace("    // METADATA_METHODS", "\n".join(metadata)))
paths = ["Core/Models/ChatMessage.swift", "Core/Models/MessageHistory.swift", "Core/Networking/APIModels.swift",
         "Core/Networking/WebSearchConfig.swift", "Core/Models/AdminUser.swift", "Core/Models/User.swift",
         "Core/Extensions/Date+Extensions.swift", "Core/Models/Conversation.swift", "Core/Models/ChatAdvancedParams.swift"]
subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", *[str(root / "Open UI" / p) for p in paths],
                str(harness), "-o", str(output / "checks")], check=True)
subprocess.run([str(output / "checks")], check=True)
