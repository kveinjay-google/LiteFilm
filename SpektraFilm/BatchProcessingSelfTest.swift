import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum BatchProcessingSelfTest {
    static func run() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw EngineError.message("batch: " + message) }
        }
        var ownEdits = PhotoAdjustments()
        ownEdits.geometry.rotation = 1
        ownEdits.geometry.crop = PhotoCrop(x: 0.1, y: 0.2, width: 0.8, height: 0.7)
        ownEdits.shadows = 0.35
        ownEdits.retouch = RetouchEdits(layers: [RetouchLayer(kind: .radial, points: [RetouchPoint(x: 0.25, y: 0.7)])])
        let own = GalleryRecipe(filmID: "own", paperID: "paper", exposureEV: 0.5,
            frame: FrameEditState(), watermark: WatermarkEditState(), adjustments: ownEdits)
        var foreign = own
        foreign.filmID = "preset"; foreign.exposureEV = -0.25
        foreign.adjustments?.geometry.rotation = 3
        foreign.adjustments?.shadows = -0.6
        foreign.adjustments?.retouch = RetouchEdits(layers: [RetouchLayer(kind: .brush, points: [RetouchPoint(x: 0.8, y: 0.1)])])
        let merged = BatchRecipe.resolve(saved: own, fallback: foreign, override: foreign)
        try require(merged.filmID == "preset" && merged.exposureEV == -0.25, "global preset not copied")
        try require(merged.adjustments?.geometry == ownEdits.geometry, "preset replaced own geometry")
        try require(merged.adjustments?.retouch == ownEdits.retouch, "preset replaced local edits")
        try require(merged.adjustments?.shadows == -0.6, "global color missing")
        try require(BatchRecipe.resolve(saved: own, fallback: foreign, override: nil) == own, "own-recipe mode changed recipe")
        let imported = BatchRecipe.resolve(saved: nil, fallback: foreign, override: nil)
        try require(imported.filmID == "preset" && imported.adjustments?.geometry == PhotoGeometry(), "fallback imported spatial edits")
        try require(imported.adjustments?.retouch == RetouchEdits(), "fallback imported local edits")
        var options = BatchExportOptions()
        try options.validate()
        options.longEdge = -1
        do { try options.validate(); throw EngineError.message("batch: negative edge accepted") }
        catch BatchValidationError.invalidLongEdge { }
        options.longEdge = 2048; options.maxBytes = Int.max
        do { try options.validate(); throw EngineError.message("batch: overflowing bytes accepted") }
        catch BatchValidationError.invalidSizeLimit { }
        options.maxBytes = 0
        do { try options.validate(); throw EngineError.message("batch: zero cap accepted") }
        catch BatchValidationError.invalidSizeLimit { }
        try require(BatchSnapshot.maximumCount == 50, "batch count bound")
        let input = BatchInput(id: "sample", title: "test", sourceURL: URL(fileURLWithPath: "/sample"), recipe: merged)
        let snapshot = BatchSnapshot(inputs: [input], options: BatchExportOptions(), films: FilmCatalog(films: [], papers: []),
            frames: .empty, watermarks: .builtin, dateText: "2026.11.12")
        try snapshot.validate()
        foreign.filmID = "changed-after-snapshot"
        try require(snapshot.inputs[0].recipe.filmID == "preset", "snapshot changed with later settings")
        for count in [0, 51] {
            let invalid = BatchSnapshot(inputs: Array(repeating: input, count: count), options: BatchExportOptions(),
                films: snapshot.films, frames: snapshot.frames, watermarks: snapshot.watermarks, dateText: snapshot.dateText)
            do { try invalid.validate(); throw EngineError.message("batch: invalid count accepted") }
            catch BatchValidationError.invalidCount { }
        }
        logLine("LITEFILM_BATCH_SELFTEST_OK")
    }

    /// Run serially after editor work is quiescent. The largest source is 160×112;
    /// exports and the isolated source folder are removed even when an assertion fails.
    static func runRendering() async throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw EngineError.message("batch rendering: " + message) }
        }
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("LiteFilm-batch-selftest-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var generatedURLs: [URL] = []
        defer {
            for url in generatedURLs { try? fileManager.removeItem(at: url) }
            try? fileManager.removeItem(at: root)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true; format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 112), format: format).image { context in
            for y in 0..<7 {
                for x in 0..<10 {
                    UIColor(red: CGFloat(x + 1) / 11, green: CGFloat(y + 1) / 8,
                        blue: CGFloat((x + 2 * y) % 9 + 1) / 10, alpha: 1).setFill()
                    context.fill(CGRect(x: x * 16, y: y * 16, width: 16, height: 16))
                }
            }
        }
        guard let bytes = image.pngData() else { throw EngineError.message("batch rendering: synthetic PNG missing") }
        let sourceURL = root.appendingPathComponent("source.png")
        try bytes.write(to: sourceURL, options: .atomic)
        let films = try FilmCatalog.load()
        let frames = try FrameCatalog.load()
        let watermarks = WatermarkCatalog.builtin
        guard let film = films.film("kodak_portra_400") ?? films.films.first,
              let paper = films.paper("kodak_portra_endura") ?? films.papers.first,
              let markPreset = watermarks.presets.first else {
            throw EngineError.message("batch rendering: bundled catalog is incomplete")
        }
        try require(!frames.frames.isEmpty, "bundled frames unavailable")
        var frame = FrameEditState.makeDefault(catalog: frames)
        frame.ratio = FrameRatioState(mode: "locked", ratioId: "source")
        var watermark = WatermarkEditState()
        watermark.enabled = true; watermark.activeID = markPreset.id
        watermark.displayName = "Batch Test"; watermark.offsetX = 0.08; watermark.offsetY = -0.05
        var edits = PhotoAdjustments()
        edits.geometry.rotation = 1; edits.shadows = 0.15
        edits.retouch = RetouchEdits(layers: [RetouchLayer(kind: .radial,
            points: [RetouchPoint(x: 0.3, y: 0.6)], radius: 0.2, exposure: 0.25)])
        let recipe = GalleryRecipe(filmID: film.id, paperID: paper.id, exposureEV: 0.15,
            frame: frame, watermark: watermark, adjustments: edits,
            textLayers: [PhotoTextLayer(text: "Batch", size: 0.12, x: 0.5, y: 0.45)])

        for exportFormat in [ExportFormat.jpeg, .png] {
            let input = BatchInput(id: "good-\(exportFormat.rawValue)", title: "合成色卡", sourceURL: sourceURL, recipe: recipe)
            let missing = BatchInput(id: "missing-\(exportFormat.rawValue)", title: "缺失原片",
                sourceURL: root.appendingPathComponent("does-not-exist.png"), recipe: recipe)
            var settings = BatchExportOptions()
            settings.format = exportFormat
            settings.longEdge = exportFormat == .jpeg ? 1280 : 2048
            settings.maxBytes = exportFormat == .jpeg ? 10_000 : 100_000
            settings.includeFrame = exportFormat == .jpeg
            settings.includeWatermark = exportFormat == .jpeg
            settings.includeText = true
            let snapshot = BatchSnapshot(inputs: [input, missing], options: settings,
                films: films, frames: frames, watermarks: watermarks, dateText: "2026.11.12")
            // A later UI settings edit must not change this already-created job.
            settings.format = exportFormat == .jpeg ? .png : .jpeg
            settings.maxBytes = 1; settings.includeText = false
            try require(snapshot.options.format == exportFormat && snapshot.options.includeText,
                "captured export settings changed")

            // A file-specific error must be surfaced and must not poison the serial engine.
            var missingRejected = false
            do {
                let unexpected = try await BatchProcessor.shared.render(missing, snapshot: snapshot)
                if let url = unexpected.url { generatedURLs.append(url) }
            } catch {
                let failure = error as NSError
                missingRejected = failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoSuchFileError
            }
            try require(missingRejected, "missing source was not reported as a file-specific failure")

            let output = try await BatchProcessor.shared.render(input, snapshot: snapshot)
            guard let url = output.url else { throw EngineError.message("batch rendering: successful job has no URL") }
            generatedURLs.append(url)
            let exported = try Data(contentsOf: url)
            guard let source = CGImageSourceCreateWithData(exported as CFData, nil),
                  let type = CGImageSourceGetType(source),
                  let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw EngineError.message("batch rendering: output cannot be decoded")
            }
            try require(type as String == exportFormat.utType.identifier, "encoded type disagrees with requested format")
            try require(!exported.isEmpty && exported.count <= snapshot.options.maxBytes!, "per-file size cap not honored")
            try require(decoded.width > 0 && decoded.height > 0 && max(decoded.width, decoded.height) <= 160,
                "output exceeded source or final-canvas edge ceiling")
            try require(max(decoded.width, decoded.height) <= snapshot.options.longEdge, "selected long edge not honored")
            if exportFormat == .png {
                try require(decoded.width == 112 && decoded.height == 160, "unframed output lost saved quarter-turn geometry")
            }
            try require(output.id == input.id && output.title == input.title && output.succeeded, "result associated with wrong item")
            try require(output.detail.contains("\(decoded.width) × \(decoded.height)"), "reported dimensions disagree with file")
            try require(snapshot.inputs[0].recipe == recipe && snapshot.inputs[1].recipe == recipe,
                "render mutated captured per-photo recipe")
            try require(try Data(contentsOf: sourceURL) == bytes, "render modified original bytes")
            logLine("LITEFILM_BATCH_RENDER_OK format=\(exportFormat.rawValue) pixels=\(decoded.width)x\(decoded.height) bytes=\(exported.count)")
        }
        logLine("LITEFILM_BATCH_RENDER_SELFTEST_OK")
    }
}
