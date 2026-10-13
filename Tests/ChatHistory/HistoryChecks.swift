@main struct HistoryChecks {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--benchmark") {
            benchmark(Int(CommandLine.arguments[2])!, mode: CommandLine.arguments[3])
            return
        }
        var checks = 0
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            checks += 1
            if !condition { failures += 1; print("FAIL", name) }
        }
        for state in [Conversation?.none, Conversation(title: "Invented empty tree")] {
            let subject = Subject()
            subject.conversation = state
            subject.writes = 0
            subject.syncFlatMessagesToTreeNodes()
            check(subject.writes == 0, "absent or empty history")
        }
        let source = ChatSourceReference(id: "invented-source", title: "Imaginary Observatory",
                                        url: "https://example.test/comet", snippet: "An invented comet.",
                                        type: "web", metadata: ["sample": "invented"])
        let file = ChatMessageFile(type: "file", url: "https://example.test/catalog.txt",
                                   name: "invented-catalog.txt", contentType: "text/plain")
        let status = ChatStatusUpdate(action: "invented_lookup", description: "Invented sample", done: true)
        let error = ChatMessageError(content: "An invented error.")
        var node = HistoryNode(id: "invented-match", role: .assistant, content: "Keep this invented reply.",
                               files: [file], sources: [source], followUps: ["Invented follow-up"],
                               statusHistory: [status], error: error, usage: ["total_tokens": 7])
        var tree = MessageHistory()
        tree.addNode(node)
        tree.addNode(HistoryNode(id: "invented-inactive", role: .assistant, content: "Inactive invented branch."))
        tree.currentId = node.id
        let subject = Subject()
        subject.conversation = Conversation(title: "Invented metadata", history: tree,
            messages: [ChatMessage(id: node.id, role: .assistant, content: "", isStreaming: true),
                       ChatMessage(id: "invented-missing", role: .assistant, content: "Not a tree node.")])
        subject.writes = 0
        subject.syncFlatMessagesToTreeNodes()
        node = subject.conversation!.history.nodes[node.id]!
        check(node.content == "Keep this invented reply.", "empty flat content preserves tree")
        check(!node.done, "streaming state")
        check(node.files == [file], "empty files preserve tree")
        check(node.sources == [source], "empty sources preserve tree")
        check(node.followUps == ["Invented follow-up"], "empty follow-ups preserve tree")
        check(node.error == error, "absent error preserves tree")
        check(node.statusHistory.first?.description == status.description, "empty status preserves tree")
        check(node.usage?["total_tokens"] as? Int == 7, "absent usage preserves tree")
        check(subject.conversation!.history.nodes["invented-missing"] == nil, "missing node is not created")
        check(subject.conversation!.history.nodes["invented-inactive"]?.content == "Inactive invented branch.", "inactive branch survives")
        check(subject.writes == 1, "one observable history assignment")
        let newFile = ChatMessageFile(type: "file", url: "https://example.test/second.txt", name: "invented-second.txt", contentType: "text/plain")
        let newSource = ChatSourceReference(id: "invented-second", title: "Second invented source", url: "https://example.test/second", snippet: nil, type: nil, metadata: nil)
        let newStatus = ChatStatusUpdate(description: "A new invented status.", done: true)
        subject.conversation!.messages = [ChatMessage(id: node.id, role: .assistant, content: "New invented answer.",
            files: [newFile], sources: [newSource], statusHistory: [newStatus], followUps: ["New invented question"],
            error: ChatMessageError(content: "New invented error."), usage: ["total_tokens": 11])]
        subject.writes = 0
        subject.syncFlatMessagesToTreeNodes()
        let updated = subject.conversation!.history.nodes[node.id]!
        check(updated.content == "New invented answer.", "content copied")
        check(updated.done, "completion copied")
        check(updated.files == [newFile] && updated.sources == [newSource], "metadata copied")
        check(updated.statusHistory.first?.description == newStatus.description, "new status copied")
        check(updated.followUps == ["New invented question"], "follow-ups copied")
        check(updated.error?.content == "New invented error.", "error copied")
        check(updated.usage?["total_tokens"] as? Int == 11, "usage copied")
        check(subject.writes == 1, "batched metadata assignment")

        for count in [2, 12, 1000] {
            let history = makeHistory(count)
            var messages = history.createMessagesList()
            for index in messages.indices {messages[index].content += " A new invented observation."}
            let vm = Subject()
            vm.conversation = Conversation(title: "Invented batched save", history: history, messages: messages)
            vm.writes = 0
            vm.syncFlatMessagesToTreeNodes()
            check(vm.writes == 1, "one assignment for \(count) messages")
            for message in messages {check(vm.conversation!.history.nodes[message.id]?.content == message.content, "all saved contents preserved")}
        }
        for streaming in [false, true] {
            for localStreaming in [false, true] {
                for role in [MessageRole.user, .assistant, .system] {
                    for text in ["", " ", "\n\t\u{2003}", "Invented comet.", "\u{200B}", "🌙 fictional"] {
                        let local = ChatMessage(id: "invented-guard", role: role, content: text, isStreaming: localStreaming)
                        let remote = ChatMessage(id: local.id, role: role, content: "Invented server answer.")
                        let vm = Subject()
                        vm.isStreaming = streaming
                        vm.conversation = Conversation(title: "Invented guard", messages: [local])
                        vm.adoptServerMessages(serverConversation: Conversation(title: "Invented guard", messages: [remote]))
                        let preserves = streaming && !localStreaming && role == .assistant
                            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        check(vm.conversation!.messages[0].content == (preserves ? text : remote.content), "streaming content guard")
                        check(!vm.conversation!.messages[0].isStreaming, "server completion state")
                    }
                }
            }
        }
        let live = Subject()
        live.conversation = Conversation(title: "Invented live stream", messages: [
            ChatMessage(id: "invented-live", role: .assistant, content: "Invented live delta.", isStreaming: true)])
        live.isStreaming = true
        live.streamingStore.isActive = true
        live.streamingStore.streamingMessageId = "invented-live"
        live.adoptServerMessages(serverConversation: Conversation(title: "Invented live stream", messages: [
            ChatMessage(id: "invented-live", role: .assistant, content: "Invented stale response.")]))
        check(live.conversation!.messages[0].content == "Invented live delta.", "live pipeline content retained")
        check(live.conversation!.messages[0].isStreaming, "live pipeline state retained")
        for count in [1, 2, 12, 100, 1000] {
            var history = makeHistory(count)
            if count >= 2 {
                let parent = "invented-comet-\(count-2)"
                history.addNode(HistoryNode(id: "invented-alternative", parentId: parent, role: .assistant,
                    content: "An invented alternative branch.", timestamp: Date(timeIntervalSince1970: -1),
                    files: [file], sources: [source], followUps: ["Invented alternate follow-up"], error: error))
                history.appendChildId("invented-alternative", to: parent)
            }
            let oldMessages = history.createMessagesList()
            let vm = Subject()
            vm.conversation = Conversation(title: "Invented background reply", history: history, messages: oldMessages)
            let previous = history.currentId!
            history.addNode(HistoryNode(id: "invented-extra", parentId: previous, role: .assistant,
                                       content: "An invented background reply.", timestamp: Date(timeIntervalSince1970: Double(count))))
            history.appendChildId("invented-extra", to: previous)
            let remote = Conversation(title: "Invented background reply", history: history, messages: oldMessages)
            vm.adoptServerMessages(serverConversation: remote)
            history.currentId = "invented-extra"
            check(vm.conversation!.messages == history.createMessagesList(), "background tree becomes visible")
            check(vm.conversation!.messages.count == count + 1, "background count")
            check(vm.conversation!.history.currentId == "invented-extra", "stale current ID follows deepest leaf")
            if count >= 2 {check(vm.conversation!.messages[count-1].versions.first?.id == "invented-alternative", "branch version survives snapshot reuse")}
        }
        let first = Subject()
        let server = Conversation(title: "Invented initial load", model: "invented-model", messages: [
            ChatMessage(id: "invented-first", role: .assistant, content: "An invented first reply.")])
        first.adoptServerMessages(serverConversation: server)
        check(first.conversation == server, "initial load")
        check(first.selectedModelId == "invented-model", "initial model")
        print("\(checks-failures)/\(checks) history checks passed")
        if failures > 0 { exit(1) }
    }

    static func makeHistory(_ count: Int) -> MessageHistory {
        var history = MessageHistory()
        for index in 0..<count {
            history.addNode(HistoryNode(id: "invented-comet-\(index)",
                parentId: index > 0 ? "invented-comet-\(index-1)" : nil,
                childrenIds: index + 1 < count ? ["invented-comet-\(index+1)"] : [],
                role: index % 2 == 0 ? .user : .assistant,
                content: "A freshly invented amber comet \(index).",
                timestamp: Date(timeIntervalSince1970: Double(index))))
        }
        history.currentId = count > 0 ? "invented-comet-\(count-1)" : nil
        return history
    }

    static func cpu() -> Double {
        var usage = rusage()
        getrusage(0, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }

    @MainActor static func benchmark(_ count: Int, mode: String) {
        var history = makeHistory(count)
        let messages = history.createMessagesList()
        let local = Conversation(title: "Invented benchmark", history: history, messages: messages)
        let previous = history.currentId!
        history.addNode(HistoryNode(id: "invented-new", parentId: previous, role: .assistant,
                                   content: "Invented background reply.", timestamp: Date(timeIntervalSince1970: Double(count))))
        history.appendChildId("invented-new", to: previous)
        let remote = Conversation(title: local.title, history: history, messages: messages)
        let vm = Subject()
        vm.conversation = local
        vm.writes = 0
        let before = cpu(), start = ProcessInfo.processInfo.systemUptime
        if mode == "sync" { vm.syncFlatMessagesToTreeNodes() }
        else { vm.adoptServerMessages(serverConversation: remote) }
        let cpuMilliseconds = (cpu() - before) * 1000
        let wallMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
        var memory = rusage()
        getrusage(0, &memory)
        if mode == "sync" {
            precondition(vm.conversation!.history.createMessagesList() == messages)
        } else {
            history.currentId = "invented-new"
            precondition(vm.conversation!.messages == history.createMessagesList())
        }
        print(String(data: try! JSONSerialization.data(withJSONObject: [
            "rows": count, "mode": mode, "writes": vm.writes,
            "cpu_ms": cpuMilliseconds, "wall_ms": wallMilliseconds,
            "peak_rss_bytes": memory.ru_maxrss
        ], options: .sortedKeys), encoding: .utf8)!)
    }
}
