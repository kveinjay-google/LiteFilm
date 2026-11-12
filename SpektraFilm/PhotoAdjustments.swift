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

/// Five fixed input anchors (0, .25, .5, .75, 1); output anchors never decrease.
struct ToneCurve: Codable, Equatable, Hashable, Sendable {
    static let identity = [0.0, 0.25, 0.5, 0.75, 1.0]
    var points = identity

    func sanitized() -> Self {
        var result = Self.identity
        for i in 0..<5 {
            let value = i < points.count ? bounded(points[i], 0...1, fallback: Self.identity[i]) : Self.identity[i]
            result[i] = max(i == 0 ? 0 : result[i - 1], value)
        }
        return Self(points: result)
    }
}

/// Ordered red, yellow, green, cyan, blue, magenta. Hue ±1 = ±30 degrees.
struct HSLBand: Codable, Equatable, Hashable, Sendable {
    var hue = 0.0
    var saturation = 0.0
    var luminance = 0.0
    static let defaults = Array(repeating: Self(), count: 6)

    func sanitized() -> Self {
        Self(hue: bounded(hue, -1...1), saturation: bounded(saturation, -1...1),
             luminance: bounded(luminance, -1...1))
    }

    static func sanitized(_ bands: [Self]) -> [Self] {
        (0..<6).map { $0 < bands.count ? bands[$0].sanitized() : Self() }
    }
}

struct PhotoAdjustments: Codable, Equatable, Hashable, Sendable {
    var highlights = 0.0
    var shadows = 0.0
    var contrast = 0.0
    var saturation = 0.0
    var temperature = 0.0
    var tint = 0.0
    var blacks = 0.0
    var whites = 0.0
    var curve = ToneCurve()
    var hsl = HSLBand.defaults
    var geometry = PhotoGeometry()
    var retouch = RetouchEdits()

    private enum CodingKeys: String, CodingKey {
        case highlights, shadows, contrast, saturation, temperature, tint, blacks, whites, curve, hsl, geometry, retouch
    }

    init(highlights: Double = 0, shadows: Double = 0, contrast: Double = 0, saturation: Double = 0,
         temperature: Double = 0, tint: Double = 0, blacks: Double = 0, whites: Double = 0,
         curve: ToneCurve = ToneCurve(), hsl: [HSLBand] = HSLBand.defaults,
         geometry: PhotoGeometry = PhotoGeometry(), retouch: RetouchEdits = RetouchEdits()) {
        self.highlights = highlights; self.shadows = shadows; self.contrast = contrast; self.saturation = saturation
        self.temperature = temperature; self.tint = tint; self.blacks = blacks; self.whites = whites
        self.curve = curve; self.hsl = hsl; self.geometry = geometry; self.retouch = retouch
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(highlights: try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0,
                  shadows: try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0,
                  contrast: try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 0,
                  saturation: try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 0,
                  temperature: try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0,
                  tint: try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0,
                  blacks: try c.decodeIfPresent(Double.self, forKey: .blacks) ?? 0,
                  whites: try c.decodeIfPresent(Double.self, forKey: .whites) ?? 0,
                  curve: try c.decodeIfPresent(ToneCurve.self, forKey: .curve) ?? ToneCurve(),
                  hsl: try c.decodeIfPresent([HSLBand].self, forKey: .hsl) ?? HSLBand.defaults,
                  geometry: try c.decodeIfPresent(PhotoGeometry.self, forKey: .geometry) ?? PhotoGeometry(),
                  retouch: try c.decodeIfPresent(RetouchEdits.self, forKey: .retouch) ?? RetouchEdits())
        self = sanitized()
    }

