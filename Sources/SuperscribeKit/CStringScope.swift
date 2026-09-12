/// Keeps optional string storage alive for the complete synchronous C invocation.
internal enum CStringScope {
    internal static func withCString<Result>(_ value: String?, body: (UnsafePointer<CChar>?) throws -> Result) rethrows -> Result {
        if let value {
            return try value.withCString { pointer in return try body(pointer) }
        }
        return try body(nil)
    }
}
