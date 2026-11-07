import AVFoundation
import Foundation

/// `Loominate --probe <file>`: prints what is in a recording without needing ffprobe.
enum Probe {
    static func run(path: String) async {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration).seconds
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
            print("file: \(url.lastPathComponent)")
            print(String(format: "duration: %.2f s   size: %.1f MB   overall: %.0f kbps",
                         duration, Double(size) / 1_000_000, duration > 0 ? Double(size) * 8 / duration / 1000 : 0))
            let tracks = try await asset.load(.tracks)
            for track in tracks {
                let formats = try await track.load(.formatDescriptions)
                let codec = formats.first.map { fourCC($0.mediaSubType.rawValue) } ?? "?"
                let rate = try await track.load(.estimatedDataRate)
                let range = try await track.load(.timeRange)
                var line = "track \(track.trackID) \(track.mediaType.rawValue): \(codec)"
                if track.mediaType == .video {
                    let natural = try await track.load(.naturalSize)
                    let fps = try await track.load(.nominalFrameRate)
                    line += String(format: " %dx%d %.1f fps", Int(natural.width), Int(natural.height), fps)
                } else if let asbd = formats.first?.audioStreamBasicDescription {
                    line += " \(Int(asbd.mSampleRate)) Hz \(asbd.mChannelsPerFrame) ch"
                }
                line += String(format: " %.0f kbps %.2f s", rate / 1000, range.duration.seconds)
                print(line)
            }
        } catch {
            print("probe failed: \(error.localizedDescription)")
        }
    }

    static func fourCC(_ value: FourCharCode) -> String {
        let bytes = [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
        return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "?"
    }
}
