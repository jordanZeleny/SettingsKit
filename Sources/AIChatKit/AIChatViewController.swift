import AIProxy
import PhotosUI
import SafariServices
import UIKit
import UniformTypeIdentifiers

/// A configurable, chat-style AI assistant screen. Supply an ``AIChatConfig`` to
/// customize the copy, suggestion tiles, backend, and engine (text chat or image
/// generation). The chat UI, typing/scroll mechanics, and per-assistant history
/// are shared across every app that uses it.
///
/// The package renders text bubbles only. Use ``onAssistantReply`` /
/// ``onImageGenerated`` to react to each turn, and ``appendAssistantView(_:)`` to
/// drop in your own richer result UI (e.g. an image-result bubble).
public final class AIChatViewController: UIViewController, UIScrollViewDelegate {

    // MARK: - Public callbacks

    /// Fired after a `chat` turn completes, with the raw model output and the
    /// displayed (transformed) reply. Parse `raw` to apply structured results.
    public var onAssistantReply: ((_ raw: String, _ displayed: String) -> Void)?

    /// Fired after an `image` turn completes, with the generated image. The
    /// package does not render it; present or insert it however you like (and you
    /// can call ``appendAssistantView(_:)`` to show it inline).
    public var onImageGenerated: ((UIImage) -> Void)?

    /// Fired when the user taps an ``AIChatAction`` whose kind is `.custom`, with
    /// that action's id. Use it for app-specific actions (e.g. show a paywall).
    public var onAction: ((String) -> Void)?

    /// Fired when a result-message action link is tapped, with its id plus the
    /// message's inline image and/or payload — so the host can apply the result
    /// (e.g. "Add to Label", "Open in Editor"). Works for restored messages too.
    public var onResultAction: ((_ id: String, _ image: UIImage?, _ payload: String?) -> Void)?

    // MARK: - Config / AI

    private let config: AIChatConfig
    private let openAIService: OpenAIService

    // MARK: - Chat state

    struct Message: Codable {
        let role: ChatRole
        var text: String
        var imageData: Data?
        var actions: [ArchivedAction]?
        /// User-attached input images (JPEG), resent with every turn so the model
        /// keeps "seeing" them through the conversation.
        var attachmentDatas: [Data]?
    }

    private let chatStore: ChatHistoryStore
    private var conversationID = UUID()
    private var messages: [Message] = []

    /// Optional live "context" image (e.g. the current label sheet) sent to the
    /// model on EVERY chat turn so it can see and edit the current state, not just
    /// what it produced. Evaluated fresh each turn.
    public var contextImageProvider: (() -> UIImage?)?

    /// Optional live text context (e.g. which cell is selected and what each cell
    /// holds) appended to the system prompt on EVERY turn — evaluated fresh so it
    /// always reflects the current state.
    public var contextTextProvider: (() -> String)?

    /// The most recently attached user image in this conversation (decoded), so a
    /// host can place the user's actual photo into a result instead of a generated
    /// one. Nil if the user hasn't attached anything.
    public var latestAttachmentImage: UIImage? {
        for msg in messages.reversed() where msg.role == .user {
            if let data = msg.attachmentDatas?.last, let img = UIImage(data: data) {
                return img
            }
        }
        return nil
    }
    /// Prompt to preload when the next picked image arrives (set when an attach
    /// suggestion tile opens the menu); nil for the input bar's + button.
    private var pendingAttachPrompt: String?
    private var isSending = false
    private var typingIndicator: TypingIndicatorView?
    private var pinToBottom = true

    /// Whether saved sessions should be restored. Image chats don't persist their
    /// generated images, so they always start fresh.
    private var restoresHistory: Bool {
        if case .image = config.engine { return false }
        return true
    }

