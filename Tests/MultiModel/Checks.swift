import Foundation

// The fixture contains plain text only; image decoding is outside this test.
enum InlineImageStore {
    static func extractAndReplace(content: String) -> String { content }
}

@main struct Checks {
    static func main() throws {
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            guard condition else { print("FAIL: " + label); exit(1) }
            checks += 1
            print("PASS: " + label)
        }
        let source: [String: Any] = [
            "id": "column-two", "role": "assistant", "model": "craft-model",
            "modelIdx": 1, "parentId": "question", "childrenIds": [],
            "content": "Fold the paper in half.", "done": true
        ]
        let restored = MessageHistory.parseNode(id: "column-two", from: source)
        check(restored.toServerDict()["modelIdx"] as? Int == 1,
              "reopening and saving preserves the second model column")
        for index in [0, 1, 2, 12] {
            var column = source
            column["modelIdx"] = index
            let saved = MessageHistory.parseNode(id: "column-two", from: column).toServerDict()
            check(saved["modelIdx"] as? Int == index, "column \(index) survives")
        }
        var legacy = source
        legacy.removeValue(forKey: "modelIdx")
        check(MessageHistory.parseNode(id: "legacy", from: legacy).toServerDict()["modelIdx"] == nil,
              "legacy model-based grouping does not acquire a fabricated column")
        var malformed = source
        malformed["modelIdx"] = "not-an-index"
        check(MessageHistory.parseNode(id: "malformed", from: malformed).toServerDict()["modelIdx"] == nil,
              "malformed index is not silently coerced into a valid column")

        let question = HistoryNode(id: "question", childrenIds: ["left", "right", "right-retry"],
                                   role: .user, content: "Describe a paper fold.",
                                   models: ["craft-model", "craft-model"])
        var tree = MessageHistory()
        tree.nodes["question"] = question
        for (id, index) in [("left", 0), ("right", 1), ("right-retry", 1)] {
            var json = source
            json["id"] = id
            json["modelIdx"] = index
            tree.nodes[id] = MessageHistory.parseNode(id: id, from: json)
        }
        tree.currentId = "right-retry"
        let encoded = try JSONSerialization.data(withJSONObject: tree.toServerDict())
        let dictionary = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        let reopened = MessageHistory.fromServerJSON(dictionary,
            messagesMap: dictionary["messages"] as! [String: [String: Any]],
            currentId: dictionary["currentId"] as? String)
        check(reopened.nodes["left"]?.modelIndex == 0, "duplicate model's first column survives")
        check(reopened.nodes["right"]?.modelIndex == 1, "duplicate model's second column survives")
        check(reopened.nodes["right-retry"]?.modelIndex == 1, "regeneration retains its column")
        check(reopened.nodes["question"]?.models == ["craft-model", "craft-model"],
              "duplicate selections and their order are retained")
        check(reopened.currentId == "right-retry", "active branch is retained")
        check(reopened.createMessagesList().map(\.id) == ["question", "right-retry"],
              "prompt history stays on the active branch, not a concatenation of comparisons")
        check(reopened.nodes["question"]?.childrenIds == ["left", "right", "right-retry"],
              "all sibling responses remain in the saved tree")
        check(reopened.nodes["right"]?.content == source["content"] as? String,
              "inactive response content is preserved")
        check(reopened.nodes["right-retry"]?.done == true, "completion state is preserved")

        var request = ChatCompletionRequest(model: "craft-model", messages: [
            ["role": "user", "content": "Describe a paper fold."]
        ], chatId: "comparison-chat", sessionId: "synthetic-session", messageId: "left", parentId: "question")
        check(request.toJSON()["message_ids"] == nil, "ordinary request shape is unchanged")
        request.responseTargets = []
        check(request.toJSON()["message_ids"] == nil, "empty targets do not request empty fan-out")
        request.responseTargets = [
            .init(modelID: "craft-model", messageID: "left", modelIndex: 0),
            .init(modelID: "craft-model", messageID: "right", modelIndex: 1)
        ]
        let body = request.toJSON()
        let targets = body["message_ids"] as! [[String: Any]]
        check(targets.count == 2, "duplicate models remain distinct request targets")
        check(targets.map { $0["model_id"] as! String } == ["craft-model", "craft-model"],
              "native fan-out carries the requested model in each target")
        check(targets.map { $0["message_id"] as! String } == ["left", "right"],
              "request targets preserve response order and identity")
        check(targets.map { $0["modelIdx"] as! Int } == [0, 1], "native fan-out includes column indices")
        check(body["id"] as? String == "left", "primary response ID remains present")
        check(body["chat_id"] as? String == "comparison-chat" && body["session_id"] as? String == "synthetic-session",
              "chat and socket context remain present")
        check(body["parent_id"] as? String == "question", "one shared user turn remains the parent")
        check(JSONSerialization.isValidJSONObject(body), "fan-out body is valid native JSON")
        request.responseTargets = [.init(modelID: "craft-model", messageID: "right-retry", modelIndex: 1)]
        check((request.toJSON()["message_ids"] as? [[String: Any]])?.first?["modelIdx"] as? Int == 1,
              "single-column regeneration retains a nonzero target index")
        print("\(checks) multi-model contract checks passed")
    }
}
