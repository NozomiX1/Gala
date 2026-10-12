import Foundation

/// Wine output of the most recent launches, one folder per game.
public enum LaunchLog {
    static let keepCount = 3

    public static func directory(gameID: UUID, logsDirectory: URL) -> URL {
        logsDirectory.appendingPathComponent(gameID.uuidString)
    }

    /// Returns the path for a new log and deletes all but the newest previous ones.
    public static func newURL(gameID: UUID, logsDirectory: URL, now: Date = Date()) throws -> URL {
        let directory = directory(gameID: gameID, logsDirectory: logsDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for old in logs(in: directory).dropFirst(keepCount - 1) {
            try? FileManager.default.removeItem(at: old)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return directory.appendingPathComponent("\(formatter.string(from: now)).log")
    }

    public static func latest(gameID: UUID, logsDirectory: URL) -> URL? {
        logs(in: directory(gameID: gameID, logsDirectory: logsDirectory)).first
    }

    // File names are timestamps, so name order is time order.
    private static func logs(in directory: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}

/// Cuts a Wine log down to what fits in an issue or a chat message.
public enum LogExcerpt {
    public static func make(_ log: String, tailLines: Int = 40, errorLines: Int = 40) -> String {
        let lines = log.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            .filter { !$0.contains("try_map_free_area") }
        guard lines.count > tailLines else { return lines.joined(separator: "\n") }

        let tail = lines.suffix(tailLines)
        let errors = lines.dropLast(tailLines)
            .filter { $0.contains("err:") || $0.contains("Unhandled exception") }
            .prefix(errorLines)

        var parts: [String] = []
        if !errors.isEmpty {
            parts.append("[earlier error lines]\n" + errors.joined(separator: "\n"))
        }
        parts.append("[last \(tailLines) of \(lines.count) lines]\n" + tail.joined(separator: "\n"))
        return parts.joined(separator: "\n\n")
    }
}
