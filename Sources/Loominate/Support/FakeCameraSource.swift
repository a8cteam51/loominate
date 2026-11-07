import CoreImage
import CoreVideo
import Foundation

/// Synthetic 640x480 camera feed (a moving colour sweep) for testing the bubble without a real camera.
final class FakeCameraSource: CameraFrameSource {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private let timer: DispatchSourceTimer
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var pool: CVPixelBufferPool?
    private var phase: CGFloat = 0

    var latestFrame: CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    init() {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 640,
            kCVPixelBufferHeightKey as String: 480,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.automattic.loominate.fakecamera"))
        timer.schedule(deadline: .now(), repeating: .milliseconds(33))
        timer.setEventHandler { [weak self] in self?.render() }
        timer.resume()
    }

    deinit { timer.cancel() }

    private func render() {
        guard let pool else { return }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return }
        phase += 0.03
        let x = 320 + 200 * cos(phase)
        let y = 240 + 120 * sin(phase)
        let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: x, y: y),
            "inputRadius0": 40,
            "inputRadius1": 260,
            "inputColor0": CIColor(red: 1, green: 0.9, blue: 0.2),
            "inputColor1": CIColor(red: 0.1, green: 0.3, blue: 0.8),
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 640, height: 480))
        context.render(gradient, to: buffer, bounds: CGRect(x: 0, y: 0, width: 640, height: 480), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        lock.lock(); latest = buffer; lock.unlock()
    }
}
