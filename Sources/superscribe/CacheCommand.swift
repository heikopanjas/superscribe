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

    mutating func validate() throws -> Void {
        try assertMutuallyExclusive([
            ("--list", self.list),
            ("--clear", self.clear),
            ("--rm", self.rm != nil)
        ])
        if self.yes == true && self.clear == false {
            throw ValidationError("--yes applies only to --clear.")
        }
    }

    mutating func run() throws -> Void {
        let cache = ConvertedAudioCache()
        if self.list == true {
            try self.runList(cache: cache)
        }
        else if self.clear == true {
            try self.runClear(cache: cache)
        }
        else if let path = self.rm {
            try self.runRemove(path: path, cache: cache)
        }
        else {
            try self.runInfo(cache: cache)
        }
    }

    // MARK: - Verbs

    private func runInfo(cache: ConvertedAudioCache) throws -> Void {
        let (entries, totalBytes) = try self.scanEntries(cache: cache)
        print("Cache location: \(cache.root.path)")
        print("Entries:        \(entries.count)")
        print("Total size:     \(formatBytes(totalBytes))")
    }

    private func runList(cache: ConvertedAudioCache) throws -> Void {
        let (entries, totalBytes) = try self.scanEntries(cache: cache)
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

    private func runClear(cache: ConvertedAudioCache) throws -> Void {
        let (entries, totalBytes) = try self.scanEntries(cache: cache)
        if entries.isEmpty == true {
            print("Cache is already empty.")
            return
        }
        guard
            confirm(
                prompt: "Delete \(entries.count) entry(s) (\(formatBytes(totalBytes))) from \(cache.root.path)? [y/N] ",
                skip: self.yes
            ) == true
        else {
            print("Aborted.")
            return
        }
        try FileManager.default.removeItem(at: cache.root)
        print("Cleared \(entries.count) entry(s) (\(formatBytes(totalBytes))).")
    }

    func runRemove(path: String, cache: ConvertedAudioCache) throws -> Void {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let manifest = try cache.loadManifest()
        var digests = Set(manifest.values.filter { URL(fileURLWithPath: $0.sourcePath).standardizedFileURL.path == url.path }.map(\.digest))
        if let key = cache.key(for: url, targetFormat: .asr16kMono), cache.lookup(key) != nil { digests.insert(key.digest) }
        guard digests.isEmpty == false else {
            print("No cache entry for '\(url.lastPathComponent)'.")
            return
        }
        var total: Int64 = 0
        var removed = 0
        for digest in digests where digest.range(of: "\\A[0-9a-f]{64}\\z", options: .regularExpression) != nil {
            let entryURL = cache.root.appendingPathComponent("\(digest).wav")
            if FileManager.default.fileExists(atPath: entryURL.path) == true {
                total += Int64(try entryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                try FileManager.default.removeItem(at: entryURL)
                removed += 1
            }
            try cache.updateManifest(removingDigest: digest)
        }
        print("Removed \(removed) cache entry(s) for '\(url.lastPathComponent)' (\(formatBytes(total))).")
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
