import UIKit
import AIProxy

/// Re-exported AIProxy knobs so callers don't need to import AIProxy directly.
public typealias ChatReasoningEffort = OpenAIChatCompletionRequestBody.ReasoningEffort
public typealias ChatVerbosity = OpenAIChatCompletionRequestBody.Verbosity

/// One tap-to-fill starter shown in the 2×2 grid under the welcome message.
public struct AIChatSuggestion {
    public let icon: String       // SF Symbol name
    public let title: String
    public let subtitle: String
    public let prompt: String     // dropped into the input field when tapped

    public init(icon: String, title: String, subtitle: String, prompt: String) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.prompt = prompt
    }
}

/// How a user turn is fulfilled. `chat` streams a text completion; `image`
/// generates an image from the prompt.
public enum AIChatEngine {
    case chat(systemPrompt: String,
              model: String = "gpt-5.2",
              reasoningEffort: ChatReasoningEffort = .high,
              verbosity: ChatVerbosity = .low)

    case image(model: String = "gpt-image-1",
               size: String = "1024x1024",
               background: ImageBackground = .transparent,
               quality: ImageQuality = .medium)

    public enum ImageBackground { case auto, opaque, transparent }
    public enum ImageQuality { case auto, high, medium, low }
}

/// Everything an app customizes about a chat assistant. The copy is fully
/// dynamic per app; the chat UI, mechanics, and history are shared.
public struct AIChatConfig {

    // MARK: Copy
    /// Navigation title (emoji welcome, e.g. "💬 AI Label Assistant").
    public var navigationTitle: String
    /// Input-field placeholder, e.g. "Ask Label Assistant".
    public var placeholder: String
    /// First assistant message, typed in on open.
    public var introMessage: String
    /// The four starter cards shown under the intro (any count works; 4 fills
    /// the 2×2 grid).
    public var suggestions: [AIChatSuggestion]

    // MARK: Backend
    /// AIProxy partial key for this app/service.
    public var partialKey: String
    /// AIProxy service URL for this app/service.
    public var serviceURL: String
    /// Which engine fulfills each turn.
    public var engine: AIChatEngine

    // MARK: Behavior
    /// UserDefaults namespace so each assistant keeps its own history.
    public var historyNamespace: String
    /// Maps raw model output to the text shown in the assistant bubble. Apps that
    /// have the model return JSON can pull out a "reply" field here; the default
    /// strips ``` fences and shows the text as-is. (chat engine only)
    public var replyTransform: (String) -> String

    public init(
        navigationTitle: String,
        placeholder: String,
        introMessage: String,
        suggestions: [AIChatSuggestion],
        partialKey: String,
        serviceURL: String,
        engine: AIChatEngine,
        historyNamespace: String,
        replyTransform: @escaping (String) -> String = AIChatConfig.defaultReplyTransform
    ) {
        self.navigationTitle = navigationTitle
        self.placeholder = placeholder
        self.introMessage = introMessage
        self.suggestions = suggestions
        self.partialKey = partialKey
        self.serviceURL = serviceURL
        self.engine = engine
        self.historyNamespace = historyNamespace
        self.replyTransform = replyTransform
    }

    /// Trims whitespace and ```code fences``` and returns the text unchanged.
    public static func defaultReplyTransform(_ raw: String) -> String {
        raw.replacingOccurrences(of: "```json", with: "")
           .replacingOccurrences(of: "```", with: "")
           .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
