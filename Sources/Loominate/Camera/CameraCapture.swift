import AVFoundation
import CoreVideo

/// Anything that can hand the compositor its most recent camera frame.
protocol CameraFrameSource: AnyObject {
    var latestFrame: CVPixelBuffer? { get }
}

/// One AVCaptureSession feeding both the on-screen preview and the compositor.
final class CameraCapture: NSObject, CameraFrameSource, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.automattic.loominate.camera")
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private(set) var device: AVCaptureDevice?
    private var disconnectObserver: NSObjectProtocol?

    override init() {
        super.init()
        disconnectObserver = NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: nil) { [weak self] note in
            guard let self, let gone = note.object as? AVCaptureDevice, gone.uniqueID == self.device?.uniqueID else { return }
            Log.camera.warning("camera disconnected: \(gone.localizedName)")
            self.lock.lock(); self.latest = nil; self.lock.unlock()
        }
    }

    deinit {
        if let disconnectObserver { NotificationCenter.default.removeObserver(disconnectObserver) }
    }

    var latestFrame: CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    func configure(device: AVCaptureDevice) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        for input in session.inputs { session.removeInput(input) }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw RecordingError.cameraUnavailable(device.localizedName) }
        session.addInput(input)
        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
        if !session.outputs.contains(output) {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddOutput(output) else { throw RecordingError.cameraUnavailable(device.localizedName) }
            session.addOutput(output)
        }
        self.device = device
        lock.lock(); latest = nil; lock.unlock()
        Log.camera.info("camera configured: \(device.localizedName)")
    }

    func start() {
        queue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        lock.lock(); latest = nil; lock.unlock()
    }

    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        return layer
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock(); latest = buffer; lock.unlock()
    }
}
