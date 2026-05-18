import ArgumentParser
import Foundation
import SuperscribeKit

struct CacheCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cache",
        abstract: "Inspect and prune the converted-audio cache."
    )

    @Flag(name: .long, help: "List cache entries with size and age.")
    var list: Bool = false

    @Flag(name: .long, help: "Delete all cache entries.")
    var clear: Bool = false

    @Option(name: .long, help: "Delete the cache entry for the source file at <path>.")
    var rm: String?

    @Flag(name: .long, help: "Skip confirmation prompt (use with --clear).")
    var yes: Bool = false

    mutating func validate() throws {
        let verbs: [(String, Bool)] = [
            ("--list", list),
            ("--clear", clear),
            ("--rm", rm != nil)
        ]
        let active = verbs.filter(\.1).map(\.0)
        if active.count > 1 {
            throw ValidationError(
                "Only one of \(active.joined(separator: ", ")) may be used at once."
            )
        }
        if yes == true && clear == false {
            throw ValidationError("--yes applies only to --clear.")
        }
    }

    mutating func run() throws {
        let cache = ConvertedAudioCache()
        if list == true {
            try runList(cache: cache)
        }
        else if clear == true {
            try runClear(cache: cache)
        }
        else if let path = rm {
            try runRemove(path: path, cache: cache)
        }
        else {
            try runInfo(cache: cache)
        }
    }

    // MARK: - Verbs

    private func runInfo(cache: ConvertedAudioCache) throws {
        let (entries, totalBytes) = try scanEntries(cache: cache)
        print("Cache location: \(cache.root.path)")
        print("Entries:        \(entries.count)")
        print("Total size:     \(formatBytes(totalBytes))")
    }

    private func runList(cache: ConvertedAudioCache) throws {
        let (entries, totalBytes) = try scanEntries(cache: cache)
        if entries.isEmpty == true {
            print("Cache is empty (\(cache.root.path))")
            return
        }
        let manifest = (try? cache.loadManifest()) ?? [:]
        let now = Date()
        for (url, size, mtime) in entries.sorted(by: { $0.2 > $1.2 }) {
            let digest = url.deletingPathExtension().lastPathComponent
            let age = now.timeIntervalSince(mtime)
            let sizeStr = formatBytes(size).leftPad(toLength: 10)
            let source =
                manifest[digest].map {
                    URL(fileURLWithPath: $0.sourcePath).lastPathComponent
                } ?? "?"
            print("  \(sizeStr)  \(formatAge(age))  \(source)")
        }
        print("\n\(entries.count) entry(s) — \(formatBytes(totalBytes))")
    }

    private func runClear(cache: ConvertedAudioCache) throws {
        let (entries, totalBytes) = try scanEntries(cache: cache)
        if entries.isEmpty == true {
            print("Cache is already empty.")
            return
        }
        if yes == false {
            FileHandle.standardError.write(
                Data(
                    "Delete \(entries.count) entry(s) (\(formatBytes(totalBytes))) from \(cache.root.path)? [y/N] "
                        .utf8
                )
            )
            let answer = readLine(strippingNewline: true)?.lowercased() ?? ""
            guard answer == "y" || answer == "yes" else {
                print("Aborted.")
                return
            }
        }
        try FileManager.default.removeItem(at: cache.root)
        print("Cleared \(entries.count) entry(s) (\(formatBytes(totalBytes))).")
    }

    private func runRemove(path: String, cache: ConvertedAudioCache) throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard let key = cache.key(for: url, targetFormat: .asr16kMono) else {
            print("Cannot read file metadata for '\(url.lastPathComponent)' — no entry deleted.")
            return
        }
        guard let entryURL = cache.lookup(key) else {
            print("No cache entry for '\(url.lastPathComponent)'.")
            return
        }
        let res = try entryURL.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(res.fileSize ?? 0)
        try FileManager.default.removeItem(at: entryURL)
        try? cache.updateManifest(removingDigest: key.digest)
        print("Removed cache entry for '\(url.lastPathComponent)' (\(formatBytes(size))).")
    }

    // MARK: - Helpers

    private func scanEntries(
        cache: ConvertedAudioCache
    ) throws -> (entries: [(URL, Int64, Date)], totalBytes: Int64) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: cache.root.path) == true else { return ([], 0) }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let contents = try fm.contentsOfDirectory(
            at: cache.root,
            includingPropertiesForKeys: Array(keys),
            options: .skipsHiddenFiles
        )
        var entries: [(URL, Int64, Date)] = []
        var total: Int64 = 0
        for url in contents where url.pathExtension == "wav" {
            let res = try url.resourceValues(forKeys: keys)
            guard res.isRegularFile == true else { continue }
            let size = Int64(res.fileSize ?? 0)
            let mtime = res.contentModificationDate ?? Date.distantPast
            entries.append((url, size, mtime))
            total += size
        }
        return (entries, total)
    }
}

private func formatAge(_ seconds: TimeInterval) -> String {
    let s = Int(seconds)
    if s < 60 { return "< 1m ago" }
    if s < 3600 { return "\(s / 60)m ago" }
    if s < 86400 {
        let h = s / 3600
        let m = (s % 3600) / 60
        return m > 0 ? "\(h)h \(m)m ago" : "\(h)h ago"
    }
    let d = s / 86400
    let h = (s % 86400) / 3600
    return h > 0 ? "\(d)d \(h)h ago" : "\(d)d ago"
}
