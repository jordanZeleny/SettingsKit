import AIProxy
import UIKit

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

    // MARK: - Config / AI

    private let config: AIChatConfig
    private let openAIService: OpenAIService

    // MARK: - Chat state

    struct Message: Codable {
        let role: ChatRole
        var text: String
    }

    private let chatStore: ChatHistoryStore
    private var conversationID = UUID()
    private var messages: [Message] = []
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
        bar.onSend = { [weak self] text in self?.handleSend(text) }
        return bar
    }()

    // MARK: - Init

    public init(config: AIChatConfig) {
        self.config = config
        self.chatStore = ChatHistoryStore(namespace: config.historyNamespace)
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
        SuggestionGridView(items: config.suggestions) { [weak self] prompt in
            self?.inputBar.setText(prompt)
        }
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

    private func handleSend(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }

        appendMessage(Message(role: .user, text: trimmed))
        inputBar.clear()

        isSending = true
        inputBar.setBusy(true)
        showTypingIndicator()

        switch config.engine {
        case .chat:  runChatTurn()
        case .image: runImageTurn(prompt: trimmed)
        }
    }

    private func finishTurn() {
        isSending = false
        inputBar.setBusy(false)
    }

    private func runChatTurn() {
        let history = messages
        Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await self.requestChat(history: history)
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

    // MARK: - AI requests

    private func requestChat(history: [Message]) async throws -> String {
        guard case let .chat(systemPrompt, model, reasoning, verbosity) = config.engine else { return "" }

        var apiMessages: [OpenAIChatCompletionRequestBody.Message] = [
            .system(content: .text(systemPrompt))
        ]
        for msg in history {
            switch msg.role {
            case .user:      apiMessages.append(.user(content: .text(msg.text)))
            case .assistant: apiMessages.append(.assistant(content: .text(msg.text)))
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
        messages.append(msg)
        messagesStack.addArrangedSubview(ChatBubble(role: msg.role, text: msg.text))
        persist()
        scrollToBottom()
        DispatchQueue.main.async { [weak self] in self?.scrollToBottom() }
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
            messages: messages.map { ArchivedMessage(isUser: $0.role == .user, text: $0.text) }
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
        messages = saved.map { Message(role: $0.isUser ? .user : .assistant, text: $0.text) }
        messagesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for msg in messages {
            messagesStack.addArrangedSubview(ChatBubble(role: msg.role, text: msg.text))
        }
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
        present(UINavigationController(rootViewController: vc), animated: true)
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
