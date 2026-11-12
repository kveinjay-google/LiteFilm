import UIKit

enum PhotoAnalysisSelfTest {
    static func run() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw EngineError.message("photo analysis: " + message) }
        }
        func image(_ colors: [UInt8], width: Int = 12, height: Int = 8) -> UIImage {
            var bytes = [UInt8](repeating: 255, count: width * height * 4)
            for index in 0..<(width * height) {
                let value = colors[index % colors.count]
                bytes[index * 4] = value; bytes[index * 4 + 1] = value; bytes[index * 4 + 2] = value
            }
            let provider = CGDataProvider(data: Data(bytes) as CFData)!
            return UIImage(cgImage: CGImage(width: width, height: height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!)
        }
        let black = try PhotoAnalysis.analyze(image([0]))
        try require(black.pixelCount == 96 && black.histogram[0] == 96, "black histogram")
        try require(black.highlightCount == 0 && black.shadowCount == 96, "black clipping")
        let white = try PhotoAnalysis.analyze(image([255]))
        try require(white.histogram[255] == 96 && white.highlightCount == 96, "white histogram/clipping")
        let gray = try PhotoAnalysis.analyze(image([128]))
        try require(gray.histogram[128] == 96 && gray.highlightCount == 0 && gray.shadowCount == 0, "gray histogram/clipping")
        let mixed = try PhotoAnalysis.analyze(image([0, 128, 255]))
        try require(mixed.histogram.reduce(0, +) == 96 && mixed.highlightCount == 32, "mixed counts")
        let mask = mixed.highlightOverlay.dataProvider!.data! as Data
        try require(mask[3] == 0 && mask[7] == 0 && mask[11] > 0, "overlay not localized to clipped pixels")
        let wide = image([128], width: 1200, height: 600)
        let bounded = try PhotoAnalysis.analyze(wide)
        try require(bounded.width == 512 && bounded.height == 256, "bounded aspect ratio")
        let rotated = UIImage(cgImage: wide.cgImage!, scale: 1, orientation: .right)
        let turned = try PhotoAnalysis.analyze(rotated)
        try require(turned.width == 256 && turned.height == 512, "oriented dimensions")
        // An asymmetric card catches an upside-down or unrotated clipping overlay.
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = true
        let halves = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 8), format: fmt).image { _ in
            UIColor.black.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 16, height: 8))
            UIColor.white.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let mirrored = try PhotoAnalysis.analyze(UIImage(cgImage: halves.cgImage!, scale: 1, orientation: .upMirrored))
        let mirroredMask = mirrored.highlightOverlay.dataProvider!.data! as Data
        try require(mirroredMask[3] == 0 && mirroredMask[15 * 4 + 3] > 0, "mirrored clipping position")
        logLine("LITEFILM_PHOTO_ANALYSIS_SELFTEST_OK")
    }
}
