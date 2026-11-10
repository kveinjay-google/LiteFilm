import CoreGraphics
import Foundation
import UIKit

enum AdjustmentSelfTest {
    static func run() throws {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = true
        let card = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240), format: fmt).image { _ in
            for column in 0..<8 {
                UIColor(white: CGFloat(column + 1) / 10, alpha: 1).setFill()
                UIRectFill(CGRect(x: column * 40, y: 0, width: 40, height: 240))
            }
        }.cgImage!
        let neutral = try PhotoProcessor.apply(card, settings: PhotoAdjustments())
        try require(neutral.width == 320 && neutral.height == 240 && abs(SelfTest.meanLuma(neutral) - SelfTest.meanLuma(card)) < 0.5, "neutral image changed")
        var settings = PhotoAdjustments()
        settings.geometry.crop = PhotoCrop(x: 0.25, y: 0, width: 0.5, height: 1)
        let cropped = try PhotoProcessor.apply(card, settings: settings)
        try require(cropped.width == 160 && cropped.height == 240, "crop dimensions")
        settings.geometry = PhotoGeometry(); settings.geometry.rotation = 1
        let turned = try PhotoProcessor.apply(card, settings: settings)
        try require(turned.width == 240 && turned.height == 320, "quarter-turn dimensions")
        settings.geometry = PhotoGeometry()
        settings.shadows = 0.8
        let shadows = try PhotoProcessor.apply(card, settings: settings)
        try require(SelfTest.meanLuma(shadows) > SelfTest.meanLuma(card) + 2, "shadows must brighten")
        settings.shadows = 0; settings.highlights = -0.8
        let highlights = try PhotoProcessor.apply(card, settings: settings)
        try require(SelfTest.meanLuma(highlights) < SelfTest.meanLuma(card) - 2, "highlights must darken")
        settings = PhotoAdjustments()
        settings.geometry.angle = 30; settings.geometry.vertical = 0.8
        settings.geometry.horizontal = -0.6; settings.geometry.distortion = 0.7
        for (name, geometry) in [("angle", PhotoGeometry(angle: 30)), ("perspective", PhotoGeometry(vertical: 0.8, horizontal: -0.6)), ("lens", PhotoGeometry(distortion: 0.7)), ("combined", settings.geometry)] {
            let probe = try PhotoProcessor.geometry(card, settings: geometry)
            logLine("LITEFILM_ALPHA_PROBE \(name) opaque=\(isOpaque(probe))")
        }
        let warped = try PhotoProcessor.apply(card, settings: settings)
        try require(warped.width > 0 && warped.height > 0, "geometry output")
        try require(isOpaque(warped), "geometry has transparent borders")
        var corrupt = PhotoAdjustments()
        corrupt.shadows = .nan; corrupt.geometry.angle = .infinity
        corrupt.geometry.crop = PhotoCrop(x: -5, y: 2, width: 0, height: .nan)
        let sanitized = corrupt.sanitized()
        _ = try JSONEncoder().encode(sanitized)
        let safe = try PhotoProcessor.apply(card, settings: corrupt)
        try require(safe.width > 0 && safe.height > 0, "invalid edit must remain renderable")
        let archived = try JSONEncoder().encode(settings)
        try require(try JSONDecoder().decode(PhotoAdjustments.self, from: archived) == settings, "adjustment archive")
        // Legacy archives have no adjustments field and must still decode.
        let legacy = Data("{\"schemaVersion\":5,\"exposureEV\":0}".utf8)
        try require(try JSONDecoder().decode(PersistedEdit.self, from: legacy).adjustments == nil, "legacy decode")
        logLine("LITEFILM_ADJUSTMENT_PIXEL_OK")
    }

    @MainActor
    static func checkModel() async throws {
        let suite = "litefilm.adjustments.selftest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let galleryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: galleryRoot) }
        let model = LabModel(defaults: defaults)
        model.gallery = ImportGalleryStore(rootURL: galleryRoot)
        await model.bootstrap()
        await model.waitUntilSettled()
        guard model.errorText == nil, let original = model.originalPreview?.cgImage else {
            throw EngineError.message("adjustment model bootstrap")
        }
        model.chooseNoFrame(); model.setWatermarkEnabled(false)
        await model.waitUntilSettled()
        let code = model.stockCode(model.catalog.films.last!.id, papers: false)
        let selected = model.filmID
        let film = model.catalog.films.last!.id, paper = model.catalog.papers.last!.id
        model.toggleFavorite(film, papers: false); model.toggleFavorite(paper, papers: true)
        try require(model.stocks(papers: false).first?.id == film && model.stocks(papers: true).first?.id == paper, "favorites not first")
        try require(model.stockCode(film, papers: false) == code && model.filmID == selected, "favorite changed code or selection")
        let reloaded = LabModel(defaults: defaults)
        try require(reloaded.isFavorite(film, papers: false) && reloaded.isFavorite(paper, papers: true), "favorite persistence")
        model.toggleFavorite(film, papers: false)
        try require(model.stocks(papers: false).map(\.id) == model.catalog.films.map(\.id), "unfavorite order")
        model.setExposure(0.6); model.setAdjustment(\.shadows, 0.45)
        await model.waitUntilSettled()
        var geometry = PhotoGeometry()
        geometry.crop = PhotoCrop(x: 0.2, y: 0, width: 0.6, height: 1)
        geometry.angle = 3
        model.applyGeometry(geometry)
        await model.waitUntilSettled()
        try require(model.adjustments.geometry == geometry, "geometry apply")
        guard let edited = model.preview?.cgImage else { throw EngineError.message("missing edited preview") }
        try require(abs(Double(edited.width) / Double(edited.height) - 0.9) < 0.01, "model cropped aspect")
        model.undo()
        await model.waitUntilSettled()
        try require(model.adjustments.geometry == PhotoGeometry() && model.adjustments.shadows == 0.45, "geometry undo altered tone")
        model.applyGeometry(geometry)
        await model.waitUntilSettled()
        let saved = try JSONDecoder().decode(PersistedEdit.self, from: defaults.data(forKey: "spektrafilm.edit.v1")!)
        try require(saved.adjustments == model.adjustments, "persisted adjustment mismatch")
        model.saveCurrentLookToGallery()
        guard let variant = model.gallery.items.first else { throw EngineError.message("missing variant") }
        try require(variant.recipe?.adjustments == model.adjustments, "gallery did not store adjustment")
        let keep = model.adjustments
        model.resetAdjustments()
        await model.waitUntilSettled()
        await model.openImport(id: variant.id)
        await model.waitUntilSettled()
        try require(model.adjustments == keep && model.exposureEV == 0.6, "gallery did not restore adjustments")
        model.export(.png, includeFrame: false, includeWatermark: false)
        await model.waitUntilSettled()
        guard let url = model.shareURL, let exported = UIImage(contentsOfFile: url.path)?.cgImage,
              let preview = model.preview?.cgImage else { throw EngineError.message("adjustment export failed") }
        try require(abs(Double(exported.width) / Double(exported.height) - 0.9) < 0.01, "export crop differs")
        try require(abs(SelfTest.meanLuma(exported) - SelfTest.meanLuma(preview)) < 8, "export tone differs")
        try require(model.originalPreview?.cgImage?.width == original.width, "original was destructively cropped")
        let sampleURL = Bundle.main.url(forResource: "SampleBars", withExtension: "png")!
        let broken = try model.gallery.importPhoto(data: Data(contentsOf: sampleURL), title: "Broken test")
        try Data("invalid image".utf8).write(to: galleryRoot.appendingPathComponent("originals").appendingPathComponent(broken.originalName))
        await model.openImport(id: broken.id)
        try require(model.errorText != nil && model.adjustments == keep, "failed gallery open changed active edit")
        await model.showSample()
        await model.waitUntilSettled()
        try require(model.adjustments.geometry == PhotoGeometry() && !model.canUndo, "source switch retained geometry or cross-photo undo")
        logLine("LITEFILM_ADJUSTMENT_MODEL_OK favorites=1 undo=1 archive=1 variant=1 export=1 sourceIsolation=1")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw EngineError.message(message) }
    }

    private static func isOpaque(_ image: CGImage) -> Bool {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let alpha = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
        if let minimum = alpha.min(), minimum < 254 {
            logLine("LITEFILM_ALPHA_MIN \(minimum) count=\(alpha.filter { $0 < 254 }.count) first=\(alpha.firstIndex(where: { $0 < 254 }) ?? -1)")
        }
        return alpha.allSatisfy { $0 >= 254 }
    }
}
