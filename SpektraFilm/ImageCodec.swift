import CoreGraphics
import PhotosUI
import SwiftUI
import CoreTransferable
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct FrameBuffer: Sendable {
    var pixels: [Float]
    var width: Int
    var height: Int

    var longEdge: Int { max(width, height) }
}

enum MemoryTier {
    /// Interactive picture. The engine's `live` tier uses the same long edge,
    /// so a preview does not allocate a second, larger working set.
    static let previewLongEdge = 2048

    /// Full-resolution export is one frame at a time, and still capped.
    /// A 48 MP float pipeline plus the engine's working planes is enough to
    /// jetsam an iPhone, so the cap follows physical memory.
    static func exportLongEdge(nativeLongEdge: Int) -> Int {
        let ram = ProcessInfo.processInfo.physicalMemory
        let cap: Int
        if ram < 4_500_000_000 {
            cap = 2048
        } else if ram < 6_500_000_000 {
            cap = 3072
        } else {
            cap = 4096
        }
        return max(64, min(max(nativeLongEdge, 1), cap))
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case jpeg
    case png
    case heic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        }
    }

    var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        }
    }
}

/// Shared Photos picker settings.
/// Note: PHPickerFilter has no `.rawImage`; camera RAW / DNG assets still appear under `.images`.
/// The dedicated RAW path is in load + ImageIO demosaic below.
enum PhotoImport {
    static var pickerFilter: PHPickerFilter { .images }

    /// Prefer the library's current full asset bytes (helps keep ProRAW / DNG when present).
    static var preferredEncoding: PhotosPickerItem.EncodingDisambiguationPolicy { .current }

    /// Load bytes from a picker item, preferring RAW/DNG payloads when advertised.
    static func loadData(from item: PhotosPickerItem) async throws -> Data {
        let types = item.supportedContentTypes
        let prefersRaw = types.contains {
            $0.conforms(to: UTType.rawImage)
                || $0.identifier == "com.adobe.raw-image"
                || $0.identifier.lowercased().contains("raw-image")
                || $0.identifier.lowercased().contains("dng")
        }
        // Always try the RAW-capable transferable first when the item advertises RAW.
        if prefersRaw {
            if let payload = try? await item.loadTransferable(type: RawImagePayload.self), !payload.data.isEmpty {
                return payload.data
            }
        }
        if let payload = try? await item.loadTransferable(type: ImageFilePayload.self), !payload.data.isEmpty {
            return payload.data
        }
        if let data = try await item.loadTransferable(type: Data.self), !data.isEmpty {
            return data
        }
        throw CodecError.message("这张照片没有可读的图像数据。")
    }
}

/// RAW / DNG only — used when supportedContentTypes advertises a raw UTI.
struct RawImagePayload: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: UTType.rawImage) { RawImagePayload(data: $0) }
        DataRepresentation(importedContentType: UTType("com.adobe.raw-image") ?? UTType.rawImage) { RawImagePayload(data: $0) }
        DataRepresentation(importedContentType: UTType("public.camera-raw-image") ?? UTType.rawImage) { RawImagePayload(data: $0) }
    }
}

/// Transferable that accepts RAW/DNG as well as common raster types.
struct ImageFilePayload: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: UTType.rawImage) { ImageFilePayload(data: $0) }
        DataRepresentation(importedContentType: UTType("com.adobe.raw-image") ?? UTType.rawImage) { ImageFilePayload(data: $0) }
        DataRepresentation(importedContentType: UTType.image) { ImageFilePayload(data: $0) }
        DataRepresentation(importedContentType: UTType.jpeg) { ImageFilePayload(data: $0) }
        DataRepresentation(importedContentType: UTType.heic) { ImageFilePayload(data: $0) }
        DataRepresentation(importedContentType: UTType.png) { ImageFilePayload(data: $0) }
        DataRepresentation(importedContentType: UTType.tiff) { ImageFilePayload(data: $0) }
    }
}

struct ImageProbe: Sendable {
    var uti: String
    var isRaw: Bool
    var width: Int
    var height: Int
}

