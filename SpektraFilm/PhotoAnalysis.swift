import UIKit

/// Display-only analysis of an oriented sRGB preview, never an export operation.
struct PhotoAnalysisResult: @unchecked Sendable {
    let histogram: [Int]
    let pixelCount: Int
    let highlightCount: Int
    let shadowCount: Int
    let width: Int
    let height: Int
    let highlightOverlay: CGImage

    var highlightPercent: Double { pixelCount == 0 ? 0 : Double(highlightCount) / Double(pixelCount) * 100 }
    var shadowPercent: Double { pixelCount == 0 ? 0 : Double(shadowCount) / Double(pixelCount) * 100 }
}

enum PhotoAnalysis {
    /// Fixed allocation ceiling also applies to direct callers and self-tests.
    static let maximumEdge = 512

    static func analyze(_ image: UIImage) throws -> PhotoAnalysisResult {
        try Task.checkCancellation()
        let size = image.size
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            throw EngineError.message("照片预览尺寸无效")
        }
        let sourceWidth = size.width * image.scale
        let sourceHeight = size.height * image.scale
        let factor = min(1, CGFloat(maximumEdge) / max(sourceWidth, sourceHeight))
        let width = max(1, min(maximumEdge, Int((sourceWidth * factor).rounded())))
        let height = max(1, min(maximumEdge, Int((sourceHeight * factor).rounded())))
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = false; format.preferredRange = .standard
        // UIImage.draw applies all eight EXIF orientations, including mirrored images.
        let normalized = UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            image.draw(in: rect)
        }
        guard let cgImage = normalized.cgImage else { throw EngineError.message("无法读取照片预览") }
        try Task.checkCancellation()
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let drawn = rgba.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: bitmapInfo) else { return false }
            context.draw(cgImage, in: rect)
            return true
        }
        guard drawn else { throw EngineError.message("无法分析照片预览") }
        var histogram = [Int](repeating: 0, count: 256)
        var overlay = [UInt8](repeating: 0, count: rgba.count)
        var highlights = 0, shadows = 0, count = 0
        for y in 0..<height {
            try Task.checkCancellation()
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let alpha = Int(rgba[offset + 3])
                guard alpha > 0 else { continue }
                let r = min(255, Int(rgba[offset]) * 255 / alpha)
                let g = min(255, Int(rgba[offset + 1]) * 255 / alpha)
                let b = min(255, Int(rgba[offset + 2]) * 255 / alpha)
                // Rec.709 coefficients on displayed sRGB values; not a RAW sensor histogram.
                let luminance = min(255, max(0, Int((0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)).rounded())))
                histogram[luminance] += 1; count += 1
                if max(r, max(g, b)) >= 254 {
                    highlights += 1
                    let opacity: UInt8 = (x + y) % 10 < 5 ? 150 : 85
                    // Premultiplied red zebra; all other pixels remain fully transparent.
                    overlay[offset] = opacity
                    overlay[offset + 3] = opacity
                }
                if max(r, max(g, b)) <= 1 { shadows += 1 }
            }
        }
        guard let provider = CGDataProvider(data: Data(overlay) as CFData),
              let overlayImage = CGImage(width: width, height: height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw EngineError.message("无法生成高光提示")
        }
        return PhotoAnalysisResult(histogram: histogram, pixelCount: count, highlightCount: highlights,
            shadowCount: shadows, width: width, height: height, highlightOverlay: overlayImage)
    }
}

/// A single serial executor prevents competing analysis tasks from creating worker pools.
actor PhotoAnalysisWorker {
    static let shared = PhotoAnalysisWorker()
    func analyze(_ image: UIImage) throws -> PhotoAnalysisResult {
        try PhotoAnalysis.analyze(image)
    }
}
