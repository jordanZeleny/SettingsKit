import Foundation

/// Persists a small set of reusable facts the assistant chose to remember (names,
/// addresses, etc.), keyed per assistant namespace so they can be recalled in later
/// chats. Deliberately tiny and capped — only "worth reusing" info gets saved.
final class ChatMemoryStore {
    private let key: String
    private let defaults = UserDefaults.standard
    private let maxFacts = 60

    init(namespace: String) { self.key = "AIChatKit.memory.\(namespace)" }

    var facts: [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    /// Adds new facts (case-insensitively de-duplicated), keeping the most recent.
    func add(_ newFacts: [String]) {
        let cleaned = newFacts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return }
        var current = facts
        for fact in cleaned where !current.contains(where: { $0.caseInsensitiveCompare(fact) == .orderedSame }) {
            current.append(fact)
        }
        if current.count > maxFacts { current = Array(current.suffix(maxFacts)) }
        defaults.set(current, forKey: key)
    }

    func remove(at index: Int) {
        var current = facts
        guard current.indices.contains(index) else { return }
        current.remove(at: index)
        defaults.set(current, forKey: key)
    }

    func clear() { defaults.removeObject(forKey: key) }
}

/// A persistable action link shown under a result message (e.g. "Add to Label",
/// "Open in Editor"). The behaviour is rebuilt from `id` (+ optional `payload`)
/// when the conversation is restored, so the links survive reloads.
struct ArchivedAction: Codable {
    var title: String
    var systemImage: String?
    var id: String
    var payload: String?
}

/// A single chat message, stored independently of the VC's private model. May
/// carry an inline image and/or action links so rich results persist in history.
struct ArchivedMessage: Codable {
    let isUser: Bool
    var text: String
    var imageData: Data?
    var actions: [ArchivedAction]?
    var attachmentDatas: [Data]?
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
