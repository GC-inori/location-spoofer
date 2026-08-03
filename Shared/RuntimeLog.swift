import Foundation

struct RuntimeLogEntry: Codable, Identifiable, Equatable {
    enum Level: String, Codable {
        case debug
        case info
        case warning
        case error
    }

    let id: UUID
    let timestamp: Date
    let source: String
    let level: Level
    let category: String
    let message: String
    let details: [String: String]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: String,
        level: Level,
        category: String,
        message: String,
        details: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.level = level
        self.category = category
        self.message = message
        self.details = details
    }

    var renderedText: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let suffix = details.isEmpty
            ? ""
            : "  " + details.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: "  ")
        return "\(formatter.string(from: timestamp)) [\(source)] [\(level.rawValue.uppercased())] [\(category)] \(message)\(suffix)"
    }
}

enum RuntimeLogStore {
    private static let lock = NSLock()
    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()
    private static let maximumBytes: UInt64 = 1_500_000

    static func append(_ entry: RuntimeLogEntry) {
        lock.lock()
        defer { lock.unlock() }
        do {
            let url = try logURL(for: entry.source)
            try rotateIfNeeded(url)
            var data = try encoder.encode(entry)
            data.append(0x0A)
            if !FileManager.default.fileExists(atPath: url.path) {
                try data.write(to: url, options: .atomic)
                return
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
            handle.synchronizeFile()
        } catch {
            NSLog("RuntimeLogStore append failed: %@", error.localizedDescription)
        }
    }

    static func loadAll(limit: Int = 800) -> [RuntimeLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        let directory = AppGroup.containerURL.appendingPathComponent("RuntimeLogs", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        let entries = urls
            .filter { $0.pathExtension == "jsonl" }
            .flatMap(readEntries)
            .sorted { $0.timestamp < $1.timestamp }
        return Array(entries.suffix(limit))
    }

    static func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        let directory = AppGroup.containerURL.appendingPathComponent("RuntimeLogs", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    private static func logURL(for source: String) throws -> URL {
        let directory = AppGroup.containerURL.appendingPathComponent("RuntimeLogs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let process = (Bundle.main.bundleIdentifier ?? "unknown-process")
            .replacingOccurrences(of: "/", with: "-")
        let safeSource = source.replacingOccurrences(of: "/", with: "-")
        return directory.appendingPathComponent("\(process)-\(safeSource).jsonl")
    }

    private static func rotateIfNeeded(_ url: URL) throws {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.uint64Value >= maximumBytes else { return }
        let backup = url.deletingPathExtension().appendingPathExtension("previous.jsonl")
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.moveItem(at: url, to: backup)
    }

    private static func readEntries(_ url: URL) -> [RuntimeLogEntry] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard let data = String(line).data(using: .utf8) else { return nil }
            return try? decoder.decode(RuntimeLogEntry.self, from: data)
        }
    }
}

enum RuntimeLogger {
    static func debug(_ source: String, _ category: String, _ message: String, details: [String: String] = [:]) {
        write(.debug, source: source, category: category, message: message, details: details)
    }

    static func info(_ source: String, _ category: String, _ message: String, details: [String: String] = [:]) {
        write(.info, source: source, category: category, message: message, details: details)
    }

    static func warning(_ source: String, _ category: String, _ message: String, details: [String: String] = [:]) {
        write(.warning, source: source, category: category, message: message, details: details)
    }

    static func error(_ source: String, _ category: String, _ message: String, error: Error? = nil, details: [String: String] = [:]) {
        var values = details
        if let error {
            let nsError = error as NSError
            values["error.domain"] = nsError.domain
            values["error.code"] = String(nsError.code)
            values["error.description"] = nsError.localizedDescription
            if !nsError.userInfo.isEmpty {
                values["error.userInfo"] = nsError.userInfo
                    .map { "\($0.key)=\(String(describing: $0.value))" }
                    .sorted()
                    .joined(separator: "; ")
            }
        }
        write(.error, source: source, category: category, message: message, details: values)
    }

    private static func write(_ level: RuntimeLogEntry.Level, source: String, category: String, message: String, details: [String: String]) {
        RuntimeLogStore.append(RuntimeLogEntry(
            source: source,
            level: level,
            category: category,
            message: message,
            details: details
        ))
    }
}
