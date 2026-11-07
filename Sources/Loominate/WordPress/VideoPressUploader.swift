import Foundation

struct UploadResult: Equatable {
    let guid: String
    let mediaID: Int
    let shareURL: URL
    var title: String
}

/// Upload token → resumable upload → best-effort title → share link.
struct VideoPressUploader {
    let api: WPComAPI
    let session: URLSession

    func upload(file: URL, title: String, blogID: Int, progress: @escaping (Int64, Int64) -> Void) async throws -> UploadResult {
        var refreshedOnce = false
        while true {
            let jwt = try await api.videoPressUploadToken(blogID: blogID)
            let endpoint = jwt.endpoint(defaultBlogID: blogID)
            let uploader = TusUploader(session: session)
            let filename = Self.sanitizedFilename(title) + ".mp4"
            do {
                let completion = try await uploader.upload(file: file, endpoint: endpoint, token: jwt.uploadToken,
                                                           metadata: [("filename", filename), ("filetype", "video/mp4")],
                                                           progress: progress)
                Log.note("uploaded \(file.lastPathComponent) → guid \(completion.guid) media \(completion.mediaID)")
                do {
                    try await api.setMediaTitle(blogID: blogID, mediaID: completion.mediaID, title: title)
                } catch {
                    Log.note("title update failed (video may still be processing): \(error.localizedDescription)")
                }
                return UploadResult(guid: completion.guid, mediaID: completion.mediaID,
                                    shareURL: WPComConfig.shareURL(guid: completion.guid), title: title)
            } catch WPComError.authExpired where !refreshedOnce {
                // The short-lived upload token may have expired mid-upload; fetch a fresh one and start over.
                refreshedOnce = true
                Log.note("upload token rejected; fetching a fresh one and restarting the upload")
                continue
            }
        }
    }

    static func sanitizedFilename(_ title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Recording" : String(cleaned.prefix(120))
    }
}
