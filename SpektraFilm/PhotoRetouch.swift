import CoreGraphics
import CoreImage
import Foundation

private func retouchBound(_ value: Double, _ limits: ClosedRange<Double>, _ fallback: Double) -> Double {
    value.isFinite ? min(limits.upperBound, max(limits.lowerBound, value)) : fallback
}

/// Coordinates are fractions of the final upright, cropped image, from its top-left.
struct RetouchPoint: Codable, Hashable, Sendable {
    var x = 0.5
    var y = 0.5
    func sanitized() -> Self { Self(x: retouchBound(x, 0...1, 0.5), y: retouchBound(y, 0...1, 0.5)) }
}

enum RetouchKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case linear, radial, brush, repair
    var id: String { rawValue }
    var title: String {
        switch self { case .linear: "渐变"; case .radial: "径向"; case .brush: "画笔"; case .repair: "取样修复" }
    }
    var symbol: String {
        switch self { case .linear: "line.diagonal"; case .radial: "circle.dashed"; case .brush: "paintbrush.pointed"; case .repair: "bandage" }
    }
}

struct RetouchLayer: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var kind: RetouchKind = .radial
    var points: [RetouchPoint] = []
    var source: RetouchPoint? = nil
    /// Brush/radial radius, as a fraction of the shorter image edge.
    var radius = 0.12
    var feather = 0.6
    var exposure = 0.5
    var saturation = 0.0

    func sanitized() -> Self {
        var result = self
        result.points = Array(points.prefix(RetouchEdits.maximumPoints)).map { $0.sanitized() }
        result.source = source?.sanitized()
        result.radius = retouchBound(radius, 0.005...0.5, 0.12)
        result.feather = retouchBound(feather, 0...1, 0.6)
        result.exposure = retouchBound(exposure, -2...2, 0)
        result.saturation = retouchBound(saturation, -1...1, 0)
        return result
    }
}

struct RetouchEdits: Codable, Hashable, Sendable {
    static let maximumLayers = 24
    static let maximumPoints = 256
    var layers: [RetouchLayer] = []
    var isEmpty: Bool { layers.isEmpty }
    func sanitized() -> Self {
        var ids = Set<UUID>()
        let safe = layers.prefix(Self.maximumLayers).map { raw in
            var layer = raw.sanitized()
            if ids.contains(layer.id) { layer.id = UUID() }
            ids.insert(layer.id)
            return layer
        }
        return Self(layers: safe)
    }
}

