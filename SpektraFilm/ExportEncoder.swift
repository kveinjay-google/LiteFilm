import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ExportEncodingError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

struct EncodedPhoto {
    let data: Data
    let width: Int
    let height: Int
}

enum ExportSizeLimit {
    static let maximumKB = 1_000_000

    /// Decimal KB, matching file sizes shown by Files. Reject overflow before multiplication.
    static func bytes(fromKB text: String) -> Int? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
              let value = Int(text), (1...maximumKB).contains(value) else { return nil }
        return value * 1_000
    }
}

enum ExportEncoder {
    static func encode(_ image: CGImage, type: UTType, maxBytes: Int?) throws -> EncodedPhoto {
        if let maxBytes, !(1...(ExportSizeLimit.maximumKB * 1_000)).contains(maxBytes) {
            throw ExportEncodingError.message("请输入有效的文件体积上限。")
        }
        var current = image
        // Each iteration strictly reduces the long edge. No unbounded allocation or retry loop.
        for _ in 0..<14 {
            let high = try encodedData(current, type: type, quality: 0.92)
            guard let cap = maxBytes, high.count > cap else {
                return EncodedPhoto(data: high, width: current.width, height: current.height)
            }
            var smallest = high
            if type != .png {
                let lowQuality = 0.40
                smallest = try encodedData(current, type: type, quality: lowQuality)
                if smallest.count <= cap {
                    var best = smallest
                    var low = lowQuality, highQuality = 0.92
                    for _ in 0..<7 {
                        let quality = (low + highQuality) / 2
                        let candidate = try encodedData(current, type: type, quality: quality)
                        if candidate.count <= cap { best = candidate; low = quality }
                        else { highQuality = quality }
                    }
                    return EncodedPhoto(data: best, width: current.width, height: current.height)
                }
            }
            let edge = max(current.width, current.height)
            guard edge > 64 else { break }
            let scale = min(0.85, max(0.1, sqrt(Double(cap) / Double(smallest.count)) * 0.9))
            let nextEdge = max(64, Int(Double(edge) * scale))
            // Always sample from the original so repeated reductions do not accumulate blur.
            current = try resized(image, longEdge: nextEdge)
        }
        throw ExportEncodingError.message("无法在此体积上限内保留有效图片，请提高 KB 上限或更换格式。")
    }

    private static func resized(_ image: CGImage, longEdge: Int) throws -> CGImage {
        let ratio = Double(longEdge) / Double(max(image.width, image.height))
        let width = max(1, Int((Double(image.width) * ratio).rounded()))
        let height = max(1, Int((Double(image.height) * ratio).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ExportEncodingError.message("无法调整导出尺寸。")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resized = context.makeImage() else {
            throw ExportEncodingError.message("无法生成调整后的图片。")
        }
        return resized
    }

    private static func encodedData(_ image: CGImage, type: UTType, quality: Double) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw ExportEncodingError.message("无法创建图片文件。")
        }
        CGImageDestinationAddImage(destination, image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportEncodingError.message("图片编码失败，请尝试其他格式。")
        }
        return data as Data
    }
}
