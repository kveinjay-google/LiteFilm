import CoreGraphics
import Foundation

/// Pixel checks use top-left storage, matching the saved image and editor gestures.
enum RetouchSelfTest {
    static func run() throws {
        let input = try card(160)
        let identity = try PhotoRetouchProcessor.apply(input, edits: RetouchEdits())
        try require(identity === input, "identity must return original pixels")
        var radial = RetouchLayer(kind: .radial)
        radial.points = [RetouchPoint(x: 0.25, y: 0.25)]
        radial.radius = 0.12; radial.feather = 0.35; radial.exposure = 1
        let output = try PhotoRetouchProcessor.apply(input, edits: RetouchEdits(layers: [radial]))
        try require(output.width == input.width && output.height == input.height && output.bitsPerComponent == 16, "output lost resolution or precision")
        let before = pixels(input), after = pixels(output)
        try require(after[(40 * 160 + 40) * 4] > before[(40 * 160 + 40) * 4] + 20, "radial center unchanged / vertical inversion")
        try require(abs(Int(after[(120 * 160 + 40) * 4]) - Int(before[(120 * 160 + 40) * 4])) < 3, "radial escaped mask")
        let large = try PhotoRetouchProcessor.apply(card(320), edits: RetouchEdits(layers: [radial]))
        let larger = pixels(large)
        try require(abs(Int(after[(40 * 160 + 40) * 4]) - Int(larger[(80 * 320 + 80) * 4])) < 3, "resolution dependent mask")
        var brush = radial; brush.kind = .brush
        brush.points = [RetouchPoint(x: 0.2, y: 0.2), RetouchPoint(x: 0.4, y: 0.2)]
        let painted = pixels(try PhotoRetouchProcessor.apply(input, edits: RetouchEdits(layers: [brush])))
        let brushTop = Int(painted[(32 * 160 + 48) * 4])
        let brushMirror = Int(painted[(128 * 160 + 48) * 4])
        logLine("LITEFILM_RETOUCH_BRUSH_PIXELS top=\(brushTop) beforeTop=\(before[(32 * 160 + 48) * 4]) mirror=\(brushMirror) beforeMirror=\(before[(128 * 160 + 48) * 4])")
        try require(brushTop > Int(before[(32 * 160 + 48) * 4]) + 15, "brush missing or inverted: top=\(brushTop), mirror=\(brushMirror)")
        try require(abs(Int(painted[(128 * 160 + 48) * 4]) - Int(before[(128 * 160 + 48) * 4])) < 3, "brush leaked")
        let brushLarge = pixels(try PhotoRetouchProcessor.apply(card(320), edits: RetouchEdits(layers: [brush])))
        try require(abs(Int(brushLarge[(64 * 320 + 96) * 4]) - brushTop) < 4, "brush mask scale changed strength")
        var linear = radial; linear.kind = .linear
        linear.points = [RetouchPoint(x: 0.2, y: 0.1), RetouchPoint(x: 0.2, y: 0.8)]
        let ramp = pixels(try PhotoRetouchProcessor.apply(input, edits: RetouchEdits(layers: [linear])))
        let topGain = Int(ramp[(16 * 160 + 40) * 4]) - Int(before[(16 * 160 + 40) * 4])
        let bottomGain = Int(ramp[(144 * 160 + 40) * 4]) - Int(before[(144 * 160 + 40) * 4])
        try require(topGain > bottomGain + 15, "linear direction incorrect")
        var repair = RetouchLayer(kind: .repair)
        repair.points = [RetouchPoint(x: 0.75, y: 0.25)]
        repair.source = RetouchPoint(x: 0.25, y: 0.75)
        repair.radius = 0.12; repair.feather = 0.2
        let fixed = pixels(try PhotoRetouchProcessor.apply(input, edits: RetouchEdits(layers: [repair])))
        logLine("LITEFILM_RETOUCH_REPAIR_PIXELS target=\(fixed[(40 * 160 + 120) * 4]) source=\(before[(120 * 160 + 40) * 4]) mirror=\(fixed[(120 * 160 + 120) * 4])")
        try require(abs(Int(fixed[(40 * 160 + 120) * 4]) - Int(before[(120 * 160 + 40) * 4])) < 4, "repair did not sample vertically offset source")
        try require(abs(Int(fixed[(120 * 160 + 120) * 4]) - Int(before[(120 * 160 + 120) * 4])) < 3, "repair escaped stroke")
        repair.source = RetouchPoint(x: 0, y: 0)
        repair.points = [RetouchPoint(x: 0.98, y: 0.98)]
        let edge = pixels(try PhotoRetouchProcessor.apply(input, edits: RetouchEdits(layers: [repair])))
        try require(stride(from: 3, to: edge.count, by: 4).allSatisfy { edge[$0] == 255 }, "edge repair introduced transparency")
        radial.radius = .infinity; radial.exposure = .nan; radial.feather = -100
        radial.points = Array(repeating: RetouchPoint(x: .nan, y: 400), count: 2000)
        let safe = RetouchEdits(layers: Array(repeating: radial, count: 200)).sanitized()
        try require(safe.layers.count == RetouchEdits.maximumLayers && safe.layers.allSatisfy { $0.points.count <= RetouchEdits.maximumPoints }, "limits not enforced")
        try require(Set(safe.layers.map(\.id)).count == safe.layers.count, "duplicate layer identities")
        try require(try JSONDecoder().decode(RetouchEdits.self, from: JSONEncoder().encode(safe)) == safe, "archive roundtrip")
        _ = try PhotoRetouchProcessor.apply(input, edits: safe)
        logLine("LITEFILM_RETOUCH_SELFTEST_OK")
    }
    private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw EngineError.message("retouch: " + message) }
    }
    private static func card(_ side: Int) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        for y in 0..<side { for x in 0..<side {
            let value: UInt8 = (x < side / 2 ? 80 : 180) + (y < side / 2 ? 0 : 20)
            let i = (y * side + x) * 4
            bytes[i] = value; bytes[i + 1] = value; bytes[i + 2] = value
        }}
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        guard let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw EngineError.message("retouch test fixture")
        }
        return image
    }
    private static func pixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { data in
            let context = CGContext(data: data.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
