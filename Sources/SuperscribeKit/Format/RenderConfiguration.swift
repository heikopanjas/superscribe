import Foundation

public struct RenderConfiguration: Sendable {
    public var format: OutputFormat
    public var overlapPolicy: OverlapPolicy?
    public var gapThreshold: TimeInterval
    public var maxCueDuration: TimeInterval?
    public var maxLineLength: Int?
    public var includeWords: Bool

    public init(
        format: OutputFormat = .vtt, overlapPolicy: OverlapPolicy? = nil, gapThreshold: TimeInterval = 3, maxCueDuration: TimeInterval? = nil, maxLineLength: Int? = nil,
        includeWords: Bool = false
    ) {
        self.format = format
        self.overlapPolicy = overlapPolicy
        self.gapThreshold = gapThreshold
        self.maxCueDuration = maxCueDuration
        self.maxLineLength = maxLineLength
        self.includeWords = includeWords
    }

    public func validate() throws -> Void {
        try self.mergerConfig.validate()
        try Self.validateLineLength(self.maxLineLength)
        if self.format == .txt, self.overlapPolicy == .preserve { throw InputValidationError("TXT supports interleave (default) or trim; preserve cannot represent overlapping speech") }
    }

    internal var mergerConfig: MergerConfig {
        return MergerConfig(overlapPolicy: self.overlapPolicy ?? (self.format == .txt ? .interleave : .preserve), gapThreshold: self.gapThreshold, maxCueDuration: self.maxCueDuration)
    }

    internal static func validateLineLength(_ length: Int?) throws -> Void {
        if let length, length <= 0 { throw InputValidationError("Maximum line length must be positive") }
    }
}
