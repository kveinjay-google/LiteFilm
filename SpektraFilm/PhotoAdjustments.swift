import CoreGraphics
import CoreImage
import Foundation

private func bounded(_ value: Double, _ range: ClosedRange<Double>, fallback: Double = 0) -> Double {
    value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
}

/// Fractions of the upright, geometrically corrected image, measured from its top-left.
struct PhotoCrop: Codable, Equatable, Hashable, Sendable {
    var x = 0.0
    var y = 0.0
    var width = 1.0
    var height = 1.0

    func sanitized() -> Self {
        let w = bounded(width, 0.05...1, fallback: 1)
        let h = bounded(height, 0.05...1, fallback: 1)
        return Self(x: bounded(x, 0...(1 - w)), y: bounded(y, 0...(1 - h)), width: w, height: h)
    }
}

struct PhotoGeometry: Codable, Equatable, Hashable, Sendable {
    var rotation = 0
    var angle = 0.0
    var vertical = 0.0
    var horizontal = 0.0
    var distortion = 0.0
    var crop = PhotoCrop()

    func sanitized() -> Self {
        Self(rotation: ((rotation % 4) + 4) % 4, angle: bounded(angle, -45...45),
             vertical: bounded(vertical, -1...1), horizontal: bounded(horizontal, -1...1),
             distortion: bounded(distortion, -1...1), crop: crop.sanitized())
    }
}

struct PhotoAdjustments: Codable, Equatable, Hashable, Sendable {
    var highlights = 0.0
    var shadows = 0.0
    var contrast = 0.0
    var saturation = 0.0
    var geometry = PhotoGeometry()

    func sanitized() -> Self {
        Self(highlights: bounded(highlights, -1...1), shadows: bounded(shadows, -1...1),
             contrast: bounded(contrast, -1...1), saturation: bounded(saturation, -1...1),
             geometry: geometry.sanitized())
    }
}

