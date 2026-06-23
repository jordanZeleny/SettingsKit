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
    /// Prompt to send alongside the next picked image (set when an image-attach
    /// suggestion is tapped).
    private var pendingImagePrompt: String?
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
        SuggestionGridView(items: config.suggestions) { [weak self] suggestion in
            guard let self else { return }
            if suggestion.attachesImage {
                self.presentImageSourcePicker(prompt: suggestion.prompt)
            } else {
                self.inputBar.setText(suggestion.prompt)
            }
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

    /// Sends a chat turn that includes a photo (vision). Used by image-attach
    /// suggestion cards.
    private func sendImageTurn(prompt: String, image: UIImage) {
        guard !isSending else { return }
        appendMessage(Message(role: .user, text: prompt))
        isSending = true
        inputBar.setBusy(true)
        showTypingIndicator()
        runChatTurn(attachment: image)
    }

    private func runChatTurn(attachment: UIImage? = nil) {
        let history = messages
        Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await self.requestChat(history: history, attachment: attachment)
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

    private func presentImageSourcePicker(prompt: String) {
        pendingImagePrompt = prompt
        let alert = UIAlertController(title: "Add a Photo",
                                     message: "Choose where to get the image from.",
                                     preferredStyle: .alert)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alert.addAction(UIAlertAction(title: "Take Photo", style: .default) { [weak self] _ in
                self?.presentCamera()
            })
        }
        alert.addAction(UIAlertAction(title: "Photo Library", style: .default) { [weak self] _ in
            self?.presentLibrary()
        })
        alert.addAction(UIAlertAction(title: "Files", style: .default) { [weak self] _ in
            self?.presentFiles()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.pendingImagePrompt = nil
        })
        present(alert, animated: true)
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
        guard let prompt = pendingImagePrompt else { return }
        pendingImagePrompt = nil
        sendImageTurn(prompt: prompt, image: image)
    }

    /// Encodes an image as a JPEG data URL for the model's image content part.
    private static func dataURL(for image: UIImage) -> URL? {
        // Cap the longest side so the base64 payload stays reasonable.
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
        guard let data = scaled.jpegData(compressionQuality: 0.7) else { return nil }
        return URL(string: "data:image/jpeg;base64,\(data.base64EncodedString())")
    }

    // MARK: - AI requests

    private func requestChat(history: [Message], attachment: UIImage? = nil) async throws -> String {
        guard case let .chat(systemPrompt, model, reasoning, verbosity) = config.engine else { return "" }

        var apiMessages: [OpenAIChatCompletionRequestBody.Message] = [
            .system(content: .text(systemPrompt))
        ]
        let attachmentURL = attachment.flatMap(Self.dataURL(for:))
        for (i, msg) in history.enumerated() {
            let isLast = (i == history.count - 1)
            switch msg.role {
            case .user:
                if isLast, let attachmentURL {
                    apiMessages.append(.user(content: .parts([.text(msg.text), .imageURL(attachmentURL)])))
                } else {
                    apiMessages.append(.user(content: .text(msg.text)))
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
        pendingImagePrompt = nil
    }
}

extension AIChatViewController: PHPickerViewControllerDelegate {
    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else {
            pendingImagePrompt = nil
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
        guard let url = urls.first else { pendingImagePrompt = nil; return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            didPickImage(image)
        } else {
            pendingImagePrompt = nil
        }
    }

    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingImagePrompt = nil
    }
}
