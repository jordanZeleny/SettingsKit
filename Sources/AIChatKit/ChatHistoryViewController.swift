import UIKit

/// Lists a single assistant's past conversations, grouped into day sections with
/// a short title each. Tapping one hands it back so the chat can reload it.
final class ChatHistoryViewController: UITableViewController {

    private let onSelect: (ChatConversation) -> Void

    private let sections: [(day: Date, convos: [ChatConversation])]

    private static let dayHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.doesRelativeDateFormatting = true
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    init(conversations: [ChatConversation], onSelect: @escaping (ChatConversation) -> Void) {
        self.onSelect = onSelect
        let cal = Calendar.current
        let grouped = Dictionary(grouping: conversations) { cal.startOfDay(for: $0.date) }
        self.sections = grouped
            .map { (day: $0.key, convos: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "History"
        // Pushed onto the chat's navigation stack — the back button handles return.
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.isEmpty ? 1 : sections.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard !sections.isEmpty else { return nil }
        return Self.dayHeaderFormatter.string(from: sections[section].day)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections.isEmpty ? 1 : sections[section].convos.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()

        if sections.isEmpty {
            config.text = "No past chats yet"
            config.textProperties.color = .secondaryLabel
            cell.selectionStyle = .none
            cell.accessoryType = .none
        } else {
            let convo = sections[indexPath.section].convos[indexPath.row]
            config.text = convo.title
            config.secondaryText = Self.timeFormatter.string(from: convo.date)
            config.secondaryTextProperties.color = .secondaryLabel
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator
        }

        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !sections.isEmpty else { return }
        let convo = sections[indexPath.section].convos[indexPath.row]
        onSelect(convo)
        navigationController?.popViewController(animated: true)
    }
}