/// Offline feathered clone repair, not semantic/AI healing. Every repair has an explicit source.
/// The same bounded, resolution-independent recipe is used by editor previews and exports.
enum PhotoRetouchProcessor {
    private static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!,
        .cacheIntermediates: false
    ])
    private static let white = CIColor(red: 1, green: 1, blue: 1)
    private static let black = CIColor(red: 0, green: 0, blue: 0)

    static func apply(_ image: CGImage, edits: RetouchEdits) throws -> CGImage {
        let layers = edits.sanitized().layers.filter {
            !$0.points.isEmpty && ($0.kind == .repair ? $0.source != nil : ($0.exposure != 0 || $0.saturation != 0))
        }
        guard !layers.isEmpty else { return image }
        // Reject impossible imports before allocating masks or a full output bitmap.
        guard image.width > 0, image.height > 0, image.width <= 32768, image.height <= 32768,
              image.width <= 64_000_000 / image.height else {
            throw EngineError.message("局部编辑支持最多 6400 万像素的照片。")
        }
        var output = CIImage(cgImage: image)
        let rect = output.extent
        for layer in layers {
            try Task.checkCancellation()
            let mask = try mask(for: layer, extent: rect)
            let modified: CIImage
            if layer.kind == .repair, let source = layer.source, let target = layer.points.first {
                let dx = (target.x - source.x) * rect.width
                let dy = (source.y - target.y) * rect.height
                // Crop to genuine source pixels. Source-over retains the original wherever a
                // translated sample lies outside the photo or its source has transparency.
                let sample = output.transformed(by: CGAffineTransform(translationX: dx, y: dy)).cropped(to: rect)
                modified = sample.composited(over: output).cropped(to: rect)
            } else {
                var local = output
                if layer.exposure != 0 {
                    local = local.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: layer.exposure])
                }
                if layer.saturation != 0 {
                    local = local.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 + layer.saturation])
                }
                modified = local
            }
            output = modified.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: output, kCIInputMaskImageKey: mask
            ]).cropped(to: rect)
        }
        try Task.checkCancellation()
        let colorSpace = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpace(name: CGColorSpace.displayP3)!
        guard let result = context.createCGImage(output, from: rect, format: .RGBA16, colorSpace: colorSpace) else {
            throw EngineError.message("局部编辑渲染失败。")
        }
        return result
    }

    private static func vector(_ point: RetouchPoint, _ rect: CGRect) -> CIVector {
        CIVector(x: point.x * rect.width, y: (1 - point.y) * rect.height)
    }

    private static func mask(for layer: RetouchLayer, extent: CGRect) throws -> CIImage {
        let origin = layer.points[0]
        let radius = layer.radius * min(extent.width, extent.height)
        if layer.kind == .linear {
            let end = layer.points.count > 1 ? layer.points[1] : RetouchPoint(x: origin.x, y: min(1, origin.y + 0.3))
            let startVector = vector(origin, extent), endVector = vector(end, extent)
            // A zero-length drag is an empty mask, never an unbounded/global exposure edit.
            guard hypot(startVector.x - endVector.x, startVector.y - endVector.y) >= 0.5 else {
                return CIImage(color: black).cropped(to: extent)
            }
            return CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": startVector, "inputPoint1": endVector,
                "inputColor0": white, "inputColor1": black
            ])!.outputImage!.cropped(to: extent)
        }
        if layer.kind == .radial {
            return CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": vector(origin, extent), "inputRadius0": radius * (1 - layer.feather),
                "inputRadius1": radius + 0.01, "inputColor0": white, "inputColor1": black
            ])!.outputImage!.cropped(to: extent)
        }
        // A mask uses <=4 MiB regardless of original resolution; Core Image scales it back.
        let scale = min(1, 2048 / max(extent.width, extent.height))
        let width = max(1, Int((extent.width * scale).rounded()))
        let height = max(1, Int((extent.height * scale).rounded()))
        guard let drawing = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else {
            throw EngineError.message("无法创建局部编辑蒙版。")
        }
        drawing.setFillColor(gray: 0, alpha: 1)
        drawing.fill(CGRect(x: 0, y: 0, width: width, height: height))
        drawing.setStrokeColor(gray: 1, alpha: 1); drawing.setFillColor(gray: 1, alpha: 1)
        let r = radius * scale * (1 - layer.feather * 0.45)
        drawing.setLineWidth(max(1, r * 2)); drawing.setLineCap(.round); drawing.setLineJoin(.round)
        // A bitmap CGContext draws in bottom-left coordinates. makeImage() preserves that
        // orientation; CIImage does not turn a top-left UI point into a drawing point.
        // Match the explicit conversion used by radial/linear masks above.
        let points = layer.points.map { CGPoint(x: $0.x * Double(width), y: (1 - $0.y) * Double(height)) }
        if points.count == 1 {
            drawing.fillEllipse(in: CGRect(x: points[0].x - r, y: points[0].y - r, width: 2 * r, height: 2 * r))
        } else {
            drawing.addLines(between: points); drawing.strokePath()
        }
        guard let bitmap = drawing.makeImage() else { throw EngineError.message("局部蒙版生成失败。") }
        var result = CIImage(cgImage: bitmap)
        if layer.feather > 0 {
            result = result.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(0.1, radius * scale * layer.feather * 0.3)])
        }
        return result.transformed(by: CGAffineTransform(scaleX: extent.width / Double(width), y: extent.height / Double(height))).cropped(to: extent)
    }
}
