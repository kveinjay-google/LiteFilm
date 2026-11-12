import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Film / paper / frame / watermark snapshot attached to a gallery variant.
struct GalleryRecipe: Codable, Equatable, Hashable, Sendable {
    var filmID: String
    var paperID: String
    var exposureEV: Double
    var frame: FrameEditState
    var watermark: WatermarkEditState
    var adjustments: PhotoAdjustments? = nil
    var textLayers: [PhotoTextLayer]? = nil
}

/// One sandbox gallery entry. Variants duplicate original bytes so deletes stay isolated.
struct GalleryItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var title: String
    var createdAt: Date
    var originalName: String
    var thumbName: String
    var byteCount: Int
    /// "import" (default) or "variant". Missing on older manifests = import.
    var kind: String?
    var recipe: GalleryRecipe?
    /// Informational fork pointer only — never shares files with the parent.
    var forkedFromID: String?

    static let sampleID = "builtin-sample-bars"

    var isVariant: Bool {
        if kind == "variant" { return true }
        return recipe != nil
    }
}

/// Persists imported originals + JPEG thumbs under Application Support.
@MainActor
final class ImportGalleryStore: ObservableObject {
    @Published private(set) var items: [GalleryItem] = []

    private let fileManager: FileManager
    private let rootURL: URL
    private let originalsURL: URL
    private let thumbsURL: URL
    private let manifestURL: URL

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.rootURL = support.appendingPathComponent("SpektraFilm/Gallery", isDirectory: true)
        }
        originalsURL = self.rootURL.appendingPathComponent("originals", isDirectory: true)
        thumbsURL = self.rootURL.appendingPathComponent("thumbs", isDirectory: true)
        manifestURL = self.rootURL.appendingPathComponent("manifest.json", isDirectory: false)
        ensureFolders()
        reload()
    }

    var importCount: Int { items.count }

    func recent(limit: Int = 12) -> [GalleryItem] {
        Array(items.prefix(max(0, limit)))
    }

    func reload() {
        ensureFolders()
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode(Manifest.self, from: data)
        else {
            items = []
            return
        }
        items = decoded.items
            .filter { fileManager.fileExists(atPath: originalURL(for: $0).path) }
            .sorted { $0.createdAt > $1.createdAt }
        if items.count != decoded.items.count {
            saveManifest()
        }
    }

    @discardableResult
    func importPhoto(data: Data, title: String) throws -> GalleryItem {
        try writeEntry(
            data: data,
            title: title.isEmpty ? "照片" : title,
            kind: "import",
            recipe: nil,
            forkedFromID: nil,
            previewJPEG: nil
        )
    }

    /// Independent look: own original copy + own thumb + recipe. Deleting it never touches siblings.
    @discardableResult
    func saveVariant(
        originalData: Data,
        title: String,
        recipe: GalleryRecipe,
        previewJPEG: Data?,
        forkedFromID: String?
    ) throws -> GalleryItem {
        try writeEntry(
            data: originalData,
            title: title.isEmpty ? "方案" : title,
            kind: "variant",
            recipe: recipe,
            forkedFromID: forkedFromID,
            previewJPEG: previewJPEG
        )
    }

    func delete(id: String) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[index]
        try? fileManager.removeItem(at: originalURL(for: item))
        try? fileManager.removeItem(at: thumbURL(for: item))
        items.remove(at: index)
        saveManifest()
        logLine("SPEKTRAFILM_GALLERY_DELETE id=\(id) total=\(items.count)")
    }

    func item(id: String) -> GalleryItem? {
        items.first { $0.id == id }
    }

    func originalURL(for item: GalleryItem) -> URL {
        originalsURL.appendingPathComponent(item.originalName)
    }

    func thumbURL(for item: GalleryItem) -> URL {
        thumbsURL.appendingPathComponent(item.thumbName)
    }

    func loadOriginalData(for item: GalleryItem) throws -> Data {
        try Data(contentsOf: originalURL(for: item))
    }

    func loadThumb(for item: GalleryItem) -> UIImage? {
        let url = thumbURL(for: item)
        if let image = UIImage(contentsOfFile: url.path) { return image }
        guard let data = try? Data(contentsOf: originalURL(for: item)) else { return nil }
        if let image = UIImage(data: data) { return image }
        if let jpeg = Self.makeThumbJPEG(data: data, maxPixel: 512) {
            try? jpeg.write(to: url, options: .atomic)
            return UIImage(data: jpeg)
        }
        return nil
    }

    /// File-backed round trip used by `--frame-self-test`.
    static func selfCheck(in temporaryRoot: URL) -> [String] {
        var failures: [String] = []
        do {
            if FileManager.default.fileExists(atPath: temporaryRoot.path) {
                try FileManager.default.removeItem(at: temporaryRoot)
            }
            let store = ImportGalleryStore(rootURL: temporaryRoot)
            let payload = Self.syntheticJPEG()
            let item = try store.importPhoto(data: payload, title: "自测导入")
            if store.items.count != 1 { failures.append("count-after-import") }

            let recipeA = GalleryRecipe(
                filmID: "kodak_portra_400",
                paperID: "kodak_portra_endura",
                exposureEV: 0,
                frame: FrameEditState(),
                watermark: WatermarkEditState()
            )
            var recipeB = recipeA
            recipeB.exposureEV = 0.5
            let variantA = try store.saveVariant(
                originalData: payload,
                title: "方案 A",
                recipe: recipeA,
                previewJPEG: payload,
                forkedFromID: item.id
            )
            let variantB = try store.saveVariant(
                originalData: payload,
                title: "方案 B",
                recipe: recipeB,
                previewJPEG: payload,
                forkedFromID: item.id
            )
            if store.items.count != 3 { failures.append("count-after-variants") }
            if variantA.id == variantB.id { failures.append("variant-id-collision") }
            if variantA.originalName == variantB.originalName { failures.append("variant-file-shared") }

            store.reload()
            guard let reloadedA = store.item(id: variantA.id), let reloadedB = store.item(id: variantB.id) else {
                failures.append("variant-missing-after-reload")
                return failures
            }
            if reloadedA.recipe?.exposureEV != 0 { failures.append("recipe-a") }
            if reloadedB.recipe?.exposureEV != 0.5 { failures.append("recipe-b") }
            let bytesA = try store.loadOriginalData(for: reloadedA)
            let bytesB = try store.loadOriginalData(for: reloadedB)
            if bytesA != payload || bytesB != payload { failures.append("variant-bytes") }

            try store.delete(id: variantA.id)
            store.reload()
            if store.item(id: variantA.id) != nil { failures.append("variant-a-linger") }
            if store.item(id: variantB.id) == nil { failures.append("variant-b-lost") }
            if store.item(id: item.id) == nil { failures.append("import-lost") }
            let stillB = try store.loadOriginalData(for: store.item(id: variantB.id)!)
            if stillB != payload { failures.append("sibling-corrupt") }

            try store.delete(id: item.id)
            try store.delete(id: variantB.id)
            store.reload()
            if !store.items.isEmpty { failures.append("delete-linger") }
        } catch {
            failures.append("exception:\(error.localizedDescription)")
        }
        return failures
    }

    private func writeEntry(
        data: Data,
        title: String,
        kind: String,
        recipe: GalleryRecipe?,
        forkedFromID: String?,
        previewJPEG: Data?
    ) throws -> GalleryItem {
        ensureFolders()
        let id = UUID().uuidString.lowercased()
        let originalName = "\(id).bin"
        let thumbName = "\(id).jpg"
        let originalURL = originalsURL.appendingPathComponent(originalName)
        let thumbURL = thumbsURL.appendingPathComponent(thumbName)
        try data.write(to: originalURL, options: .atomic)
        if let previewJPEG, !previewJPEG.isEmpty {
            try previewJPEG.write(to: thumbURL, options: .atomic)
        } else if let thumb = Self.makeThumbJPEG(data: data, maxPixel: 512) {
            try thumb.write(to: thumbURL, options: .atomic)
        } else {
            logLine("SPEKTRAFILM_GALLERY_THUMB_FAIL bytes=\(data.count)")
        }
        let item = GalleryItem(
            id: id,
            title: title,
            createdAt: Date(),
            originalName: originalName,
            thumbName: thumbName,
            byteCount: data.count,
            kind: kind,
            recipe: recipe,
            forkedFromID: forkedFromID
        )
        items.insert(item, at: 0)
        saveManifest()
        let tag = kind == "variant" ? "VARIANT" : "IMPORT"
        logLine("SPEKTRAFILM_GALLERY_\(tag) id=\(id) bytes=\(data.count) total=\(items.count)")
        return item
    }

    private func ensureFolders() {
        for url in [rootURL, originalsURL, thumbsURL] {
            if !fileManager.fileExists(atPath: url.path) {
                try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

    private func saveManifest() {
        let payload = Manifest(schemaVersion: 2, items: items)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private static func makeThumbJPEG(data: Data, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixel),
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: true,
        ]
        var image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        if image == nil {
            image = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldAllowFloat: true,
            ] as CFDictionary)
        }
        guard let image else { return nil }
        let mutable = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutable, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutable as Data
    }

    private static func syntheticJPEG() -> Data {
        let size = CGSize(width: 64, height: 48)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 0.82, green: 0.55, blue: 0.28, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 8, y: 8, width: 16, height: 32))
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data([0xFF, 0xD8, 0xFF, 0xD9])
    }

    private struct Manifest: Codable {
        var schemaVersion: Int
        var items: [GalleryItem]
    }
}

enum LabStage: String, Equatable, Sendable {
    case home
    case gallery
    case editor
}
