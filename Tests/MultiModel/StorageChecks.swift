import Foundation

enum InlineImageStore {
    static func extractAndReplace(content: String) -> String { content }
}
enum APIError: Error { case responseDecoding(underlying: Error, data: Data) }
enum Method { case post }
final class FixtureNetwork {
    var response: [String: Any] = [:]
    var body: [String: Any] = [:]
    var path = ""
    func requestRaw(path: String, method: Method, body: Data) async throws -> (Data, Int) {
        self.path = path
        self.body = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        return (try JSONSerialization.data(withJSONObject: response), 200)
    }
    func requestVoidJSON(path: String, method: Method, body: [String: Any]) async throws {
        self.path = path
        self.body = body
    }
}
final class APIClient {
    let network = FixtureNetwork()
    // Legacy flat parsing is outside these native-tree storage checks.
    nonisolated func parseSingleMessage(_ json: [String: Any]) -> ChatMessage? {
        let id = json["id"] as? String ?? "synthetic-legacy"
        var history = MessageHistory()
        history.nodes[id] = MessageHistory.parseNode(id: id, from: json)
        history.currentId = id
        return history.createMessagesList().first
    }
    // PRODUCTION_METHODS
}
final class ConversationManager {
    let apiClient: APIClient
    init(_ api: APIClient) { apiClient = api }
    var fetchedConversation: Conversation?
    var onFetch: (() -> Void)?
    func fetchConversation(id: String) async throws -> Conversation {
        let result = fetchedConversation!
        onFetch?()
        return result
    }
    // MANAGER_METHODS
}
final class FixtureStream {
    var streamingMessageId: String?
    var isActive = false
    func appendSources(_ sources: [ChatSourceReference]) {}
    func appendStatus(_ status: ChatStatusUpdate) {}
}
final class MetadataHarness {
    var conversation: Conversation?
    var conversationId: String?
    var manager: ConversationManager?
    let streamingStore = FixtureStream()
    func streamingStore(for id: String) -> FixtureStream { streamingStore }
    var streamingSessionId = 0
    var tasks: [ChatTask] = []
    init(_ conversation: Conversation, manager: ConversationManager) {
        self.conversation = conversation
        self.manager = manager
    }
    // METADATA_METHODS
}
final class SelectionHarness {
    struct Model { let id: String }
    var availableModels = [Model(id: "fallback-model")]
    // SELECTION_METHODS
}
final class EditHarness {
    var conversation: Conversation?
    let manager: ConversationManager
    init(_ conversation: Conversation, api: APIClient) {
        self.conversation = conversation
        self.manager = ConversationManager(api)
    }
    func saveConversationToServer() async { try! await manager.saveConversation(conversation!) }
    // EDITING_METHODS
}
@main struct StorageChecks {
    static func main() async throws {
        var passed = 0
        func check(_ condition: Bool, _ label: String) {
            guard condition else { print("FAIL: " + label); exit(1) }
            passed += 1
            print("PASS: " + label)
        }
        let api = APIClient()
        let models = ["paper-model", "paper-model", "fold-model"]
        var nodes: [String: [String: Any]] = [
            "question": ["id": "question", "role": "user", "content": "Describe a paper fold.", "models": models,
                         "childrenIds": ["first", "second", "third"]],
            "first": ["id": "first", "role": "assistant", "content": "Fold the paper once.", "parentId": "question",
                      "model": models[0], "modelIdx": 0, "done": true],
            "second": ["id": "second", "role": "assistant", "content": "Make one straight crease.", "parentId": "question",
                       "model": models[1], "modelIdx": 1, "done": true],
            "third": ["id": "third", "role": "assistant", "content": "Align the two corners.", "parentId": "question",
                      "model": models[2], "modelIdx": 2, "done": true]
        ]
        for id in ["first", "second", "third"] {
            let content = nodes[id]!["content"]!
            nodes[id]?["output"] = [["type": "message", "role": "assistant",
                                    "content": [["type": "output_text", "text": content]]]]
        }
        let json: [String: Any] = ["id": "synthetic-comparison", "chat": [
            "title": "Paper folding", "models": models,
            "history": ["messages": nodes, "currentId": "second"],
            "params": ["temperature": 0.4]
        ]]
        var conversation = api.parseFullConversation(json)
        let selection = SelectionHarness()
        selection.restoreModelSelection(from: conversation)
        check(selection.selectedModelIds == models, "view model restores all native selections")
        check(selection.selectedModelId == models[0], "primary model remains the first comparison slot")
        selection.selectedModelId = "single-model"
        check(selection.selectedModelIds == ["single-model"], "legacy explicit model assignment selects a single slot")
        selection.restoreModelSelection(from: conversation)
        check(selection.selectedModelIds == models, "offline/online restoration uses the same complete model list")
        var noSelection = conversation
        noSelection.models = []
        selection.restoreModelSelection(from: noSelection)
        check(selection.selectedModelIds == ["paper-model"], "history model is fallback only when native selection is absent")
        noSelection.models = ["stale-single-model"]
        selection.restoreModelSelection(from: noSelection)
        check(selection.selectedModelIds == ["paper-model"], "single-model chats retain their existing last-used-model behavior")
        selection.selectedModelId = nil
        selection.restoreModelSelection(from: Conversation(title: "Empty synthetic chat"))
        check(selection.selectedModelId == "fallback-model", "empty legacy chat can still use an available model")
        try await api.saveFixture(conversation)
        var chat = api.network.body["chat"] as! [String: Any]
        check(chat["models"] as? [String] == models, "load/save preserves ordered and duplicate model slots")
        check(conversation.model == "paper-model", "single-model accessor uses the first slot")
        check(conversation.messages.map(\.id) == ["question", "second"], "prompt branch remains singular")
        let history = chat["history"] as! [String: Any]
        let savedNodes = history["messages"] as! [String: [String: Any]]
        check(savedNodes.count == 4, "saving includes inactive comparison responses")
        check(savedNodes["second"]?["modelIdx"] as? Int == 1, "saving retains duplicate-model column identity")
        check((chat["params"] as? [String: Any])?["temperature"] as? Double == 0.4, "chat params survive")
        check((chat["messages"] as? [[String: Any]])?.last?["modelIdx"] as? Int == 1, "flat compatibility projection preserves column identity")

        api.network.response = json
        let recreated = try await api.createFixture(conversation)
        chat = api.network.body["chat"] as! [String: Any]
        check(chat["models"] as? [String] == models, "saving a temporary comparison retains selections")
        check((chat["messages"] as? [[String: Any]])?.last?["modelIdx"] as? Int == 1, "temporary save retains current column")
        check((chat["messages"] as? [[String: Any]])?.first?["models"] as? [String] == models, "temporary save retains turn selections")
        try await api.saveFixture(recreated)
        check((api.network.body["chat"] as? [String: Any])?["models"] as? [String] == models, "reopening saved temporary chat retains all selections")
        _ = try await api.createEmptyFixture(conversation)
        check((api.network.body["chat"] as? [String: Any])?["models"] as? [String] == models, "precreated empty chat keeps all model slots")
        check(api.network.path == "/api/v1/chats/new", "precreation uses native chat endpoint")

        try await api.saveFlatFixture(conversation)
        chat = api.network.body["chat"] as! [String: Any]
        check(chat["models"] as? [String] == models, "legacy flat sync preserves selected model list")
        check((chat["messages"] as? [[String: Any]])?.last?["modelIdx"] == nil, "flat fallback does not invent a column index it cannot know")

        let manager = ConversationManager(api)
        try await manager.saveConversation(conversation)
        chat = api.network.body["chat"] as! [String: Any]
        check(chat["models"] as? [String] == models, "manager passes complete selection when saving")
        let managerTree = (chat["history"] as! [String: Any])["messages"] as! [String: [String: Any]]
        check(managerTree["third"]?["modelIdx"] as? Int == 2, "manager saves populated tree without dropping inactive columns")
        let editor = EditHarness(conversation, api: api)
        await editor.saveAssistantMessageContent(id: "second", newContent: "Make one neat diagonal crease.")
        let edited = api.parseFullConversation(["id": conversation.id, "chat": api.network.body["chat"]!])
        check(edited.history.nodes["second"]?.content == "Make one neat diagonal crease.", "editing a comparison survives structured-output reconstruction")
        check(edited.history.nodes["first"]?.output.isEmpty == false, "editing one response preserves peer structured output")
        check(edited.history.nodes["third"]?.content == "Align the two corners.", "editing preserves inactive response content")
        check(edited.history.nodes["second"]?.modelIndex == 1, "editing preserves target column identity")

        let metadata = MetadataHarness(conversation, manager: manager)
        let citation = ChatSourceReference(id: "paper-source", title: "Paper guide", url: "https://example.com/folding")
        metadata.appendSources(id: "first", sources: [citation, citation])
        check(metadata.conversation?.history.nodes["first"]?.sources.count == 1, "inactive column receives citations exactly once")
        metadata.appendStatusUpdate(id: "first", status: ChatStatusUpdate(action: "search", description: "Searching", done: false))
        metadata.appendStatusUpdate(id: "first", status: ChatStatusUpdate(action: "search", description: "Searched", done: true))
        metadata.appendStatusUpdate(id: "first", status: ChatStatusUpdate(action: "search", description: "Searched", done: true))
        check(metadata.conversation?.history.nodes["first"]?.statusHistory.count == 1, "inactive column replaces pending status without duplicates")
        check(metadata.conversation?.history.nodes["first"]?.statusHistory.first?.done == true, "inactive column stores completed status")
        metadata.appendFollowUps(id: "first", followUps: ["Try another fold?"])
        check(metadata.conversation?.history.nodes["first"]?.followUps == ["Try another fold?"], "inactive column stores its own follow-ups")
        check(metadata.conversation?.history.nodes["second"]?.followUps.isEmpty == true, "follow-ups do not leak into duplicate-model peer")
        check(metadata.conversation?.messages.map(\.id) == ["question", "second"], "metadata does not change the prompt branch")
        metadata.appendSources(id: "second", sources: [citation])
        metadata.appendStatusUpdate(id: "second", status: ChatStatusUpdate(action: "lookup", done: false))
        check(metadata.conversation?.messages.last?.sources.count == 1, "active column keeps visible citations")
        check(metadata.conversation?.history.nodes["second"]?.sources.count == 1, "active citations survive branch changes")
        check(metadata.conversation?.history.nodes["second"]?.statusHistory.count == 1, "active status survives branch changes")
        metadata.appendSources(id: "missing", sources: [citation])
        metadata.appendStatusUpdate(id: "missing", status: ChatStatusUpdate(action: "lookup"))
        check(metadata.conversation?.history.nodes["missing"] == nil, "unknown metadata never fabricates a message")

        var fetched = conversation
        fetched.history.nodes["first"]?.content = "Fold slowly, then flatten."
        fetched.history.nodes["first"]?.output = [["type": "message", "content": [["type": "output_text", "text": "Fold slowly, then flatten."]]]]
        fetched.history.nodes["first"]?.files = [ChatMessageFile(type: "file", url: "synthetic-file", name: "folding.txt")]
        fetched.history.nodes["first"]?.usage = ["completion_tokens": 7]
        fetched.history.nodes["first"]?.embeds = ["<p>Synthetic fold preview</p>"]
        manager.fetchedConversation = fetched
        try await metadata.refreshConversationMetadata(chatId: conversation.id, assistantMessageId: "first")
        check(metadata.conversation?.history.nodes["first"]?.content == "Fold slowly, then flatten.", "refresh reads inactive response by exact tree ID")
        check(metadata.conversation?.history.nodes["first"]?.files.first?.name == "folding.txt", "inactive file metadata is retained")
        check(metadata.conversation?.history.nodes["first"]?.usage?["completion_tokens"] as? Int == 7, "inactive usage is retained")
        check(metadata.conversation?.history.nodes["first"]?.embeds == ["<p>Synthetic fold preview</p>"], "inactive embeds are retained")
        let refreshedOutput = metadata.conversation!.history.nodes["first"]!.output
        check(MessageHistory.reconstructContentFromOutput(refreshedOutput) == "Fold slowly, then flatten.", "refreshed content and structured snapshot agree")
        check(metadata.conversation?.messages.last?.content == "Make one straight crease.", "peer refresh does not overwrite selected response")
        try await manager.saveConversation(metadata.conversation!)
        let savedMetadata = api.parseFullConversation(["id": conversation.id, "chat": api.network.body["chat"]!])
        // Embed serialization belongs to the already-ported #300, not this change.
        check(savedMetadata.history.nodes["first"]?.sources.count == 1, "inactive citations survive save and reopen")
        check(savedMetadata.history.nodes["first"]?.files.first?.name == "folding.txt", "inactive attachments survive save and reopen")

        let navigated = Conversation(id: "another-synthetic-chat", title: "Other synthetic chat")
        manager.onFetch = { metadata.conversation = navigated }
        try await metadata.refreshConversationMetadata(chatId: conversation.id, assistantMessageId: "first")
        check(metadata.conversation?.title == "Other synthetic chat", "late refresh cannot rename a different chat")
        metadata.conversation = conversation
        manager.onFetch = { metadata.manager = ConversationManager(APIClient()) }
        try await metadata.refreshConversationMetadata(chatId: conversation.id, assistantMessageId: "first")
        check(metadata.conversation?.history.nodes["first"]?.content == "Fold the paper once.", "late refresh cannot cross an account manager change")
        metadata.manager = manager
        manager.onFetch = { metadata.streamingSessionId += 1 }
        try await metadata.refreshConversationMetadata(chatId: conversation.id, assistantMessageId: "first")
        check(metadata.conversation?.history.nodes["first"]?.content == "Fold the paper once.", "old completion refresh cannot overwrite a newer generation")
        manager.onFetch = {
            metadata.conversation?.history.nodes["first"]?.content = "Locally edited synthetic answer."
            metadata.conversation?.history.nodes["first"]?.output = []
        }
        try await metadata.refreshConversationMetadata(chatId: conversation.id, assistantMessageId: "first")
        check(metadata.conversation?.history.nodes["first"]?.content == "Locally edited synthetic answer.", "refresh cannot erase an edit made during the request")
        check(metadata.conversation?.history.nodes["first"]?.output.isEmpty == true, "stale output cannot resurrect the pre-edit text")
        manager.onFetch = nil

        let summary = api.parseConversationSummary(json)!
        try await api.saveFixture(summary)
        check((api.network.body["chat"] as? [String: Any])?["models"] as? [String] == models, "summary parsing retains model list")

        let folder = api.parseFolderChatItem(json, folderId: "synthetic-folder")!
        try await api.saveFixture(folder)
        check((api.network.body["chat"] as? [String: Any])?["models"] as? [String] == models, "folder parsing preserves selections")

        conversation.model = "single-model"
        try await api.saveFixture(conversation)
        check((api.network.body["chat"] as? [String: Any])?["models"] as? [String] == ["single-model"], "explicit legacy single selection replaces comparison list")
        conversation.model = nil
        try await api.saveFixture(conversation)
        check((api.network.body["chat"] as? [String: Any])?["models"] as? [String] == [], "clearing model does not retain stale comparison selections")

        let single = Conversation(title: "Synthetic single", model: "paper-model")
        try await api.saveFixture(single)
        check((api.network.body["chat"] as? [String: Any])?["models"] as? [String] == ["paper-model"], "existing single-model initializer stays compatible")
        try await manager.saveConversation(single)
        check((api.network.body["chat"] as? [String: Any])?["models"] as? [String] == ["paper-model"], "manager supports unpopulated legacy history")
        print("\(passed) storage checks passed")
    }
}