enum ImageCodec {
    static func nativeLongEdge(_ data: Data) -> Int {
        guard let size = orientedPixelSize(data) else { return MemoryTier.previewLongEdge }
        return max(Int(size.width), Int(size.height), 1)
    }

    /// Pixel size after EXIF orientation, so source-ratio frames match the upright photo.
    static func orientedPixelSize(_ data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        var width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        var height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if (5...8).contains(orientation) {
            swap(&width, &height)
        }
        guard width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    static func probe(_ data: Data) -> ImageProbe {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return ImageProbe(uti: "unknown", isRaw: false, width: 0, height: 0)
        }
        let uti = (CGImageSourceGetType(source) as String?) ?? "unknown"
        let size = orientedPixelSize(data) ?? .zero
        return ImageProbe(
            uti: uti,
            isRaw: isRawUTI(uti),
            width: Int(size.width),
            height: Int(size.height)
        )
    }

    static func isRawUTI(_ uti: String) -> Bool {
        if let type = UTType(uti), type.conforms(to: UTType.rawImage) {
            return true
        }
        let lower = uti.lowercased()
        if lower == "public.camera-raw-image" || lower == "com.adobe.raw-image" {
            return true
        }
        // ImageIO vendor UTIs almost always end with "raw-image" or contain "dng".
        if lower.contains("raw-image") || lower.contains("rawimage") {
            return true
        }
        if lower.contains("dng") {
            return true
        }
        return false
    }

