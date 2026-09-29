import Foundation

/// One native fan-out request. Each response owns its display pipeline; finishing
/// one column never completes the group or clears another column's buffered text.
@MainActor
final class ChatResponseGroup {
    let targets: [ChatCompletionRequest.ResponseTarget]
    let stores: [String: StreamingContentStore]
    let accumulators: [String: ContentAccumulator]
    private(set) var pending: Set<String>
    private(set) var successful: Set<String> = []
    private(set) var cancelled = false
    var taskIDs: Set<String> = []
    var lastActivity: [String: Date] = [:]
    var completionTasks: [Task<Void, Never>] = []
    var recoveryTask: Task<Void, Never>?
    var finished = false

    init(targets: [ChatCompletionRequest.ResponseTarget], prefixes: [String: String] = [:]) {
        self.targets = targets
        pending = Set(targets.map(\.messageID))
        var stores: [String: StreamingContentStore] = [:]
        var accumulators: [String: ContentAccumulator] = [:]
        for target in targets {
            let store = StreamingContentStore()
            store.beginStreamingForContinue(messageId: target.messageID, modelId: target.modelID,
                                            existingContent: prefixes[target.messageID] ?? "")
            stores[target.messageID] = store
            accumulators[target.messageID] = ContentAccumulator()
        }
        self.stores = stores
        self.accumulators = accumulators
    }

    func isReceiving(_ id: String) -> Bool { !cancelled && pending.contains(id) }

    /// Claim before asynchronous finalization so repeated done/error events are inert.
    func complete(_ id: String, succeeded: Bool) -> Bool {
        guard !cancelled, pending.remove(id) != nil else { return false }
        accumulators[id]?.finish()
        if succeeded { successful.insert(id) }
        return true
    }

    func cancel() {
        cancelled = true
        accumulators.values.forEach { $0.finish() }
        pending.removeAll()
        recoveryTask?.cancel()
        recoveryTask = nil
        completionTasks.forEach { $0.cancel() }
        completionTasks.removeAll()
    }

    static func taskIDs(from response: [String: Any]) -> Set<String> {
        var ids = Set(response["task_ids"] as? [String] ?? [])
        if let id = response["task_id"] as? String { ids.insert(id) }
        ids.remove("")
        return ids
    }
}
