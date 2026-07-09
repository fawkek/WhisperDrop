import Foundation

enum AppFileLog {
    static var logFile: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "WhisperDrop", directoryHint: .isDirectory)
            .appending(path: "Logs", directoryHint: .isDirectory)
        return root.appending(path: "WhisperDrop.log")
    }

    static func write(_ message: String) {
        let line = "\(timestamp()) \(message)\n"
        let data = Data(line.utf8)
        do {
            try FileManager.default.createDirectory(
                at: logFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: logFile.path) {
                let handle = try FileHandle(forWritingTo: logFile)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: logFile, options: .atomic)
            }
        } catch {
            // File logging is diagnostic only. OSLog remains the primary fallback.
        }
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
