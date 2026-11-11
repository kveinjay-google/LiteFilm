import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main
struct ExportEncoderTests {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw ExportEncodingError.message("FAIL: \(message)") }
    }

    static func main() throws {
        try require(ExportSizeLimit.bytes(fromKB: " 500 ") == 500_000, "decimal KB")
        try require(ExportSizeLimit.bytes(fromKB: "1") == 1_000, "minimum KB")
        try require(ExportSizeLimit.bytes(fromKB: "1000000") == 1_000_000_000, "maximum KB")
        for invalid in ["", "0", "-1", "1.5", "NaN", "1000001", "9999999999999999999999999"] {
            try require(ExportSizeLimit.bytes(fromKB: invalid) == nil, "invalid cap accepted: \(invalid)")
        }
        let width = 800, height = 600
        var state: UInt32 = 42
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            for channel in 0..<3 {
                state = state &* 1664525 &+ 1013904223
                pixels[i + channel] = UInt8(truncatingIfNeeded: state >> 24)
            }
            pixels[i + 3] = 255
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        for type: UTType in [.jpeg, .png, .heic] {
            let original = try ExportEncoder.encode(image, type: type, maxBytes: nil)
            try require(original.width == width && original.height == height, "unlimited dimensions")
            let generous = try ExportEncoder.encode(image, type: type, maxBytes: 5_000_000)
            try require(generous.width == width && generous.height == height, "unnecessary resizing")
            for cap in [500_000, 100_000, 10_000] {
                let result = try ExportEncoder.encode(image, type: type, maxBytes: cap)
                try require(result.data.count <= cap, "\(type.identifier) exceeds \(cap): \(result.data.count)")
                guard let source = CGImageSourceCreateWithData(result.data as CFData, nil),
                      let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw ExportEncodingError.message("FAIL: cannot decode \(type.identifier)")
                }
                try require(CGImageSourceGetType(source) as String? == type.identifier, "format changed")
                try require(decoded.width == result.width && decoded.height == result.height, "reported dimensions")
                try require(result.width <= width && result.height <= height, "upscaled")
                try require(abs(Double(result.width) / Double(result.height) - 4.0 / 3.0) < 0.025, "aspect ratio")
                print("PASS \(type.identifier) cap=\(cap) bytes=\(result.data.count) size=\(result.width)x\(result.height)")
            }
        }
        for cap in [-1, 0, 1, Int.max] {
            var rejected = false
            do { _ = try ExportEncoder.encode(image, type: .png, maxBytes: cap) }
            catch { rejected = true }
            try require(rejected, "invalid/impossible byte cap accepted: \(cap)")
        }
        // Preserve transparent areas even when a PNG must be reduced.
        let context = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8,
            bytesPerRow: 3200, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: 800, height: 600))
        context.draw(image, in: CGRect(x: 200, y: 150, width: 400, height: 300))
        let alpha = try ExportEncoder.encode(context.makeImage()!, type: .png, maxBytes: 10_000)
        let alphaSource = CGImageSourceCreateWithData(alpha.data as CFData, nil)!
        let decodedAlpha = CGImageSourceCreateImageAtIndex(alphaSource, 0, nil)!
        let probe = CGContext(data: nil, width: decodedAlpha.width, height: decodedAlpha.height,
            bitsPerComponent: 8, bytesPerRow: decodedAlpha.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        probe.draw(decodedAlpha, in: CGRect(x: 0, y: 0, width: decodedAlpha.width, height: decodedAlpha.height))
        try require(probe.data!.assumingMemoryBound(to: UInt8.self)[3] == 0, "PNG transparency lost")
        print("PASS validation, impossible limits, PNG transparency; ALL EXPORT TESTS PASSED")
    }
}
