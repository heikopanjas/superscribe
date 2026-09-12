import Foundation

/// Per-call configuration passed to a `Transcriber`.
public struct TranscriptionConfig: Sendable, Hashable {
    public let language: String?
    public let prompt: String?

    public init(language: String? = nil, prompt: String? = nil) {
        self.language = language
        self.prompt = prompt
    }

    public func validate() throws -> Void {
        guard self.language?.contains("\0") != true, self.prompt?.contains("\0") != true else { throw InputValidationError("Language and prompt must not contain NUL characters") }
    }
}