    // MARK: - Views

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.alwaysBounceVertical = true
        sv.keyboardDismissMode = .interactive
        sv.clipsToBounds = false
        // Highlight controls (suggestion tiles, action buttons) immediately on
        // touch-down instead of waiting for the scroll view to rule out a scroll.
        sv.delaysContentTouches = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.contentInset.bottom = 10
        return sv
    }()

    private let messagesStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = 12
        s.alignment = .fill
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private lazy var inputBar: InputBar = {
        let bar = InputBar(placeholder: config.placeholder)
        bar.onSend = { [weak self] text, attachments in self?.handleSend(text, attachments: attachments) }
        return bar
    }()

    // MARK: - Init

    private let memoryStore: ChatMemoryStore

    public init(config: AIChatConfig) {
        self.config = config
        self.chatStore = ChatHistoryStore(namespace: config.historyNamespace)
        self.memoryStore = ChatMemoryStore(namespace: config.historyNamespace)
        self.openAIService = AIProxy.openAIService(
            partialKey: config.partialKey,
            serviceURL: config.serviceURL
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let closeButton = UIBarButtonItem(
            image: UIImage(systemName: "xmark"), style: .plain,
            target: self, action: #selector(closeTapped))

        var titleConfig = UIButton.Configuration.plain()
        titleConfig.title = config.navigationTitle
        titleConfig.baseForegroundColor = .label
        titleConfig.contentInsets = .zero
        titleConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .systemFont(ofSize: 17, weight: .semibold)
            return out
        }
        let titleButton = UIButton(configuration: titleConfig)
        titleButton.addTarget(self, action: #selector(titleTapped), for: .touchUpInside)
        navigationItem.leftBarButtonItems = [closeButton, .fixedSpace(0), UIBarButtonItem(customView: titleButton)]

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "clock.arrow.circlepath"),
            style: .plain, target: self, action: #selector(showHistory))

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithDefaultBackground()
        navigationItem.standardAppearance = navAppearance
        navigationItem.scrollEdgeAppearance = navAppearance
        navigationItem.compactAppearance = navAppearance

        setupLayout()

        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardDidShow),
            name: UIResponder.keyboardDidShowNotification, object: nil)

        if restoresHistory,
           let saved = chatStore.loadCurrent(),
           Calendar.current.isDateInToday(saved.date), saved.hasUserMessage {
            conversationID = saved.id
            renderConversation(saved.messages)
        } else {
            chatStore.clearCurrent()
            startNewConversation()
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        inputBar.focusTextView()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        inputBar.focusTextView()
    }

    // MARK: - Layout

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if pinToBottom {
            let y = bottomOffsetY()
            if abs(scrollView.contentOffset.y - y) > 0.5 {
                scrollView.contentOffset = CGPoint(x: 0, y: y)
            }
        }
    }

    private func setupLayout() {
        scrollView.delegate = self
        view.addSubview(scrollView)
        scrollView.addSubview(messagesStack)

        inputBar.translatesAutoresizingMaskIntoConstraints = false
        inputBar.setAttachmentMenu(attachmentMenu(prompt: nil))
        view.addSubview(inputBar)

        NSLayoutConstraint.activate([
            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),

            messagesStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            messagesStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            messagesStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            messagesStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            messagesStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])

        let topBlur = ProgressiveBlurView(edge: .top)
        topBlur.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBlur)
        NSLayoutConstraint.activate([
            topBlur.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBlur.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBlur.topAnchor.constraint(equalTo: view.topAnchor, constant: -44),
            topBlur.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
        ])
    }

    // MARK: - Public helpers

    /// Appends an arbitrary view (e.g. a custom image-result bubble) into the
    /// chat, animated in, and scrolls to it. Not persisted to history.
    public func appendAssistantView(_ customView: UIView) {
        customView.alpha = 0
        messagesStack.addArrangedSubview(customView)
        UIView.animate(withDuration: 0.2) { customView.alpha = 1 }
        scrollToBottom()
        DispatchQueue.main.async { [weak self] in self?.scrollToBottom() }
    }

    /// Appends and persists an assistant text bubble.
    public func appendAssistantText(_ text: String) {
        appendMessage(Message(role: .assistant, text: text))
    }

    /// Shows or hides the typing indicator for async work the host runs AFTER a
    /// turn completes (e.g. generating images for a result). Appending any message
    /// clears it automatically.
    public func setPending(_ pending: Bool) {
        if pending { showTypingIndicator() } else { hideTypingIndicator() }
    }

    /// Appends and PERSISTS an assistant "result" message — an optional caption,
    /// an inline image (shown like a chat image, from the assistant side), and
    /// action links beneath it. The image and links re-render on history restore;
    /// taps forward to ``onResultAction`` with the image + payload.
    public func appendAssistantResult(text: String? = nil,
                                      image: UIImage? = nil,
                                      actions: [AIChatResultAction] = []) {
        var msg = Message(role: .assistant, text: text ?? "")
        msg.imageData = image?.pngData()
        msg.actions = actions.isEmpty ? nil : actions.map {
            ArchivedAction(title: $0.title, systemImage: $0.systemImage, id: $0.id, payload: $0.payload)
        }
        appendMessage(msg)
    }

    /// Renders a column of liquid-glass action buttons under the latest message.
    /// `.copy`/`.openURL` are handled here; `.custom` ids forward to `onAction`.
    public func appendActions(_ actions: [AIChatAction]) {
        guard !actions.isEmpty else { return }
        let view = ActionButtonsView(
            actions: actions,
            onOpenURL: { [weak self] url in self?.openURL(url) },
            onCustom: { [weak self] id in self?.onAction?(id) }
        )
        appendAssistantView(view)
    }

    /// Opens web links in an in-app Safari sheet; non-web URLs (mailto, etc.) go
    /// to the system handler.
    private func openURL(_ url: URL) {
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            let safari = SFSafariViewController(url: url)
            present(safari, animated: true)
        } else {
            UIApplication.shared.open(url)
        }
    }

    /// Dismisses the chat, optionally running `completion` afterward.
    public func dismissChat(completion: (() -> Void)? = nil) {
        dismiss(animated: true, completion: completion)
    }

    // MARK: - Actions

    @objc private func closeTapped() { dismiss(animated: true) }

    @objc private func titleTapped() {
        pinToBottom = false
        scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: true)
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        pinToBottom = false
    }

    private func seedIntroMessage() {
        deliverAssistantMessage(config.introMessage, afterTyping: 1.8) { [weak self] in
            self?.deliverSuggestions(afterTyping: 0.54)
        }
    }

    private func deliverSuggestions(afterTyping delay: TimeInterval) {
        guard !config.suggestions.isEmpty else { return }
        showTypingIndicator()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.hideTypingIndicator()
            let grid = self.makeSuggestionGrid()
            grid.alpha = 0
            self.messagesStack.addArrangedSubview(grid)
            Haptics.soft()
            UIView.animate(withDuration: 0.2) { grid.alpha = 1 }
            self.scrollToBottom()
        }
    }

    private func makeSuggestionGrid() -> SuggestionGridView {
        SuggestionGridView(
            items: config.suggestions,
            menuProvider: { [weak self] suggestion in
                guard suggestion.attachesImage else { return nil }
                return self?.attachmentMenu(prompt: suggestion.prompt)
            },
            tapHandler: { [weak self] suggestion in
                self?.inputBar.setText(suggestion.prompt)
            }
        )
    }

    private func deliverAssistantMessage(_ text: String, afterTyping delay: TimeInterval,
                                         completion: (() -> Void)? = nil) {
        showTypingIndicator()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.hideTypingIndicator()
            self.appendMessage(Message(role: .assistant, text: text))
            Haptics.soft()
            completion?()
        }
    }

    // MARK: - Send

    private func handleSend(_ text: String, attachments: [UIImage] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!trimmed.isEmpty || !attachments.isEmpty), !isSending else { return }

        // Persist the attachments on the user message so they're shown (via
        // renderMessage) and resent to the model every turn.
        let attachmentDatas = attachments.compactMap(Self.jpegData(for:))
        var userMessage = Message(role: .user, text: trimmed)
        userMessage.attachmentDatas = attachmentDatas.isEmpty ? nil : attachmentDatas
        if !trimmed.isEmpty || !attachmentDatas.isEmpty {
            appendMessage(userMessage)
        }
        inputBar.clear()
        inputBar.clearAttachments()

        isSending = true
        inputBar.setBusy(true)
        showTypingIndicator()

        switch config.engine {
        case .chat:  runChatTurn(attachments: attachments)
        case .image: runImageTurn(prompt: trimmed)
        }
    }

    private func finishTurn() {
        isSending = false
        inputBar.setBusy(false)
    }

    private func runChatTurn(attachments: [UIImage] = []) {
        let history = messages
        Task { [weak self] in
            guard let self else { return }
            do {
                let rawWithMarkers = try await self.requestChat(history: history)
                // Save any <<remember: …>> facts and strip the markers before display.
                let raw = self.processMemoryMarkers(in: rawWithMarkers)
                let displayed = self.config.replyTransform(raw)
                await MainActor.run {
                    self.hideTypingIndicator()
                    self.appendMessage(Message(role: .assistant, text: displayed.isEmpty ? "Done!" : displayed))
                    Haptics.success()
                    self.onAssistantReply?(raw, displayed)
                    self.finishTurn()
                }
            } catch {
                await MainActor.run { self.failTurn() }
            }
        }
    }

    private func runImageTurn(prompt: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await self.requestImage(prompt: prompt)
                await MainActor.run {
                    self.hideTypingIndicator()
                    Haptics.success()
                    self.onImageGenerated?(image)
                    self.finishTurn()
                }
            } catch {
                await MainActor.run { self.failTurn() }
            }
        }
    }

    private func failTurn() {
        hideTypingIndicator()
        appendMessage(Message(role: .assistant, text: "Something went wrong reaching the assistant. Please check your connection and try again."))
        Haptics.error()
        finishTurn()
    }

    // MARK: - Image attachment (camera / library / files)

    /// The shared Camera / Photos / Files menu used by both the input bar's +
    /// button (prompt == nil) and the image-attach suggestion tiles (prompt set).
    private func attachmentMenu(prompt: String?) -> UIMenu {
        var actions: [UIAction] = []
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            actions.append(UIAction(title: "Camera", image: UIImage(systemName: "camera")) { [weak self] _ in
                self?.pendingAttachPrompt = prompt
                self?.presentCamera()
            })
        }
        actions.append(UIAction(title: "Photos", image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in
            self?.pendingAttachPrompt = prompt
            self?.presentLibrary()
        })
        actions.append(UIAction(title: "Files", image: UIImage(systemName: "folder")) { [weak self] _ in
            self?.pendingAttachPrompt = prompt
            self?.presentFiles()
        })
        return UIMenu(title: "", children: actions)
    }

    private func presentCamera() {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentLibrary() {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentFiles() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    fileprivate func didPickImage(_ image: UIImage) {
        inputBar.addAttachment(image)
        if let prompt = pendingAttachPrompt, !prompt.isEmpty {
            inputBar.setText(prompt)
        }
        pendingAttachPrompt = nil
    }

    /// Scaled JPEG bytes for an attached image — capped so the base64 stays small.
    static func jpegData(for image: UIImage) -> Data? {
        let maxSide: CGFloat = 1280
        let scaled: UIImage
        let longest = max(image.size.width, image.size.height)
        if longest > maxSide {
            let f = maxSide / longest
            let newSize = CGSize(width: image.size.width * f, height: image.size.height * f)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        } else {
            scaled = image
        }
        return scaled.jpegData(compressionQuality: 0.7)
    }

    /// Encodes JPEG data as a data URL for the model's image content part.
    private static func dataURL(forJPEG data: Data) -> URL? {
        URL(string: "data:image/jpeg;base64,\(data.base64EncodedString())")
    }

    /// Encodes an image as a JPEG data URL for the model's image content part.
    private static func dataURL(for image: UIImage) -> URL? {
        guard let data = jpegData(for: image) else { return nil }
        return URL(string: "data:image/jpeg;base64,\(data.base64EncodedString())")
    }

    // MARK: - Memory

    /// Prepends any saved facts and the save-instruction to the system prompt.
    private func systemPromptWithMemory(_ base: String) -> String {
        guard config.remembersInfo else { return base }
        var block = """

        --- Saved info & memory ---
        You can remember reusable details for the user across chats (names, mailing
        addresses, phone numbers, emails, company info, and similar). Only save things
        that are clearly worth reusing — never one-off requests, instructions, or chit-chat.
        To save a fact, put it on its own line anywhere in your reply using EXACTLY:
        <<remember: the fact as a short self-contained line>>
        These markers are stripped before the user sees your reply, so also phrase your
        normal reply naturally. Save each distinct fact on its own marker line.
        """
        let facts = memoryStore.facts
        if !facts.isEmpty {
            block += "\n\nAlready saved (reuse these when relevant; don't re-save them):\n"
            block += facts.map { "- \($0)" }.joined(separator: "\n")
        }
        return base + "\n" + block
    }

    /// Extracts `<<remember: …>>` markers, saves them, and returns the reply with the
    /// markers removed for display.
    private func processMemoryMarkers(in raw: String) -> String {
        guard config.remembersInfo else { return raw }
        let pattern = "<<\\s*remember\\s*:(.*?)>>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return raw }
        let ns = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return raw }
        let facts = matches.map { ns.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines) }
        memoryStore.add(facts)
        // Strip the markers, then tidy up any leftover blank lines.
        let stripped = regex.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        return stripped.replacingOccurrences(of: "\n\n\n", with: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - AI requests

    private func requestChat(history: [Message]) async throws -> String {
        guard case let .chat(systemPrompt, model, reasoning, verbosity) = config.engine else { return "" }

        var prompt = systemPromptWithMemory(systemPrompt)
        if let ctx = contextTextProvider?(), !ctx.isEmpty {
            prompt += "\n\n--- Current state (live, this turn) ---\n" + ctx
        }
        var apiMessages: [OpenAIChatCompletionRequestBody.Message] = [
            .system(content: .text(prompt))
        ]
        // Send the host's live context image (e.g. the current sheet) every turn so
        // the model can view and edit the CURRENT state, not just what it produced.
        if let img = contextImageProvider?(), let data = Self.jpegData(for: img),
           let url = Self.dataURL(forJPEG: data) {
            apiMessages.append(.user(content: .parts([
                .text("This image is the CURRENT state of the user's label sheet. When they ask for edits, base them on what you see here."),
                .imageURL(url),
            ])))
        }
        for msg in history {
            switch msg.role {
            case .user:
                // Include every image the user attached to this message (resent each
                // turn so the model keeps seeing them), as image content parts.
                let urls = (msg.attachmentDatas ?? []).compactMap(Self.dataURL(forJPEG:))
                if urls.isEmpty {
                    apiMessages.append(.user(content: .text(msg.text)))
                } else {
                    apiMessages.append(.user(content: .parts(
                        [.text(msg.text)] + urls.map { .imageURL($0) }
                    )))
                }
            case .assistant:
                apiMessages.append(.assistant(content: .text(msg.text)))
            }
        }

        var accumulated = ""
        let stream = try await openAIService.streamingChatCompletionRequest(
            body: OpenAIChatCompletionRequestBody(
                model: model,
                messages: apiMessages,
                reasoningEffort: reasoning,
                verbosity: verbosity
            )
        )
        for try await chunk in stream {
            if let content = chunk.choices.first?.delta.content {
                accumulated.append(content)
            }
        }
        return accumulated
    }

    /// Generates a transparent PNG from `prompt` using the image model, regardless
    /// of the configured engine — for assistants that compose generated images into
    /// a richer result (e.g. AI label designs).
    public func generateImage(prompt: String, size: String = "1024x1024") async throws -> UIImage {
        let body = OpenAICreateImageRequestBody(
            prompt: prompt,
            background: .transparent,
            model: .gptImage1,
            outputFormat: .png,
            quality: .medium,
            size: size
        )
        let response = try await openAIService.createImageRequest(body: body, secondsToWait: 120)
        guard let b64 = response.data.first?.b64JSON,
              let data = Data(base64Encoded: b64),
              let image = UIImage(data: data) else {
            throw NSError(domain: "AIChatKit", code: -1)
        }
        return image
    }

    private func requestImage(prompt: String) async throws -> UIImage {
        guard case let .image(model, size, background, quality) = config.engine else {
            throw NSError(domain: "AIChatKit", code: -2)
        }
        let bg: OpenAICreateImageRequestBody.Background
        switch background {
        case .auto: bg = .auto
        case .opaque: bg = .opaque
        case .transparent: bg = .transparent
        }
        let q: OpenAICreateImageRequestBody.Quality
        switch quality {
        case .auto: q = .auto
        case .high: q = .high
        case .medium: q = .medium
        case .low: q = .low
        }
        let modelEnum = OpenAICreateImageRequestBody.Model(rawValue: model) ?? .gptImage1
        let body = OpenAICreateImageRequestBody(
            prompt: prompt,
            background: bg,
            model: modelEnum,
            outputFormat: .png,
            quality: q,
            size: size
        )
        let response = try await openAIService.createImageRequest(body: body, secondsToWait: 120)
        guard let b64 = response.data.first?.b64JSON,
              let data = Data(base64Encoded: b64),
              let image = UIImage(data: data) else {
            throw NSError(domain: "AIChatKit", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No image data returned"])
        }
        return image
    }

    // MARK: - Chat UI updates

    private func appendMessage(_ msg: Message) {
        hideTypingIndicator()   // a result/message replaces any pending indicator
        messages.append(msg)
        renderMessage(msg)
        persist()
        scrollToBottom()
        DispatchQueue.main.async { [weak self] in self?.scrollToBottom() }
    }

    /// Renders a message's bubble + optional inline image + optional action links.
    private func renderMessage(_ msg: Message) {
        // User-attached input images appear above the text bubble.
        for data in msg.attachmentDatas ?? [] {
            if let img = UIImage(data: data) {
                messagesStack.addArrangedSubview(ChatImageBubble(role: msg.role, image: img))
            }
        }
        if !msg.text.isEmpty {
            messagesStack.addArrangedSubview(ChatBubble(role: msg.role, text: msg.text))
        }
        let image = msg.imageData.flatMap { UIImage(data: $0) }
        if let image {
            messagesStack.addArrangedSubview(ChatImageBubble(role: msg.role, image: image))
        }
        if let actions = msg.actions, !actions.isEmpty {
            messagesStack.addArrangedSubview(makeResultActions(actions, image: image))
        }
    }

    private func makeResultActions(_ actions: [ArchivedAction], image: UIImage?) -> UIView {
        let chatActions = actions.map {
            AIChatAction(title: $0.title, systemImage: $0.systemImage, kind: .custom($0.id))
        }
        return ActionButtonsView(
            actions: chatActions,
            onOpenURL: { [weak self] url in self?.openURL(url) },
            onCustom: { [weak self] id in
                let payload = actions.first { $0.id == id }?.payload
                self?.onResultAction?(id, image, payload)
            })
    }

    // MARK: - Persistence & history

    private func persist() {
        chatStore.saveCurrent(currentConversation())
    }

    private func currentConversation() -> ChatConversation {
        ChatConversation(
            id: conversationID,
            title: conversationTitle(),
            date: Date(),
            messages: messages.map {
                ArchivedMessage(isUser: $0.role == .user, text: $0.text,
                                imageData: $0.imageData, actions: $0.actions,
                                attachmentDatas: $0.attachmentDatas)
            }
        )
    }

    private func conversationTitle() -> String {
        guard let first = messages.first(where: { $0.role == .user })?.text else { return "New chat" }
        let line = first.split(whereSeparator: \.isNewline).first.map(String.init) ?? first
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 40 ? String(trimmed.prefix(40)) + "…" : trimmed
    }

    private func startNewConversation() {
        conversationID = UUID()
        messages.removeAll()
        messagesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        seedIntroMessage()
    }

    private func renderConversation(_ saved: [ArchivedMessage]) {
        messages = saved.map {
            Message(role: $0.isUser ? .user : .assistant, text: $0.text,
                    imageData: $0.imageData, actions: $0.actions,
                    attachmentDatas: $0.attachmentDatas)
        }
        messagesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for msg in messages { renderMessage(msg) }
        if !config.suggestions.isEmpty {
            let grid = makeSuggestionGrid()
            messagesStack.insertArrangedSubview(grid, at: min(1, messagesStack.arrangedSubviews.count))
        }
        pinToBottom = true
        view.layoutIfNeeded()
        scrollView.contentOffset = CGPoint(x: 0, y: bottomOffsetY())
    }

    @objc private func showHistory() {
        let vc = ChatHistoryViewController(conversations: chatStore.history()) { [weak self] convo in
            self?.loadConversation(convo)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func loadConversation(_ convo: ChatConversation) {
        conversationID = convo.id
        renderConversation(convo.messages)
    }

    // MARK: - Typing indicator

    private func showTypingIndicator() {
        guard typingIndicator == nil else { return }
        let indicator = TypingIndicatorView()
        indicator.alpha = 0
        messagesStack.addArrangedSubview(indicator)
        typingIndicator = indicator
        indicator.startAnimating()
        UIView.animate(withDuration: 0.2) { indicator.alpha = 1 }
        scrollToBottom()
    }

    private func hideTypingIndicator() {
        guard let indicator = typingIndicator else { return }
        typingIndicator = nil
        messagesStack.removeArrangedSubview(indicator)
        indicator.removeFromSuperview()
    }

    private func bottomOffsetY() -> CGFloat {
        let inset = scrollView.adjustedContentInset
        let maxY = scrollView.contentSize.height + inset.bottom - scrollView.bounds.height
        return max(-inset.top, maxY)
    }

    private func scrollToBottom(animated: Bool = true) {
        pinToBottom = true
        scrollView.layoutIfNeeded()
        scrollView.setContentOffset(CGPoint(x: 0, y: bottomOffsetY()), animated: animated)
    }

    @objc private func keyboardDidShow() {
        guard pinToBottom else { return }
        view.layoutIfNeeded()
        scrollToBottom(animated: false)
    }
}

// MARK: - Image picker delegates

extension AIChatViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    public func imagePickerController(_ picker: UIImagePickerController,
                                      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        if let image = info[.originalImage] as? UIImage {
            didPickImage(image)
        }
    }

    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        pendingAttachPrompt = nil
    }
}

extension AIChatViewController: PHPickerViewControllerDelegate {
    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else {
            pendingAttachPrompt = nil
            return
        }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else { return }
            DispatchQueue.main.async { self?.didPickImage(image) }
        }
    }
}

extension AIChatViewController: UIDocumentPickerDelegate {
    public func documentPicker(_ controller: UIDocumentPickerViewController,
                               didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { pendingAttachPrompt = nil; return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            didPickImage(image)
        } else {
            pendingAttachPrompt = nil
        }
    }

    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingAttachPrompt = nil
    }
}
