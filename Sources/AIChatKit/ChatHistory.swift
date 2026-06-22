import Foundation

/// A single chat message, stored independently of the VC's private model.
struct ArchivedMessage: Codable {
    let isUser: Bool
    var text: String
}

/// One saved conversation, grouped in the history list by its day.
struct ChatConversation: Codable {
    var id: UUID
    var title: String
    var date: Date
    var messages: [ArchivedMessage]

    var hasUserMessage: Bool { messages.contains { $0.isUser } }
}

/// Stores the in-progress conversation and the archive of past ones for a single
/// assistant, keyed by `namespace` so each assistant is independent.
final class ChatHistoryStore {
    private let currentKey: String
    private let historyKey: String
    private let defaults = UserDefaults.standard

    init(namespace: String) {
        currentKey = namespace + ".current"
        historyKey = namespace + ".history"
    }

    // MARK: Current session

    func loadCurrent() -> ChatConversation? {
        guard let data = defaults.data(forKey: currentKey) else { return nil }
        return try? JSONDecoder().decode(ChatConversation.self, from: data)
    }

    func saveCurrent(_ convo: ChatConversation) {
        if let data = try? JSONEncoder().encode(convo) {
            defaults.set(data, forKey: currentKey)
        }
        upsertHistory(convo)
    }

    func clearCurrent() {
        defaults.removeObject(forKey: currentKey)
    }

    // MARK: History archive

    func history() -> [ChatConversation] {
        guard let data = defaults.data(forKey: historyKey),
              let list = try? JSONDecoder().decode([ChatConversation].self, from: data) else { return [] }
        return list.sorted { $0.date > $1.date }
    }

    func conversation(id: UUID) -> ChatConversation? {
        history().first { $0.id == id }
    }

    private func upsertHistory(_ convo: ChatConversation) {
        guard convo.hasUserMessage else { return }
        var all = history().filter { $0.id != convo.id }
        all.append(convo)
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: historyKey)
        }
    }
}
