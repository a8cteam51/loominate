import Foundation

enum OutputLocation {
    struct URLs {
        let temp: URL     // intermediate .mov
        let final: URL    // delivered .mp4
    }

    static func makeURLs(folder: URL, baseName: String? = nil) throws -> URLs {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = baseName ?? defaultBaseName()
        return URLs(temp: folder.appendingPathComponent(name).appendingPathExtension("mov"),
                    final: folder.appendingPathComponent(name).appendingPathExtension("mp4"))
    }

    static func defaultBaseName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Recording \(formatter.string(from: date))"
    }

    static func freeSpace(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    static let minimumFreeBytes: Int64 = 1_000_000_000
}
