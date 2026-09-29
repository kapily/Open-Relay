import Foundation

enum UserDefaults {
    struct Defaults { func object(forKey key: String) -> Any? { nil } }
    static let standard = Defaults()
}
enum PromptService {
    static func buildSystemVariablesDict(userName: String?, userEmail: String?) -> [String: Any] { [:] }
}
enum InlineImageStore { static func extractAndReplace(content: String) -> String { content } }
enum APIClient {
    static func buildHistoryFromFlatMessages(_ messages: [ChatMessage]) -> MessageHistory {
        preconditionFailure("These generation fixtures require populated native history")
    }
}
final class SocketSubscription { func dispose() {} }
final class SocketIOService {
    var isConnected = true
    var sid: String? = "synthetic-session"
    func ensureConnected(timeout: Double) async -> Bool { isConnected }
}
extension Notification.Name { static let conversationListNeedsRefresh = Self("synthetic-list-refresh") }

// Display timing is verified separately in the app. This double records the data
// crossing the real lifecycle methods without using preferences, network, or audio.
@MainActor final class StreamingContentStore {
    var streamingMessageId: String?
    var isActive = false
    var content = ""
    var sources: [ChatSourceReference] = []
    var statuses: [ChatStatusUpdate] = []
    var error: ChatMessageError?
    struct StreamingResult {
        let content: String
        let sources: [ChatSourceReference]
        let statusHistory: [ChatStatusUpdate]
        let error: ChatMessageError?
    }
    func beginStreamingForContinue(messageId: String, modelId: String?, existingContent: String) {
        streamingMessageId = messageId
        isActive = true
        content = existingContent
    }
    func updateContent(_ content: String) { self.content = content }
    func appendSources(_ sources: [ChatSourceReference]) { self.sources += sources }
    func appendStatus(_ status: ChatStatusUpdate) { statuses.append(status) }
    func setError(_ error: ChatMessageError) { self.error = error }
    @discardableResult func endStreaming(finalContent: String? = nil, onFinished: (() -> Void)? = nil) -> StreamingResult {
        if let finalContent { content = finalContent }
        let result = StreamingResult(content: content, sources: sources, statusHistory: statuses, error: error)
        isActive = false
        onFinished?()
        return result
    }
    @discardableResult func abortStreaming() -> StreamingResult {
        let result = endStreaming()
        streamingMessageId = nil
        return result
    }
}
@MainActor final class FixtureAPI {
    var stopped: [String] = []
    var stoppedChats: [String] = []
    func stopTask(taskId: String) async throws { stopped.append(taskId) }
    func stopTasksByChatId(chatId: String) async throws { stoppedChats.append(chatId) }
}
@MainActor final class FixtureManager {
    let apiClient = FixtureAPI()
    var response: [String: Any] = ["task_ids": ["task-left", "task-right"]]
    var completionRequests: [ChatCompletionRequest] = []
    var completed: [(String, [[String: Any]])] = []
    var fetched: Conversation?
    var afterFetch: (() -> Void)?
    var suspendPost = false
    var postContinuation: CheckedContinuation<[String: Any], Error>?
    func sendMessageHTTP(request: ChatCompletionRequest) async throws -> [String: Any] {
        completionRequests.append(request)
        if suspendPost { return try await withCheckedThrowingContinuation { postContinuation = $0 } }
        return response
    }
    func sendChatCompleted(chatId: String, messageId: String, model: String, sessionId: String, messages: [[String: Any]]) async {
        completed.append((messageId, messages))
    }
    func fetchConversation(id: String) async throws -> Conversation {
        let result = fetched!
        afterFetch?()
        return result
    }
}
@MainActor final class GenerationHarness {
    struct TaskConfig {
        static let `default` = TaskConfig()
        var enableTitleGeneration = true
        var enableFollowUpGeneration = true
        var enableTagsGeneration = true
    }
    struct Store {
        var cachedUserDefaultParams: ChatAdvancedParams?
        var cachedUserName: String?
        var cachedUserEmail: String?
        var serverTaskConfig: TaskConfig = .default
    }
    struct Model {
        let id: String
        var rawModelItem: [String: Any]?
        var isPipeModel = false
        var filterIds: [String] = []
        var functionCallingMode: String?
    }
    struct Terminal { var id: String }
    struct Queued { let text: String }
    struct Logger {
        func info(_ value: String) {}
        func warning(_ value: String) {}
    }
    var conversation: Conversation?
    var conversationId: String?
    var manager: FixtureManager? = FixtureManager()
    var responseGroup: ChatResponseGroup?
    let streamingStore = StreamingContentStore()
    var activeChatStore: Store?
    var isStreaming = true
    var hasFinishedStreaming = false
    var selfInitiatedStream = true
    var messageQueue: [Queued] = []
    var notified: [String] = []
    var queuedSends: [String] = []
    var cleanupCount = 0
    var metadataRefreshes: [String] = []
    var streamingSessionId = 1
    var streamingTask: Task<Void, Never>?
    var completionTask: Task<Void, Never>?
    var isExternallyStreaming = false
    var selectedModelId: String? = "different-primary"
    var selectedModelIds: [String] = []
    var sessionId = "synthetic-session"
    var regenerateScrollToken = UUID()
    var socketService: SocketIOService? = SocketIOService()
    var chatSubscription: SocketSubscription?
    var channelSubscription: SocketSubscription?
    var recoveryTimer: Timer?
    var registeredTargets: [ChatCompletionRequest.ResponseTarget]?
    var availableModels: [Model] = []
    var selectedModel: Model? { availableModels.first { $0.id == selectedModelId } }
    var modelConfigTask: Task<Void, Never>?
    var userDefaultParamsTask: Task<Void, Never>?
    var isToolPermissionsEnabled = false
    var isTemporaryChat = false
    var toolApprovalMode = "ask"
    var selectedToolIds: Set<String> = []
    var folderContextId: String?
    var terminalEnabled = false
    var selectedTerminalServer: Terminal?
    var activeTaskId: String?
    var lastTaskExtractionLength = 0
    var isSavingContext = false
    var chatFiles: [ChatMessageFile] = []
    var deletedMessageIds: Set<String> = []
    var tasks: [ChatTask] = []
    let logger = Logger()
    func stopSwitchStatusPolling() {}
    func startPassiveSocketListener() {}
    func endBackgroundTask() {}
    func sendCompletionNotificationIfNeeded(content: String) async { if !content.isEmpty { notified.append(content) } }
    func sendMessage(directText: String) async { queuedSends.append(directText) }
    func refreshConversationMetadata(chatId: String, assistantMessageId: String) async throws { metadataRefreshes.append(assistantMessageId) }
    func appendSources(id: String, sources: [ChatSourceReference]) { responseGroup?.stores[id]?.appendSources(sources) }
    func appendStatusUpdate(id: String, status: ChatStatusUpdate) { responseGroup?.stores[id]?.appendStatus(status) }
    func extractErrorContent(from payload: [String: Any]) -> String { payload["error"] as? String ?? "Synthetic failure" }
    func cleanupStreaming() { cleanupCount += 1 }
    func extractAndApplyTasksFromContent(_ content: String) {}
    func syncToServerViaTree() async {}
    func syncCurrentIdToServer() async {}
    func restoreModelSelection(from conversation: Conversation) {}
    func buildAPIMessagesAsync() async -> [[String: Any]] { buildSimpleAPIMessages() }
    func refreshSelectedModelMetadata() async {}
    func buildChatFeatures() -> ChatCompletionRequest.ChatFeatures { .init() }
    func contextFileRefs(currentFiles: [ChatMessageFile]) async -> [[String: Any]] { currentFiles.map(\.serverDictionary) }
    func registerSocketHandlers(socket: SocketIOService, assistantMessageId: String, modelId: String,
                                socketSessionId: String, effectiveChatId: String?, continuePrefix: String? = nil,
                                responseTargets: [ChatCompletionRequest.ResponseTarget]? = nil) {
        registeredTargets = responseTargets
        if let continuePrefix { responseGroup?.accumulators[assistantMessageId]?.replace(continuePrefix) }
    }
    // METHODS
}
@main struct GenerationChecks {
    @MainActor static func main() async {
        var checks = 0
        func check(_ value: Bool, _ label: String) {
            guard value else { print("FAIL: " + label); exit(1) }
            checks += 1
            print("PASS: " + label)
        }
        func settle() async { try? await Task.sleep(nanoseconds: 20_000_000) }
        let targets: [ChatCompletionRequest.ResponseTarget] = [
            .init(modelID: "paper-model", messageID: "left", modelIndex: 0),
            .init(modelID: "paper-model", messageID: "right", modelIndex: 1)
        ]
        func fixture() -> GenerationHarness {
            let vm = GenerationHarness()
            var history = MessageHistory()
            history.nodes["question"] = HistoryNode(id: "question", childrenIds: targets.map(\.messageID),
                                                   role: .user, content: "Describe a paper fold.", models: targets.map(\.modelID))
            for target in targets {
                history.nodes[target.messageID] = HistoryNode(id: target.messageID, parentId: "question",
                    role: .assistant, model: target.modelID, modelIndex: target.modelIndex, done: false)
            }
            history.currentId = "left"
            vm.conversation = Conversation(id: "synthetic-comparison", title: "Paper folds", models: targets.map(\.modelID),
                                           history: history, messages: history.createMessagesList())
            vm.prepareResponseStores(targets: targets, comparison: true)
            return vm
        }
        let vm = fixture()
        let group = vm.responseGroup!
        check(group.stores["left"] !== group.stores["right"], "duplicate models own distinct display stores")
        vm.updateAssistantMessage(id: "right", content: "Right partial.", isStreaming: true)
        check(group.stores["right"]?.content == "Right partial.", "inactive peer receives live content")
        check(vm.conversation?.history.nodes["right"]?.content == "", "tokens do not invalidate the whole history")
        group.accumulators["right"]?.replaceOutput([["type": "message", "content": [["type": "output_text", "text": "Right final."]]]])
        vm.finishComparisonResponse(id: "right", content: "Right final.", succeeded: true,
                                    socketSessionId: "synthetic-session", chatId: "synthetic-comparison")
        await settle()
        check(vm.isStreaming && !vm.hasFinishedStreaming, "one completed response does not end its peer")
        check(group.pending == ["left"], "only the completed ID leaves the pending set")
        check(vm.notified.isEmpty, "partial group completion sends no ready notification")
        check(vm.conversation?.history.nodes["right"]?.content == "Right final.", "inactive completion is committed")
        check(vm.conversation?.history.nodes["right"]?.output.isEmpty == false, "structured final output survives commit")
        let rightPrompt = vm.manager!.completed.first!.1.compactMap { $0["content"] as? String }
        check(rightPrompt == ["Describe a paper fold.", "Right final."], "postprocessing receives the right response's own prompt branch")
        vm.updateAssistantMessage(id: "right", content: "Late wrong text.", isStreaming: true)
        check(vm.conversation?.history.nodes["right"]?.content == "Right final.", "late content cannot reopen a completed peer")
        vm.finishComparisonResponse(id: "right", content: "Repeated final.", succeeded: true)
        check(vm.conversation?.history.nodes["right"]?.content == "Right final.", "duplicate completion is inert")
        group.accumulators["right"]?.append("Late token.")
        check(group.accumulators["right"]?.content == "Right final.", "completed accumulator rejects late socket tokens")
        vm.failResponse(id: "left", content: "Left partial.", error: ChatMessageError(content: "Synthetic provider error"))
        await settle()
        check(!vm.isStreaming && vm.hasFinishedStreaming, "group finishes after success and error both resolve")
        check(vm.conversation?.history.nodes["left"]?.error?.content == "Synthetic provider error", "failure stays on its own response")
        check(vm.notified == ["Right final."], "mixed result produces one ready notification for successful content")
        check(vm.cleanupCount == 0, "comparison completion never invokes single-response cleanup")
        check(vm.conversation?.messages.map(\.id) == ["question", "left"], "completion never concatenates peers into the prompt branch")
        var remoteBranch = vm.conversation!
        remoteBranch.history.currentId = "right"
        remoteBranch.rederiveMessages()
        vm.adoptServerMessages(serverConversation: remoteBranch)
        check(vm.conversation?.history.currentId == "left", "last server finisher does not choose the reader's prompt branch")
        check(vm.conversation?.messages.map(\.id) == ["question", "left"], "metadata sync keeps flat messages on the chosen comparison branch")

        let cancelled = fixture()
        cancelled.responseGroup?.taskIDs = ["task-left", "task-right"]
        cancelled.responseGroup?.accumulators["left"]?.append("Partial left.")
        cancelled.responseGroup?.accumulators["right"]?.append("Partial right.")
        cancelled.updateAssistantMessage(id: "left", content: "Partial left.", isStreaming: true)
        cancelled.updateAssistantMessage(id: "right", content: "Partial right.", isStreaming: true)
        cancelled.stopStreaming()
        await settle()
        check(Set(cancelled.manager!.apiClient.stopped) == ["task-left", "task-right"], "Stop cancels all known server tasks")
        check(cancelled.conversation?.history.nodes["right"]?.content == "Partial right.", "Stop preserves inactive partial content")
        check(cancelled.conversation?.messages.last?.isStreaming == false, "Stop removes the selected response spinner")
        check(cancelled.notified.isEmpty, "cancelled group never announces ready")
        cancelled.finishComparisonResponse(id: "right", content: "Late completion.", succeeded: true)
        check(cancelled.conversation?.history.nodes["right"]?.content == "Partial right.", "late completion after Stop is ignored")

        var request = ChatCompletionRequest(model: "paper-model", messages: [], chatId: "synthetic-comparison", sessionId: "synthetic-session")
        request.responseTargets = targets
        let sending = fixture()
        await sending.submitComparisonRequest(request, group: sending.responseGroup!, chatId: "synthetic-comparison", socketSessionId: "synthetic-session")
        check(sending.manager!.completionRequests.count == 1, "fan-out submits one HTTP request")
        check(sending.responseGroup?.taskIDs == ["task-left", "task-right"], "native plural task IDs are captured")
        check(ChatResponseGroup.taskIDs(from: ["task_id": "legacy-task"]) == ["legacy-task"], "legacy task ID remains supported")
        sending.responseGroup?.cancel()

        let nullable = fixture()
        nullable.manager?.response = ["task_ids": ["task-left", "task-right"], "error": NSNull(), "detail": NSNull()]
        await nullable.submitComparisonRequest(request, group: nullable.responseGroup!, chatId: nil, socketSessionId: "synthetic-session")
        check(nullable.responseGroup?.pending.count == 2, "null error fields do not fail accepted responses")
        nullable.responseGroup?.cancel()

        let failed = fixture()
        failed.manager?.response = ["error": "Synthetic request failure"]
        await failed.submitComparisonRequest(request, group: failed.responseGroup!, chatId: nil, socketSessionId: "synthetic-session")
        await settle()
        check(failed.responseGroup?.pending.isEmpty == true && !failed.isStreaming, "request failure resolves every pending response")
        check(failed.notified.isEmpty, "all-failed group sends no ready notification")

        let detailFailure = fixture()
        detailFailure.manager?.response = ["error": NSNull(), "detail": "Synthetic rejected request"]
        await detailFailure.submitComparisonRequest(request, group: detailFailure.responseGroup!, chatId: nil, socketSessionId: "synthetic-session")
        check(detailFailure.responseGroup?.pending.isEmpty == true, "null error does not hide a real detail error")

        let racing = fixture()
        let old = racing.responseGroup!
        let manager = racing.manager!
        manager.suspendPost = true
        let post = Task { await racing.submitComparisonRequest(request, group: old, chatId: "synthetic-comparison", socketSessionId: "synthetic-session") }
        await settle()
        check(manager.postContinuation != nil, "HTTP request is suspended for the Stop race")
        racing.stopStreaming()
        manager.postContinuation?.resume(returning: ["task_ids": ["late-left", "late-right"]])
        await post.value
        check(Set(manager.apiClient.stopped) == ["late-left", "late-right"], "late HTTP reply cancels only its own returned tasks")
        check(racing.notified.isEmpty, "late HTTP reply does not resurrect cancelled work")

        let changedAccount = fixture()
        let oldManager = changedAccount.manager!
        let oldGroup = changedAccount.responseGroup!
        oldManager.suspendPost = true
        let oldPost = Task { await changedAccount.submitComparisonRequest(request, group: oldGroup, chatId: "synthetic-comparison", socketSessionId: "synthetic-session") }
        await settle()
        changedAccount.manager = FixtureManager()
        oldManager.postContinuation?.resume(throwing: URLError(.cancelled))
        await oldPost.value
        check(changedAccount.responseGroup?.pending.count == 2, "old account request failure cannot mutate current view state")
        oldGroup.cancel()

        let recovering = fixture()
        var saved = recovering.conversation!
        saved.history.nodes["right"]?.content = "Recovered right."
        saved.history.nodes["right"]?.done = true
        recovering.manager?.fetched = saved
        await recovering.recoverComparisonGroup(recovering.responseGroup!, chatId: saved.id, socketSessionId: "synthetic-session")
        await settle()
        check(recovering.responseGroup?.pending == ["left"], "recovery completes only the confirmed server response")
        check(recovering.isStreaming && recovering.notified.isEmpty, "recovery of one peer keeps the group running silently")
        check(recovering.conversation?.history.nodes["right"]?.content == "Recovered right.", "recovery finds a response outside the selected branch")
        recovering.manager?.afterFetch = { recovering.responseGroup?.lastActivity["left"] = .now.addingTimeInterval(1) }
        saved.history.nodes["left"]?.content = "Stale fetched text."
        saved.history.nodes["left"]?.done = true
        recovering.manager?.fetched = saved
        await recovering.recoverComparisonGroup(recovering.responseGroup!, chatId: saved.id, socketSessionId: "synthetic-session")
        check(recovering.responseGroup?.pending == ["left"], "newer socket activity wins over a stale recovery fetch")
        recovering.stopStreaming()

        let tools = fixture()
        var toolHistory = tools.conversation!
        toolHistory.history.nodes["right"]?.content = "<details type=\"tool_calls\" done=\"false\">Synthetic lookup</details>"
        toolHistory.history.nodes["right"]?.done = true
        tools.manager?.fetched = toolHistory
        await tools.recoverComparisonGroup(tools.responseGroup!, chatId: toolHistory.id, socketSessionId: "synthetic-session")
        check(tools.responseGroup?.pending.contains("right") == true, "legacy tool work is not finished just because model tokens stopped")
        tools.stopStreaming()

        let structured = fixture()
        var outputOnly = structured.conversation!
        outputOnly.history.nodes["right"]?.done = true
        outputOnly.history.nodes["right"]?.output = [["type": "message", "content": [["type": "output_text", "text": "Saved structured answer."]]]]
        structured.manager?.fetched = outputOnly
        await structured.recoverComparisonGroup(structured.responseGroup!, chatId: outputOnly.id, socketSessionId: "synthetic-session")
        check(structured.conversation?.history.nodes["right"]?.content == "Saved structured answer.", "output-only recovery commits reconstructed final text")
        structured.stopStreaming()

        let switching = fixture()
        switching.finishComparisonResponse(id: "left", content: "Original left.", succeeded: true)
        switching.finishComparisonResponse(id: "right", content: "Original right.", succeeded: true)
        let previousGroup = switching.responseGroup!
        let previousSession = switching.streamingSessionId
        switching.prepareResponseStores(targets: [targets[1]], comparison: true, prefixes: ["right": "Original right."])
        check(previousGroup.cancelled && switching.streamingSessionId > previousSession, "new continuation invalidates old group's callbacks")
        check(switching.streamingStore(for: "right").content == "Original right.", "comparison continuation begins after existing text")
        check(switching.conversation?.history.nodes["right"]?.done == false, "continued node is saved as in progress")
        switching.prepareResponseStores(targets: [targets[0]], comparison: false)
        check(switching.responseGroup == nil && switching.streamingStore.isActive, "ordinary response clears completed comparison state")

        let regenerating = fixture()
        regenerating.finishComparisonResponse(id: "left", content: "Original left.", succeeded: true)
        regenerating.finishComparisonResponse(id: "right", content: "Original right.", succeeded: true)
        await regenerating.regenerateResponse(messageId: "right")
        await regenerating.streamingTask?.value
        let regenerationRequest = regenerating.manager!.completionRequests.last!
        check(regenerationRequest.responseTargets?.count == 1, "regeneration submits only its target column")
        let regenerated = regenerationRequest.responseTargets!.first!
        check(regenerated.modelID == "paper-model" && regenerated.modelIndex == 1, "regeneration keeps column model instead of current primary picker")
        check(regenerating.conversation?.history.nodes[regenerated.messageID]?.modelIndex == 1, "new regeneration node keeps its comparison index")
        check(regenerating.conversation?.history.nodes["left"]?.content == "Original left.", "regeneration leaves other columns intact")
        check(regenerating.registeredTargets?.first?.messageID == regenerated.messageID, "regeneration registers exact target before sending")
        regenerating.finishComparisonResponse(id: regenerated.messageID, content: "Regenerated right.", succeeded: true)
        await regenerating.continueLastResponse()
        await regenerating.streamingTask?.value
        let continuationRequest = regenerating.manager!.completionRequests.last!
        check(continuationRequest.assistantMessageId == regenerated.messageID, "Continue reuses the same assistant node")
        check(continuationRequest.responseTargets?.first?.modelIndex == 1, "Continue sends the original nonzero column")
        check(continuationRequest.userMessage?["models"] as? [String] == ["paper-model", "paper-model"], "Continue preserves all parent model slots")
        check(regenerating.streamingStore(for: regenerated.messageID).content == "Regenerated right.", "Continue displays the prefix without re-streaming it")
        check(regenerating.responseGroup?.accumulators[regenerated.messageID]?.content == "Regenerated right.", "Continue seeds its own response accumulator")
        regenerating.stopStreaming()

        let defaults = fixture()
        defaults.availableModels = [
            .init(id: "different-primary", rawModelItem: ["id": "different-primary", "info": ["params": ["system": "Use blue paper."]]],
                  filterIds: ["blue-filter"], functionCallingMode: "native"),
            .init(id: "paper-model", rawModelItem: ["id": "paper-model", "info": ["params": ["system": "Use green paper."]]],
                  filterIds: ["green-filter"], functionCallingMode: "native")
        ]
        var ordinaryRequest = ChatCompletionRequest(model: "paper-model", messages: [])
        await defaults.populateCommonRequestFields(&ordinaryRequest)
        check(ordinaryRequest.modelItem?["id"] as? String == "paper-model", "request metadata comes from requested model, not primary picker")
        check(ordinaryRequest.params?["system"] as? String == "Use green paper.", "ordinary request preserves its own workspace system prompt")
        check(ordinaryRequest.filterIds == ["green-filter"], "ordinary request preserves its own filters")
        var batchRequest = ChatCompletionRequest(model: "paper-model", messages: [])
        batchRequest.responseTargets = targets
        await defaults.populateCommonRequestFields(&batchRequest)
        check(batchRequest.params?["system"] == nil, "fan-out does not copy a workspace system prompt to peer models")
        check(batchRequest.params?["function_calling"] == nil && batchRequest.filterIds == nil, "fan-out leaves model-specific tool mode and filters to server")
        var explicit = ChatAdvancedParams()
        explicit.systemPrompt = "Describe folding steps briefly."
        defaults.conversation?.chatParams = explicit
        defaults.selectedToolIds = ["paper-tool"]
        var explicitBatch = ChatCompletionRequest(model: "paper-model", messages: [])
        explicitBatch.responseTargets = targets
        await defaults.populateCommonRequestFields(&explicitBatch)
        check(explicitBatch.params?["system"] as? String == "Describe folding steps briefly.", "explicit chat-level system override still applies to comparisons")
        check(explicitBatch.toolIds == ["paper-tool"], "explicit shared tool selection remains in the request")
        defaults.responseGroup?.cancel()

        let editing = fixture()
        editing.finishComparisonResponse(id: "left", content: "Original left.", succeeded: true)
        editing.finishComparisonResponse(id: "right", content: "Original right.", succeeded: true)
        editing.selectedModelIds = ["paper-model", "paper-model"]
        await editing.editMessage(id: "question", newContent: "Describe a different fold.")
        await editing.streamingTask?.value
        let editRequest = editing.manager!.completionRequests.last!
        check(editRequest.responseTargets?.count == 2, "edited question fans out to every selected model slot")
        check(editRequest.responseTargets?.map(\.modelIndex) == [0, 1], "edited responses preserve ordered duplicate-model columns")
        check(editing.conversation?.history.nodes["question"]?.content == "Describe a paper fold.", "edit preserves original question branch")
        check(editing.conversation?.history.nodes["right"]?.content == "Original right.", "edit preserves original inactive response")
        check(editRequest.userMessage?["models"] as? [String] == ["paper-model", "paper-model"], "edited user node carries full selection to server")
        check(editing.conversation?.messages.count == 2, "edited prompt branch contains only one selected assistant")
        editing.stopStreaming()
        print("\(checks) generation checks passed")
    }
}
