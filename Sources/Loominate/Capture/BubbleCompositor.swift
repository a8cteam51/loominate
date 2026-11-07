import CoreImage
import CoreVideo

/// Draws the circular camera bubble onto each screen frame before encoding.
final class BubbleCompositor {
    let width: Int
    let height: Int
    private let diameter: CGFloat
    private let ringWidth: CGFloat = 3
    private let origin: CGPoint   // bottom-left of the bubble's bounding square, Core Image coords
    private let context: CIContext
    private let pool: CVPixelBufferPool
    private let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    private let ring: CIImage
    private let mask: CIImage

    init(width: Int, height: Int, size: BubbleSize, corner: BubbleCorner, insets: BubbleInsets = .zero) throws {
        self.width = width
        self.height = height
        diameter = (CGFloat(height) * size.fraction).rounded(.down)
        let margin = (diameter * BubbleInsets.marginFraction).rounded()
        let w = CGFloat(width), h = CGFloat(height)
        switch corner {
        case .bottomLeft: origin = CGPoint(x: margin + insets.left, y: margin + insets.bottom)
        case .bottomRight: origin = CGPoint(x: w - diameter - margin - insets.right, y: margin + insets.bottom)
        case .topLeft: origin = CGPoint(x: margin + insets.left, y: h - diameter - margin - insets.top)
        case .topRight: origin = CGPoint(x: w - diameter - margin - insets.right, y: h - diameter - margin - insets.top)
        }
        context = CIContext(options: [.cacheIntermediates: false])

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        guard status == kCVReturnSuccess, let pool else { throw RecordingError.compositorUnavailable }
        self.pool = pool

        let center = CGPoint(x: origin.x + diameter / 2, y: origin.y + diameter / 2)
        let radius = diameter / 2
        ring = Self.disc(center: center, radius: radius + ringWidth, color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        mask = Self.disc(center: center, radius: radius, color: CIColor.white)
    }

    /// Returns a new BGRA buffer with the bubble drawn, or the screen frame alone when no camera frame exists.
    func compose(screen: CVPixelBuffer, camera: CVPixelBuffer?) -> CVPixelBuffer? {
        var output: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) == kCVReturnSuccess, let output else { return nil }

        var image = CIImage(cvPixelBuffer: screen)
        if image.extent.width != CGFloat(width) || image.extent.height != CGFloat(height) {
            image = image.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / image.extent.width,
                                                            y: CGFloat(height) / image.extent.height))
        }
        if let camera {
            let bubble = bubbleImage(from: camera)
            image = bubble.composited(over: ring).composited(over: image)
        }
        context.render(image, to: output, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: outputColorSpace)
        return output
    }

    private func bubbleImage(from camera: CVPixelBuffer) -> CIImage {
        var cam = CIImage(cvPixelBuffer: camera)
        // Mirror like a selfie preview.
        cam = cam.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -cam.extent.width, y: 0))
        // Aspect-fill crop to a centred square.
        let side = min(cam.extent.width, cam.extent.height)
        let crop = CGRect(x: cam.extent.midX - side / 2, y: cam.extent.midY - side / 2, width: side, height: side)
        cam = cam.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        // Scale to the bubble and move into place.
        let scale = diameter / side
        cam = cam.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        cam = cam.transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))
        // Keep only the disc.
        let masked = cam.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: mask,
        ])
        return masked.cropped(to: CGRect(x: origin.x, y: origin.y, width: diameter, height: diameter))
    }

    private static func disc(center: CGPoint, radius: CGFloat, color: CIColor) -> CIImage {
        let filter = CIFilter(name: "CIRadialGradient")!
        filter.setValue(CIVector(x: center.x, y: center.y), forKey: "inputCenter")
        filter.setValue(radius - 0.75, forKey: "inputRadius0")
        filter.setValue(radius + 0.75, forKey: "inputRadius1")
        filter.setValue(color, forKey: "inputColor0")
        filter.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor1")
        let bounds = CGRect(x: center.x - radius - 2, y: center.y - radius - 2, width: radius * 2 + 4, height: radius * 2 + 4)
        return filter.outputImage!.cropped(to: bounds)
    }
}
