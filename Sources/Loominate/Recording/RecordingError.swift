import Foundation

enum RecordingError: LocalizedError {
    case cannotAddInput(String)
    case writerFailed(String)
    case notPrepared
    case noVideoTrack
    case mixdownFailed(String)
    case compositorUnavailable
    case cameraUnavailable(String)
    case insufficientDiskSpace
    case streamStopped(Error)

    var errorDescription: String? {
        switch self {
        case .cannotAddInput(let name): return "Could not set up the \(name) track."
        case .writerFailed(let detail): return "Writing the recording failed (\(detail))."
        case .notPrepared: return "The recording was not set up."
        case .noVideoTrack: return "The recording contains no video."
        case .mixdownFailed(let detail): return "Finishing the recording failed (\(detail))."
        case .compositorUnavailable: return "Could not set up the camera bubble."
        case .cameraUnavailable(let name): return "The camera \"\(name)\" could not be started."
        case .insufficientDiskSpace: return "Not enough free disk space to record (need at least 1 GB)."
        case .streamStopped(let error): return "The screen capture stopped: \(error.localizedDescription)"
        }
    }
}
