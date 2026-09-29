import Foundation

enum InlineImageStore {
    static func extractAndReplace(content: String) -> String { content }
}
final class SocketSubscription: @unchecked Sendable {
    var disposed = false
    func dispose() { disposed = true }
}
final class SocketIOService {
    typealias EventHandler = @Sendable ([String: Any], ((Any?) -> Void)?) -> Void
    var chat: EventHandler?
    var channel: EventHandler?
    var registrations: [(String?, String?)] = []
    func addChatEventHandler(conversationId: String?, sessionId: String?, handler: @escaping EventHandler) -> SocketSubscription {
        registrations.append((conversationId, sessionId))
        chat = handler
        return SocketSubscription()
    }
    func addChannelEventHandler(conversationId: String?, sessionId: String?, handler: @escaping EventHandler) -> SocketSubscription {
        channel = handler
        return SocketSubscription()
    }
}
@MainActor final class StreamingContentStore {
    func beginStreamingForContinue(messageId: String, modelId: String?, existingContent: String) {}
}
@MainActor final class RoutingHarness {
    struct Terminal { let id: String }
    var chatSubscription: SocketSubscription?
    var channelSubscription: SocketSubscription?
    var terminalEnabled = false
    var selectedTerminalServer: Terminal?
    var streamingSessionId = 1
    var hasFinishedStreaming = false
    var responseGroup: ChatResponseGroup?
    // RECEIVING
    var socketHasReceivedContent = false
    var content: [String: String] = [:]
    var handled: [(String, String)] = []
    var terminalMessages: [String] = []
    func updateAssistantMessage(id: String, content: String, isStreaming: Bool) { self.content[id] = content }
    func receiveTerminalFile(_ payload: [String: Any]?, messageId: String?, chatId: String?, serverId: String?) {
        if let messageId { terminalMessages.append(messageId) }
    }
    func handleChatEvent(_ event: [String: Any], ack: ((Any?) -> Void)?, assistantMessageId: String,
                         modelId: String, socketSessionId: String, effectiveChatId: String?, acc: ContentAccumulator) {
        handled.append((assistantMessageId, modelId))
    }
    func handleChannelEvent(_ event: [String: Any], assistantMessageId: String, acc: ContentAccumulator) {
        handled.append((assistantMessageId, "channel"))
    }
    // REGISTRATION
}
@main struct RoutingChecks {
    @MainActor static func main() async {
        var passed = 0
        func check(_ value: Bool, _ label: String) {
            guard value else { print("FAIL: " + label); exit(1) }
            passed += 1
            print("PASS: " + label)
        }
        func event(_ id: String?, _ type: String, _ data: [String: Any]) -> [String: Any] {
            var event: [String: Any] = ["data": ["type": type, "data": data]]
            if let id { event["message_id"] = id }
            return event
        }
        func settle() async { try? await Task.sleep(nanoseconds: 20_000_000) }
        let single = RoutingHarness()
        let socket = SocketIOService()
        single.registerSocketHandlers(socket: socket, assistantMessageId: "first", modelId: "paper-model",
                                      socketSessionId: "synthetic-session", effectiveChatId: "synthetic-chat")
        socket.chat?(event("unrelated", "chat:message:delta", ["content": "Wrong response."]), nil)
        await settle()
        check(single.content.isEmpty, "unrelated response cannot contaminate the active accumulator")
        socket.chat?(event(nil, "chat:message:delta", ["content": "Legacy "]), nil)
        socket.chat?(event("first", "chat:message:delta", ["content": "reply."]), nil)
        await settle()
        check(single.content["first"] == "Legacy reply.", "single-response legacy events remain supported")
        check(socket.registrations.first?.0 == "synthetic-chat" && socket.registrations.first?.1 == "synthetic-session",
              "socket registration retains chat and session scope")
        let oldHandler = socket.chat!
        single.streamingSessionId += 1
        oldHandler(event("first", "status", ["done": true]), nil)
        oldHandler(event("first", "terminal:display_file", ["name": "synthetic.txt"]), nil)
        oldHandler(event("first", "chat:message:delta", ["content": " Late."]), nil)
        await settle()
        check(single.handled.isEmpty && single.terminalMessages.isEmpty, "stale registration cannot dispatch metadata or attachments")
        check(single.content["first"] == "Legacy reply.", "stale registration cannot publish late content")

        let continuation = RoutingHarness()
        let continueSocket = SocketIOService()
        continuation.registerSocketHandlers(socket: continueSocket, assistantMessageId: "continued", modelId: "paper-model",
                                            socketSessionId: "synthetic-session", effectiveChatId: "synthetic-chat",
                                            continuePrefix: "First sentence. ")
        continueSocket.chat?(event("continued", "chat:message:delta", ["content": "Next sentence."]), nil)
        await settle()
        check(continuation.content["continued"] == "First sentence. Next sentence.", "immediate Continue delta includes the preserved prefix")

        let group = RoutingHarness()
        let multiSocket = SocketIOService()
        let targets: [ChatCompletionRequest.ResponseTarget] = [
            .init(modelID: "paper-model", messageID: "left", modelIndex: 0),
            .init(modelID: "paper-model", messageID: "right", modelIndex: 1),
            .init(modelID: "fold-model", messageID: "third", modelIndex: 2)
        ]
        group.registerSocketHandlers(socket: multiSocket, assistantMessageId: "left", modelId: "paper-model",
                                     socketSessionId: "synthetic-session", effectiveChatId: "synthetic-chat", responseTargets: targets)
        for index in 0..<30 {
            multiSocket.chat?(event("right", "chat:message:delta", ["content": "R\(index) "]), nil)
            multiSocket.chat?(event("left", "chat:message:delta", ["content": "L\(index) "]), nil)
        }
        multiSocket.chat?(event(nil, "chat:message:delta", ["content": "Ambiguous."]), nil)
        multiSocket.chat?(event("unknown", "chat:message:delta", ["content": "Unknown."]), nil)
        await settle()
        check(group.content["left"] == (0..<30).map { "L\($0) " }.joined(), "interleaved left tokens stay in their response")
        check(group.content["right"] == (0..<30).map { "R\($0) " }.joined(), "duplicate-model right tokens stay independent")
        check(group.content.count == 2, "ambiguous or unknown response IDs do not create streams")
        multiSocket.chat?(event("third", "chat:completion", ["output": [["type": "message", "content": [["type": "output_text", "text": "Fold"]]]]]), nil)
        multiSocket.chat?(event("third", "chat:message:delta", ["content": " gently."]), nil)
        multiSocket.chat?(event("right", "status", ["done": false]), nil)
        multiSocket.chat?(event("right", "terminal:display_file", ["name": "synthetic.txt"]), nil)
        await settle()
        check(group.content["third"] == "Fold gently.", "per-response snapshots precede following deltas")
        check(group.handled.contains { $0 == ("third", "fold-model") }, "metadata handler receives its own model")
        check(group.handled.contains { $0 == ("right", "paper-model") }, "duplicate-model status retains message identity")
        check(group.terminalMessages == ["right"], "terminal attachment routes to its response")

        multiSocket.chat?(event("third", "response:completion", ["type": "response.reasoning_text.delta", "item_id": "reason", "output_index": 0, "delta": "Compare corners."]), nil)
        multiSocket.chat?(event("third", "response:completion", ["type": "response.output_text.delta", "item_id": "answer", "output_index": 1, "delta": "Make a crease."]), nil)
        await settle()
        check(group.content["third"]?.contains("Compare corners.") == true, "thinking remains in its response")
        check(group.content["third"]?.contains("Make a crease.") == true, "answer tokens follow reasoning in the same response")
        check(group.content["left"]?.contains("crease") == false && group.content["right"]?.contains("corners") == false,
              "structured reasoning and output never leak to peers")
        multiSocket.channel?(event("left", "message", ["content": "Channel."]), nil)
        multiSocket.channel?(event(nil, "message", ["content": "Ambiguous channel."]), nil)
        await settle()
        check(group.content["left"]?.hasSuffix("Channel.") == true, "secondary channel uses response identity too")
        check(group.content.values.allSatisfy { !$0.contains("Ambiguous channel") }, "multi-response channel requires a message ID")
        let handler = multiSocket.chat!
        let leftBefore = group.content["left"]!
        let rightBefore = group.content["right"]!
        await withTaskGroup(of: Void.self) { tasks in
            for id in ["left", "right"] {
                tasks.addTask {
                    for index in 0..<100 {
                        handler(["message_id": id, "data": ["type": "chat:message:delta",
                            "data": ["content": "\(id):\(index) "]]], nil)
                    }
                }
            }
        }
        await settle()
        check(group.content["left"] == leftBefore + (0..<100).map { "left:\($0) " }.joined(),
              "concurrent background left deltas remain ordered and complete")
        check(group.content["right"] == rightBefore + (0..<100).map { "right:\($0) " }.joined(),
              "concurrent background right deltas remain ordered and complete")
        let beforeCompletion = group.content
        group.hasFinishedStreaming = true
        handler(event("left", "chat:message:delta", ["content": " Late."]), nil)
        await settle()
        check(group.content == beforeCompletion, "completed generation ignores queued content updates")
        print("\(passed) routing checks passed")
    }
}
