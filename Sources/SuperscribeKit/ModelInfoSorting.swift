import Foundation

extension Array where Element == InstalledModelInfo {
    public func sortedById() -> [InstalledModelInfo] {
        sorted { $0.id < $1.id }
    }
}

extension Array where Element == RemoteModelInfo {
    public func sortedById() -> [RemoteModelInfo] {
        sorted { $0.id < $1.id }
    }
}
