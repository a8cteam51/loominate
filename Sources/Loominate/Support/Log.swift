import Foundation
import os

enum Log {
    static let subsystem = "com.automattic.loominate"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let writer = Logger(subsystem: subsystem, category: "writer")
    static let mixdown = Logger(subsystem: subsystem, category: "mixdown")
    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let devices = Logger(subsystem: subsystem, category: "devices")

    /// Plain-text session log at ~/Library/Logs/Loominate/loominate.log, for diagnosing a run
    /// after the fact without the unified log. Keeps the last 512 KB.
    static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Loominate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("loominate.log")
    }()

    private static let fileQueue = DispatchQueue(label: "com.automattic.loominate.log")
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func note(_ message: String) {
        app.notice("\(message)")
        let line = "\(stamp.string(from: Date())) \(message)\n"
        fileQueue.async {
            if let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int, size > 512 * 1024 {
                try? FileManager.default.removeItem(at: fileURL)
            }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                try? handle.close()
            } else {
                try? line.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }
}
