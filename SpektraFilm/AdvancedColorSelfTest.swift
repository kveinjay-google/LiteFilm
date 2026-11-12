import CoreGraphics
import Foundation

/// Small, deterministic pixel probes. No engine, photo library or background workers.
enum AdvancedColorSelfTest {
    static func run() throws {
        let gray = try swatch(0.45, 0.45, 0.45)
        let identity = try PhotoProcessor.tone(gray, settings: PhotoAdjustments())
        try require(identity === gray, "identity must bypass rendering")
        var settings = PhotoAdjustments()
        settings.temperature = 1
        let warmImage = try PhotoProcessor.tone(gray, settings: settings)
        try require(warmImage.bitsPerComponent == 16, "color path lost 16-bit precision")
        let warm = pixel(warmImage)
        settings.temperature = -1
        let cold = try pixel(PhotoProcessor.tone(gray, settings: settings))
        try require(warm[0] - warm[2] > cold[0] - cold[2] + 15, "warm/cold separation")
        settings = PhotoAdjustments(); settings.tint = 1
        let magenta = try pixel(PhotoProcessor.tone(gray, settings: settings))
        try require(magenta[0] + magenta[2] > 2 * magenta[1] + 10, "tint must shift neutral toward magenta")
        let dark = try swatch(0.08, 0.08, 0.08)
        settings = PhotoAdjustments(); settings.blacks = 1
        try require(try pixel(PhotoProcessor.tone(dark, settings: settings))[0] > pixel(dark)[0] + 8, "black lift")
        let bright = try swatch(0.9, 0.9, 0.9)
        settings = PhotoAdjustments(); settings.whites = -1
        try require(try pixel(PhotoProcessor.tone(bright, settings: settings))[0] < pixel(bright)[0] - 8, "white reduction")
        settings = PhotoAdjustments(); settings.curve = ToneCurve(points: [0, 0.4, 0.65, 0.85, 1])
        try require(try pixel(PhotoProcessor.tone(gray, settings: settings))[0] > pixel(gray)[0] + 15, "master curve")
        var previous = -1
        for level in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0] {
            let source = try swatch(level, level, level)
            let value = try pixel(PhotoProcessor.tone(source, settings: settings))[0]
            try require(value >= previous, "curve reversed luminance order")
            previous = value
        }
        let red = try swatch(0.8, 0.1, 0.1), blue = try swatch(0.1, 0.1, 0.8)
        settings = PhotoAdjustments(); settings.hsl[0].saturation = -1
        let muted = try pixel(PhotoProcessor.tone(red, settings: settings))
        let untouched = try pixel(PhotoProcessor.tone(blue, settings: settings))
        let originalBlue = pixel(blue)
        try require(abs(muted[0] - muted[1]) < 8, "red HSL saturation")
        try require(zip(untouched, originalBlue).allSatisfy { abs($0 - $1) < 4 }, "red HSL changed blue")
        settings.hsl[0] = HSLBand(hue: 1)
        let shifted = try pixel(PhotoProcessor.tone(red, settings: settings))
        try require(shifted[1] > pixel(red)[1] + 20, "red hue shifts toward yellow")
        settings.hsl[0] = HSLBand(luminance: 0.8)
        try require(try pixel(PhotoProcessor.tone(red, settings: settings))[1] > pixel(red)[1] + 10, "red luminance")
        let legacy = Data("{\"highlights\":0.4,\"shadows\":-0.2,\"contrast\":0.1,\"saturation\":0,\"geometry\":{\"rotation\":0,\"angle\":0,\"vertical\":0,\"horizontal\":0,\"distortion\":0,\"crop\":{\"x\":0,\"y\":0,\"width\":1,\"height\":1}}}".utf8)
        try require(try JSONDecoder().decode(PhotoAdjustments.self, from: Data("{}".utf8)) == PhotoAdjustments(), "empty legacy adjustment")
        let decoded = try JSONDecoder().decode(PhotoAdjustments.self, from: legacy)
        try require(decoded.highlights == 0.4 && decoded.temperature == 0 && decoded.curve == ToneCurve() && decoded.hsl == HSLBand.defaults && decoded.retouch == RetouchEdits(), "legacy adjustment defaults")
        var corrupt = PhotoAdjustments()
        corrupt.temperature = .nan; corrupt.tint = .infinity; corrupt.blacks = -99; corrupt.whites = 99
        corrupt.curve = ToneCurve(points: [0.8, .nan, -3, 20, 0.2])
        corrupt.hsl = Array(repeating: HSLBand(hue: .nan, saturation: 20, luminance: -.infinity), count: 100)
        let safe = corrupt.sanitized()
        try require(safe.temperature == 0 && safe.tint == 0 && safe.blacks == -1 && safe.whites == 1, "finite limits")
        try require(safe.curve.points.count == 5 && zip(safe.curve.points, safe.curve.points.dropFirst()).allSatisfy { $0 <= $1 }, "monotonic curve")
        try require(safe.hsl.count == 6 && safe.hsl.allSatisfy { $0.hue == 0 && $0.saturation == 1 && $0.luminance == 0 }, "HSL bounds")
        try require(HSLBand.sanitized([]) == HSLBand.defaults, "missing HSL bands")
        try require(ToneCurve(points: []).sanitized() == ToneCurve(), "missing curve anchors")
        let roundTrip = try JSONDecoder().decode(PhotoAdjustments.self, from: JSONEncoder().encode(safe))
        try require(roundTrip == safe, "advanced archive roundtrip")
        _ = try PhotoProcessor.tone(gray, settings: corrupt)
        logLine("LITEFILM_ADVANCED_COLOR_OK identity=1 balance=1 levels=1 curve=1 hsl=1 legacy=1 bounds=1")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw EngineError.message("advanced color: " + message) }
    }

    private static func swatch(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) throws -> CGImage {
        guard let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw EngineError.message("advanced color swatch context")
        }
        context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        guard let image = context.makeImage() else { throw EngineError.message("advanced color swatch") }
        return image
    }

    private static func pixel(_ image: CGImage) -> [Int] {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { storage in
            let context = CGContext(data: storage.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes.prefix(3).map(Int.init)
    }
}