    func sanitized() -> Self {
        Self(highlights: bounded(highlights, -1...1), shadows: bounded(shadows, -1...1),
             contrast: bounded(contrast, -1...1), saturation: bounded(saturation, -1...1),
             temperature: bounded(temperature, -1...1), tint: bounded(tint, -1...1),
             blacks: bounded(blacks, -1...1), whites: bounded(whites, -1...1),
             curve: curve.sanitized(), hsl: HSLBand.sanitized(hsl),
             geometry: geometry.sanitized(), retouch: retouch.sanitized())
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

    // Color kernels work on gamma-encoded components, surrounded by explicit Core Image
    // transfer functions. HSL weights are derived once from the original hue, so edits
    // never leak into the next band through sequential hue shifts.
    private static let curveKernel = CIColorKernel(source: """
        float anchor(float v, vec4 p, float end) {
            v = clamp(v, 0.0, 1.0);
            if (v < 0.25) { return mix(p.x, p.y, v * 4.0); }
            if (v < 0.5) { return mix(p.y, p.z, (v - 0.25) * 4.0); }
            if (v < 0.75) { return mix(p.z, p.w, (v - 0.5) * 4.0); }
            return mix(p.w, end, (v - 0.75) * 4.0);
        }
        kernel vec4 master(__sample sample, vec4 p, float end, float blacks, float whites) {
            vec4 c = unpremultiply(sample);
            vec3 v = clamp(c.rgb, 0.0, 1.0);
            v += blacks * 0.22 * pow(vec3(1.0) - v, vec3(3.0));
            v += whites * 0.22 * pow(clamp(c.rgb, 0.0, 1.0), vec3(3.0));
            return premultiply(vec4(anchor(v.r, p, end), anchor(v.g, p, end), anchor(v.b, p, end), c.a));
        }
        """)
    private static let hslKernel = CIColorKernel(source: """
        float bandWeight(float h, float center) {
            float d = abs(h - center);
            d = min(d, 1.0 - d);
            return 1.0 - smoothstep(0.0, 1.0 / 6.0, d);
        }
        kernel vec4 selective(__sample sample, vec3 red, vec3 yellow, vec3 green,
                              vec3 cyan, vec3 blue, vec3 magenta) {
            vec4 original = unpremultiply(sample);
            vec3 c = clamp(original.rgb, 0.0, 1.0);
            float hi = max(c.r, max(c.g, c.b));
            float lo = min(c.r, min(c.g, c.b));
            float delta = hi - lo;
            float lightness = (hi + lo) * 0.5;
            if (delta < 0.00001) { return sample; }
            float saturation = delta / max(0.00001, 1.0 - abs(2.0 * lightness - 1.0));
            float hue;
            if (hi == c.r) { hue = (c.g - c.b) / delta; }
            else if (hi == c.g) { hue = 2.0 + (c.b - c.r) / delta; }
            else { hue = 4.0 + (c.r - c.g) / delta; }
            hue = fract(hue / 6.0 + 1.0);
            vec3 edit = red * bandWeight(hue, 0.0) + yellow * bandWeight(hue, 1.0 / 6.0)
                      + green * bandWeight(hue, 2.0 / 6.0) + cyan * bandWeight(hue, 0.5)
                      + blue * bandWeight(hue, 4.0 / 6.0) + magenta * bandWeight(hue, 5.0 / 6.0);
            edit *= smoothstep(0.0, 0.15, saturation);
            hue = fract(hue + edit.x / 12.0 + 1.0);
            saturation = clamp(saturation * (1.0 + edit.y), 0.0, 1.0);
            lightness += edit.z * 0.5 * (edit.z > 0.0 ? 1.0 - lightness : lightness);
            float chroma = (1.0 - abs(2.0 * lightness - 1.0)) * saturation;
            vec3 shape = clamp(abs(fract(vec3(hue) + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
            return premultiply(vec4((shape - vec3(0.5)) * chroma + vec3(lightness), original.a));
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
        guard s.highlights != 0 || s.shadows != 0 || s.contrast != 0 || s.saturation != 0 ||
              s.temperature != 0 || s.tint != 0 || s.blacks != 0 || s.whites != 0 ||
              s.curve != ToneCurve() || s.hsl != HSLBand.defaults else { return image }
        var output = CIImage(cgImage: image)
        if s.temperature != 0 || s.tint != 0 {
            // Reciprocal red/blue gains model warm/cool balance in linear light.
            output = output.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: pow(2, s.temperature * 0.5 + s.tint * 0.12), y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: pow(2, -s.tint * 0.25), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: pow(2, -s.temperature * 0.5 + s.tint * 0.12), w: 0)
            ])
        }
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
        if s.blacks != 0 || s.whites != 0 || s.curve != ToneCurve() || s.hsl != HSLBand.defaults {
            output = output.applyingFilter("CILinearToSRGBToneCurve")
            if s.blacks != 0 || s.whites != 0 || s.curve != ToneCurve() {
                let p = s.curve.points
                guard let curveKernel, let result = curveKernel.apply(extent: output.extent, arguments: [
                    output, CIVector(x: p[0], y: p[1], z: p[2], w: p[3]), p[4], s.blacks, s.whites
                ]) else { throw EngineError.message("无法应用色调曲线。") }
                output = result
            }
            if s.hsl != HSLBand.defaults {
                let bands = s.hsl.map { CIVector(x: $0.hue, y: $0.saturation, z: $0.luminance) }
                guard let hslKernel, let result = hslKernel.apply(extent: output.extent,
                    arguments: [output] + bands.map { $0 as Any }) else {
                    throw EngineError.message("无法应用 HSL 色彩调整。")
                }
                output = result
            }
            output = output.applyingFilter("CISRGBToneCurveToLinear")
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
        let corrected = try geometry(tone(image, settings: settings), settings: settings.geometry)
        return try PhotoRetouchProcessor.apply(corrected, edits: settings.retouch)
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
