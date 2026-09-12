import Foundation

extension Array where Element == InstalledModelInfo {
    public func sortedById() -> [InstalledModelInfo] {
        return sorted { $0.id < $1.id }
    }
}

extension Array where Element == RemoteModelInfo {
    public func sortedById() -> [RemoteModelInfo] {
        return sorted { $0.id < $1.id }
    }
}