    /// Display P3, encoded (not linear). The engine is told to decode that
    /// transfer itself (`input_cctf_decoding`).
    /// RAW/DNG uses ImageIO demosaic via thumbnail-from-full-image (not a full develop pipeline).
    static func decode(_ data: Data, maxLongEdge: Int) throws -> FrameBuffer {
        let probe = probe(data)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw CodecError.message(probe.isRaw ? "这张 RAW 系统解不开，请换 DNG 或 JPEG。" : "这张照片读不出来。")
        }
        let edge = max(64, maxLongEdge)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: edge,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            // Fallback: try full image at index 0 (sometimes works when thumbnail path fails).
            if let full = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldAllowFloat: true,
            ] as CFDictionary) {
                return try rgbaBuffer(from: full, maxLongEdge: edge, isRaw: probe.isRaw)
            }
            throw CodecError.message(probe.isRaw ? "这张 RAW 系统解不开，请换 DNG 或 JPEG。" : "这张照片缩不下来。")
        }
        return try rgbaBuffer(from: image, maxLongEdge: edge, isRaw: probe.isRaw)
    }

    /// Build a Display-P3 float RGB FrameBuffer, optionally downscaling a full-size decode.
    private static func rgbaBuffer(from image: CGImage, maxLongEdge: Int, isRaw: Bool) throws -> FrameBuffer {
        var working = image
        let longEdge = max(image.width, image.height)
        if longEdge > maxLongEdge, maxLongEdge > 0 {
            let scale = CGFloat(maxLongEdge) / CGFloat(longEdge)
            let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
            let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
            guard let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) else {
                throw CodecError.message("系统没有 Display P3。")
            }
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                throw CodecError.message(isRaw ? "这张 RAW 系统解不开，请换 DNG 或 JPEG。" : "建不起色彩转换缓冲。")
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let scaled = context.makeImage() else {
                throw CodecError.message(isRaw ? "这张 RAW 系统解不开，请换 DNG 或 JPEG。" : "照片缩不下来。")
            }
            working = scaled
        }

        let width = working.width
        let height = working.height
        guard width > 0, height > 0 else {
            throw CodecError.message("照片尺寸是 0。")
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) else {
            throw CodecError.message("系统没有 Display P3。")
        }
        let count = width * height * 4
        let rgba = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        defer { rgba.deallocate() }
        rgba.initialize(repeating: 0, count: count)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw CodecError.message(isRaw ? "这张 RAW 系统解不开，请换 DNG 或 JPEG。" : "建不起色彩转换缓冲。")
        }
        context.interpolationQuality = .high
        context.draw(working, in: CGRect(x: 0, y: 0, width: width, height: height))

        var floats = [Float]()
        floats.reserveCapacity(width * height * 3)
        for index in 0..<(width * height) {
            let offset = index * 4
            var red = Int(rgba[offset])
            var green = Int(rgba[offset + 1])
            var blue = Int(rgba[offset + 2])
            let alpha = Int(rgba[offset + 3])
            if alpha == 0 {
                red = 0
                green = 0
                blue = 0
            } else if alpha < 255 {
                red = min(255, red * 255 / alpha)
                green = min(255, green * 255 / alpha)
                blue = min(255, blue * 255 / alpha)
            }
            floats.append(Float(red) / 255)
            floats.append(Float(green) / 255)
            floats.append(Float(blue) / 255)
        }
        return FrameBuffer(pixels: floats, width: width, height: height)
    }

    static func cgImage(rgba16: UnsafePointer<UInt16>, width: Int, height: Int, rowStride: Int) throws -> CGImage {
        guard width > 0, height > 0, rowStride >= width else {
            throw CodecError.message("引擎返回的尺寸不对。")
        }
        let bytesPerRow = rowStride * MemoryLayout<UInt16>.size * 4
        let data = Data(bytes: rgba16, count: bytesPerRow * height)
        guard let provider = CGDataProvider(data: data as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)
        else {
            throw CodecError.message("装不上渲染结果。")
        }
        let last = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
        if let image = make(width: width, height: height, bytesPerRow: bytesPerRow, space: colorSpace, info: last, provider: provider) {
            return image
        }
        let premul = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
        guard let image = make(width: width, height: height, bytesPerRow: bytesPerRow, space: colorSpace, info: premul, provider: provider) else {
            throw CodecError.message("16 位结果无法变成图像。")
        }
        return image
    }

    static func write(_ image: CGImage, format: ExportFormat) throws -> URL {
        try writeExport(image, format: format, maxBytes: nil).url
    }

    static func writeExport(_ image: CGImage, format: ExportFormat, maxBytes: Int?) throws
        -> (url: URL, width: Int, height: Int, bytes: Int) {
        let ext = format.utType.preferredFilenameExtension ?? format.rawValue
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiteFilm-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        if let maxBytes {
            let photo = try ExportEncoder.encode(image, type: format.utType, maxBytes: maxBytes)
            guard photo.data.count <= maxBytes else {
                throw CodecError.message("导出文件超出体积上限，请重试。")
            }
            try photo.data.write(to: url, options: .atomic)
            return (url, photo.width, photo.height, photo.data.count)
        }
        try write(image, format: format, to: url)
        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        return (url, image.width, image.height, bytes)
    }

    static func write(_ image: CGImage, format: ExportFormat, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw CodecError.message("无法创建 \(format.title) 文件。")
        }
        let quality: CGFloat = format == .png ? 1 : 0.92
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw CodecError.message("写入 \(format.title) 失败。")
        }
    }

    static func lumaSpread(_ image: CGImage) -> Double {
        let width = min(image.width, 160)
        let height = min(image.height, 160)
        guard width > 1, height > 1,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else { return 0 }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return 0 }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var sum = 0.0
        var sumSq = 0.0
        let count = width * height
        for index in 0..<count {
            let offset = index * 4
            let y = 0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1]) + 0.0722 * Double(pixels[offset + 2])
            sum += y
            sumSq += y * y
        }
        let mean = sum / Double(count)
        return (sumSq / Double(count) - mean * mean).squareRoot()
    }

    private static func make(
        width: Int,
        height: Int,
        bytesPerRow: Int,
        space: CGColorSpace,
        info: CGBitmapInfo,
        provider: CGDataProvider
    ) -> CGImage? {
        CGImage(
            width: width,
            height: height,
            bitsPerComponent: 16,
            bitsPerPixel: 64,
            bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: info,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .perceptual
        )
    }
}

enum CodecError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}