/// Shared preview/export path. Bounded Core Image filters; no source bytes are modified.
enum PhotoProcessor {
    private static let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
    private static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!,
                                                     .cacheIntermediates: false])
    // A monotonic radial map over the bounded coefficient range. Sampling remains inside
    // the original rectangle, so correcting barrel/pincushion distortion cannot expose holes.
    private static let lensKernel = CIWarpKernel(source: """
        kernel vec2 lens(vec2 size, float amount) {
            vec2 p = (destCoord() / size - vec2(0.5)) * 2.0;
            float k = amount * 0.12;
            float scale = max(1.0, 1.0 + 2.0 * k);
            vec2 q = p * (1.0 + k * dot(p, p)) / scale;
            return (q * 0.5 + vec2(0.5)) * size;
        }
        """)

    static func exposure(_ image: CGImage, ev: Double) throws -> CGImage {
        let value = bounded(ev, -2...2)
        guard abs(value) > 0.00001 else { return image }
        let source = CIImage(cgImage: image)
        let output = source.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: value])
        return try raster(output, extent: source.extent)
    }

    static func tone(_ image: CGImage, settings: PhotoAdjustments) throws -> CGImage {
        let s = settings.sanitized()
        guard s.highlights != 0 || s.shadows != 0 || s.contrast != 0 || s.saturation != 0 else { return image }
        var output = CIImage(cgImage: image)
        if s.highlights != 0 || s.shadows != 0 {
            // Five luma anchors give independent bright/dark controls and preserve endpoints.
            // The bounded ranges keep the curve monotonic even at combined extremes.
            let shadowY = 0.25 + s.shadows * 0.14
            let highlightY = 0.75 + s.highlights * 0.14
            output = output.applyingFilter("CIToneCurve", parameters: [
                "inputPoint0": CIVector(x: 0, y: 0),
                "inputPoint1": CIVector(x: 0.25, y: shadowY),
                "inputPoint2": CIVector(x: 0.5, y: 0.5 + (s.shadows + s.highlights) * 0.025),
                "inputPoint3": CIVector(x: 0.75, y: highlightY),
                "inputPoint4": CIVector(x: 1, y: 1)
            ])
        }
        if s.contrast != 0 || s.saturation != 0 {
            output = output.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1 + s.contrast * 0.5,
                kCIInputSaturationKey: 1 + s.saturation
            ])
        }
        return try raster(output, extent: output.extent)
    }

    static func geometry(_ image: CGImage, settings: PhotoGeometry, includeCrop: Bool = true) throws -> CGImage {
        var s = settings.sanitized()
        if !includeCrop { s.crop = PhotoCrop() }
        guard s != PhotoGeometry() else { return image }
        var output = CIImage(cgImage: image)
        let orientations: [Int32] = [1, 6, 3, 8]
        output = normalized(output.oriented(forExifOrientation: orientations[s.rotation]))
        let rect = output.extent
        let w = rect.width, h = rect.height
        if s.angle != 0 {
            let a = CGFloat(s.angle * .pi / 180)
            let zoom = max((w * abs(cos(a)) + h * abs(sin(a))) / w,
                           (h * abs(cos(a)) + w * abs(sin(a))) / h)
            output = output.clampedToExtent().transformed(by: CGAffineTransform(translationX: -w / 2, y: -h / 2))
                .transformed(by: CGAffineTransform(rotationAngle: a))
                .transformed(by: CGAffineTransform(scaleX: zoom, y: zoom))
                .transformed(by: CGAffineTransform(translationX: w / 2, y: h / 2))
                .cropped(to: rect)
        }
        if s.vertical != 0 || s.horizontal != 0 {
            let top = max(0, s.vertical) * w * 0.18
            let bottom = max(0, -s.vertical) * w * 0.18
            let left = max(0, s.horizontal) * h * 0.18
            let right = max(0, -s.horizontal) * h * 0.18
            output = output.applyingFilter("CIPerspectiveTransform", parameters: [
                "inputTopLeft": CIVector(x: top, y: h - left),
                "inputTopRight": CIVector(x: w - top, y: h - right),
                "inputBottomLeft": CIVector(x: bottom, y: left),
                "inputBottomRight": CIVector(x: w - bottom, y: right)
            ])
            // Inscribed rectangle is inside all four edges of the transformed quadrilateral.
            let mx = max(top, bottom) + min(1, w * 0.05)
            let my = max(left, right) + min(1, h * 0.05)
            let safe = CGRect(x: mx, y: my, width: w - 2 * mx, height: h - 2 * my)
            output = output.transformed(by: CGAffineTransform(translationX: -safe.minX, y: -safe.minY))
                .transformed(by: CGAffineTransform(scaleX: w / safe.width, y: h / safe.height))
                .cropped(to: rect)
        }
        if s.distortion != 0 {
            guard let lensKernel, let result = lensKernel.apply(extent: rect, roiCallback: { _, _ in rect },
                image: output.clampedToExtent(), arguments: [CIVector(x: w, y: h), s.distortion]) else {
                throw EngineError.message("无法应用镜头畸变校正。")
            }
            output = result.cropped(to: rect)
        }
        let c = s.crop
        // Convert top-left UI coordinates to bottom-left Core Image coordinates.
        let crop = CGRect(x: c.x * w, y: (1 - c.y - c.height) * h,
                          width: c.width * w, height: c.height * h)
        let pixelCrop = CGRect(x: floor(crop.minX), y: floor(crop.minY),
                               width: max(1, floor(crop.width)), height: max(1, floor(crop.height)))
            .intersection(rect)
        return try raster(normalized(output.cropped(to: pixelCrop)), extent: CGRect(origin: .zero, size: pixelCrop.size))
    }

    static func apply(_ image: CGImage, settings: PhotoAdjustments) throws -> CGImage {
        try geometry(tone(image, settings: settings), settings: settings.geometry)
    }

    private static func normalized(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    private static func raster(_ image: CIImage, extent: CGRect) throws -> CGImage {
        guard let output = context.createCGImage(image, from: extent, format: .RGBA16, colorSpace: colorSpace) else {
            throw EngineError.message("照片调整渲染失败。")
        }
        return output
    }
}
