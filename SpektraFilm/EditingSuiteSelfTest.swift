import Foundation
import UIKit

/// Run only through the dedicated, externally timed self-test launch mode.
/// All state and synthetic imports are isolated from the user's preferences and gallery.
@MainActor
enum EditingSuiteSelfTest {
    static func run() async throws {
        try checkGalleryPaging()
        try AdvancedColorSelfTest.run()
        try RetouchSelfTest.run()
        try PhotoAnalysisSelfTest.run()
        try BatchProcessingSelfTest.run()
        try await BatchProcessingSelfTest.runRendering()
        let suite = "litefilm.editing-suite.test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw EngineError.message("editing suite defaults") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = recipeFixture()
        try checkRecipes(fixture, defaults: defaults, root: root)
        try await checkNativeUndo(defaults: defaults, root: root)
        try await checkModel(defaults: defaults, root: root)
        logLine("LITEFILM_EDITING_SUITE_SELFTEST_OK")
    }

    private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw EngineError.message("editing suite: " + message) }
    }

    private static func checkGalleryPaging() throws {
        // Exercise both axes, multi-page momentum, reverse overscroll and final-page bounds.
        for length: CGFloat in [393, 852, 1194] {
            try require(GalleryPageSnap.offset(projected: length * 0.8, pageLength: length, count: 8) == length,
                        "gallery ordinary swipe did not settle on next page")
            try require(GalleryPageSnap.offset(projected: length * 4.3, pageLength: length, count: 8) == length * 4,
                        "gallery momentum was restricted to one page")
            try require(GalleryPageSnap.offset(projected: -length * 2, pageLength: length, count: 8) == 0,
                        "gallery start overscroll")
            try require(GalleryPageSnap.offset(projected: length * 99, pageLength: length, count: 8) == length * 7,
                        "gallery final artwork not centered")
            try require(GalleryPageSnap.offset(projected: length, pageLength: length, count: 1) == 0,
                        "gallery single artwork")
        }
        try require(GalleryPageSnap.offset(projected: .nan, pageLength: 393, count: 8) == 0, "gallery invalid projection")
        try require(GalleryPageSnap.offset(projected: 800, pageLength: 0, count: 8) == 0, "gallery zero viewport")
        try require(GalleryPageSnap.offset(projected: 800, pageLength: 393, count: 0) == 0, "gallery empty collection")
        logLine("LITEFILM_GALLERY_PAGING_SELFTEST_OK")
    }

    private static func expectError(_ label: String, _ operation: () throws -> Void) throws {
        do { try operation() }
        catch { return }
        throw EngineError.message("editing suite: expected error for " + label)
    }

    private static func adjustmentsFixture() -> PhotoAdjustments {
        var adjustments = PhotoAdjustments(highlights: -0.11, shadows: 0.12, contrast: 0.13, saturation: -0.14,
            temperature: 0.15, tint: -0.16, blacks: 0.17, whites: -0.18,
            curve: ToneCurve(points: [0.01, 0.23, 0.52, 0.78, 0.99]))
        adjustments.hsl = (0..<6).map { i in
            let amount = Double(i + 1)
            return HSLBand(hue: amount * 0.02, saturation: amount * (-0.03), luminance: amount * 0.04)
        }
        adjustments.geometry = PhotoGeometry(angle: 2, crop: PhotoCrop(x: 0.1, y: 0.1, width: 0.8, height: 0.8))
        var radial = RetouchLayer(kind: .radial)
        radial.points = [RetouchPoint(x: 0.3, y: 0.4)]; radial.exposure = 0.3
        adjustments.retouch = RetouchEdits(layers: [radial])
        return adjustments
    }

    private static func recipeFixture() -> GalleryRecipe {
        GalleryRecipe(filmID: "kodak_portra_400", paperID: "kodak_portra_endura", exposureEV: 0.7,
            frame: FrameEditState(), watermark: WatermarkEditState(), adjustments: adjustmentsFixture(),
            textLayers: [PhotoTextLayer(text: "春日光影", x: 0.3, y: 0.7)])
    }

    private static func checkRecipes(_ recipe: GalleryRecipe, defaults: UserDefaults, root: URL) throws {
        let portable = RecipeBook.portable(recipe)
        var colorOnly = recipe.adjustments!
        colorOnly.geometry = PhotoGeometry(); colorOnly.retouch = RetouchEdits()
        try require(portable.adjustments == colorOnly, "portable must strip only spatial adjustments")
        try require(portable.frame == recipe.frame && portable.watermark == recipe.watermark && portable.textLayers == recipe.textLayers,
                    "portable lost frame/watermark/text")
        try require(portable.filmID == recipe.filmID && portable.paperID == recipe.paperID && portable.exposureEV == recipe.exposureEV,
                    "portable lost stock/exposure")
        let book = RecipeBook(defaults: defaults)
        try book.save(name: "  我的配方\n", recipe: recipe)
        try require(book.presets.count == 1 && book.presets[0].name == "我的配方", "trim preset name")
        try book.copy(recipe)
        let reloaded = RecipeBook(defaults: defaults)
        try require(reloaded.presets == book.presets && reloaded.copied == portable, "defaults recipe/clipboard roundtrip")
        // An explicit file roundtrip catches Codable failures without relying on UserDefaults caching.
        let diskURL = root.appendingPathComponent("recipes.json")
        try JSONEncoder().encode(book.presets).write(to: diskURL, options: .atomic)
        try require(try JSONDecoder().decode([SavedRecipe].self, from: Data(contentsOf: diskURL)) == book.presets, "disk recipe roundtrip")
        var detached = book.presets[0].recipe
        detached.adjustments!.hsl[0].hue = 0.95
        detached.textLayers![0].text = "changed"
        try require(book.presets[0].recipe == portable && book.copied == portable, "recipe/clipboard aliasing")
        let preserved = book.presets
        try expectError("blank preset name") { try book.save(name: " \n\t", recipe: recipe) }
        try require(book.presets == preserved, "failed save mutated library")
        try book.save(name: String(repeating: "长", count: 90), recipe: recipe)
        try require(book.presets[0].name.count == 60, "preset name limit")
        for index in book.presets.count..<50 { try book.save(name: "测试 \(index)", recipe: recipe) }
        try require(book.presets.count == 50 && Set(book.presets.map(\.id)).count == 50, "preset identities/limit")
        let beforeOverflow = book.presets
        try expectError("preset count") { try book.save(name: "第 51 个", recipe: recipe) }
        try require(book.presets == beforeOverflow, "overflow save changed library")
        let removed = book.presets[0].id
        try book.remove(id: removed)
        try require(book.presets.count == 49 && !book.presets.contains { $0.id == removed }, "delete preset")
        try require(RecipeBook(defaults: defaults).presets == book.presets, "delete persistence")
        try book.save(name: "空位可复用", recipe: recipe)
        try require(book.presets.count == 50, "slot not reusable")
        logLine("LITEFILM_RECIPE_SELFTEST_OK")
    }

    private static func checkModel(defaults: UserDefaults, root: URL) async throws {
        let gallery = ImportGalleryStore(rootURL: root.appendingPathComponent("gallery"))
        let model = LabModel(defaults: defaults, gallery: gallery)
        model.persistEnabled = false
        await model.bootstrap(); try await settled(model, "bootstrap")
        try require(model.preview != nil && model.errorText == nil, "bootstrap preview")
        let initial = model.currentRecipe()
        let advanced = adjustmentsFixture()
        model.applyAdjustments(advanced); try await settled(model, "advanced")
        try require(model.adjustments == advanced && model.canUndo && !model.canRedo, "advanced edit/history")
        try require(model.editHistory.count == 2 && model.historyCursor == 1, "one adjustment became multiple history steps")
        model.undo(); try await settled(model, "undo")
        try require(model.currentRecipe() == initial && !model.canUndo && model.canRedo, "undo all advanced fields")
        model.redo(); try await settled(model, "redo")
        try require(model.adjustments == advanced && !model.canRedo, "redo all advanced fields")
        model.undo(); try await settled(model, "branch undo")
        model.setExposure(0.7); model.finishPendingEdits(); try await settled(model, "branch")
        try require(model.exposureEV == 0.7 && model.adjustments == initial.adjustments && !model.canRedo, "redo branch not discarded")
        try require(model.editHistory.count == 2, "branch retained stale future")
        model.applyAdjustments(advanced); try await settled(model, "restore fixture")
        model.setTextLayers([PhotoTextLayer(text: "目标照片")]); try await settled(model, "target text")
        let target = model.currentRecipe()
        let portable = model.currentRecipe(portable: true)
        try require(portable.adjustments?.geometry == PhotoGeometry() && portable.adjustments?.retouch.isEmpty == true,
                    "current portable recipe includes spatial edits")
        try require(portable.textLayers == target.textLayers && portable.frame == target.frame, "current portable lost decoration")
        var imported = portable
        imported.exposureEV = -0.4
        imported.adjustments!.temperature = -0.32
        imported.adjustments!.curve = ToneCurve(points: [0, 0.3, 0.6, 0.8, 1])
        imported.adjustments!.hsl[4] = HSLBand(hue: -0.3, saturation: 0.2, luminance: -0.1)
        imported.adjustments!.geometry = PhotoGeometry(rotation: 1)
        imported.adjustments!.retouch = RetouchEdits()
        imported.textLayers = [PhotoTextLayer(text: "可复用的配方")]
        imported.frame.enabled = false
        let priorCount = model.editHistory.count
        model.applyPortableRecipe(imported); try await settled(model, "portable apply")
        try require(model.adjustments.geometry == advanced.geometry && model.adjustments.retouch == advanced.retouch,
                    "portable overwrote target geometry/retouch")
        try require(model.adjustments.temperature == -0.32 && model.adjustments.curve == imported.adjustments!.curve &&
                    model.adjustments.hsl == imported.adjustments!.hsl && model.exposureEV == -0.4, "portable color missing")
        try require(model.textLayers == imported.textLayers && !model.frame.enabled, "portable decorations missing")
        try require(model.editHistory.count == priorCount + 1, "recipe must be one undo action")
        let applied = model.currentRecipe()
        model.undo(); try await settled(model, "recipe undo")
        try require(model.currentRecipe() == target, "recipe undo incomplete")
        model.redo(); try await settled(model, "recipe redo")
        try require(model.currentRecipe() == applied, "recipe redo incomplete")
        model.resetAdjustments(); try await settled(model, "reset")
        try require(model.adjustments == PhotoAdjustments() && model.exposureEV == 0, "reset advanced fields")
        try require(model.textLayers == applied.textLayers && model.frame == applied.frame, "reset changed decorations")
        model.undo(); try await settled(model, "reset undo")
        try require(model.currentRecipe() == applied, "reset undo incomplete")
        var changedGeometry = model.adjustments.geometry; changedGeometry.angle = 3
        model.applyGeometry(changedGeometry); try await settled(model, "geometry invalidation")
        try require(model.adjustments.retouch.isEmpty, "geometry did not invalidate local coordinates")
        model.undo(); try await settled(model, "geometry undo")
        try require(model.adjustments.retouch == advanced.retouch && model.adjustments.geometry == advanced.geometry,
                    "geometry undo did not restore local edits")
        // Only this uniquely named preference suite is writable; never touch standard defaults.
        try require(defaults.data(forKey: "spektrafilm.edit.v1") == nil, "persistEnabled false wrote edit state")
        model.persistEnabled = true
        var changed = model.adjustments; changed.tint = 0.21
        model.applyAdjustments(changed); try await settled(model, "persist")
        model.persistEnabled = false
        guard let data = defaults.data(forKey: "spektrafilm.edit.v1") else { throw EngineError.message("editing suite: missing saved edit") }
        let saved = try JSONDecoder().decode(PersistedEdit.self, from: data)
        try require(saved.adjustments == changed && saved.textLayers == model.textLayers, "advanced fields not persisted")
        try require(saved.exposureEV == model.exposureEV, "exposure not persisted")
        let checkpoint = model.editHistory[1]
        model.restoreHistory(id: checkpoint.id); try await settled(model, "history selection")
        try require(model.historyCursor == 1 && model.canRedo && model.exposureEV == checkpoint.snapshot.exposureEV &&
                    model.adjustments == checkpoint.snapshot.adjustments, "history jump wrong snapshot")
        // Only a tiny synthetic card is imported; no camera roll or user photo is accessed.
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let tiny = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 48), format: format).image { _ in
            UIColor(white: 0.4, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 64, height: 48))
        }
        guard let png = tiny.pngData() else { throw EngineError.message("editing suite: synthetic photo") }
        let importedItem = try gallery.importPhoto(data: png, title: "isolated synthetic fixture")
        let nativeUndo = UndoManager()
        model.undoManager = nativeUndo
        try require(nativeUndo.canUndo && nativeUndo.canRedo, "native history attachment lost cursor")
        await model.openImport(id: importedItem.id); try await settled(model, "photo switch")
        try require(model.editHistory.isEmpty && !model.canUndo && !model.canRedo, "history crossed photo boundary")
        try require(!nativeUndo.canUndo && !nativeUndo.canRedo, "native actions crossed photo boundary")
        try require(model.adjustments == PhotoAdjustments() && model.textLayers.isEmpty, "photo inherited spatial/color edits")
        model.applyAdjustments(advanced); try await settled(model, "import edit")
        await model.showSample(); try await settled(model, "sample switch")
        try require(model.editHistory.isEmpty && model.adjustments == PhotoAdjustments() && !model.canRedo,
                    "sample switch retained prior history")
        // A model without bootstrap exercises the history bound without scheduling engine work.
        let historyOnly = LabModel(defaults: defaults, gallery: gallery)
        historyOnly.persistEnabled = false
        for index in 1...70 {
            var edits = PhotoAdjustments(); edits.temperature = Double(index) / 100
            historyOnly.applyAdjustments(edits)
        }
        try require(historyOnly.editHistory.count == 61 && historyOnly.historyCursor == 60, "history capacity")
        logLine("LITEFILM_EDITING_MODEL_SELFTEST_OK")
    }

    private static func checkNativeUndo(defaults: UserDefaults, root: URL) async throws {
        // No bootstrap: exercise UIKit history bookkeeping without any engine work.
        let model = LabModel(defaults: defaults, gallery: ImportGalleryStore(rootURL: root.appendingPathComponent("native-history")))
        model.persistEnabled = false
        let manager = UndoManager() // Keep default event grouping to cover real UIKit behavior.
        model.undoManager = manager
        defer { model.undoManager = nil }
        func nativeState(_ manager: UndoManager) -> String {
            "groupingLevel=\(manager.groupingLevel) canUndo=\(manager.canUndo) canRedo=\(manager.canRedo) groupsByEvent=\(manager.groupsByEvent) cursor=\(model.historyCursor) count=\(model.editHistory.count)"
        }
        func edit(_ temperature: Double) {
            var value = model.adjustments; value.temperature = temperature
            model.applyAdjustments(value)
        }
        edit(0.1); edit(0.2); edit(0.3)
        logLine("LITEFILM_NATIVE_HISTORY_INITIAL \(nativeState(manager))")
        try require(manager.groupingLevel == 0 && manager.canUndo && !manager.canRedo && manager.groupsByEvent,
                    "native groups leaked / initial availability: \(nativeState(manager))")
        try require(manager.undoActionName == "调色", "native action lost descriptive title")
        manager.undo()
        try require(model.adjustments.temperature == 0.2 && model.historyCursor == 2 && manager.canRedo, "native undo did not move shared cursor")
        model.undo()
        try require(model.adjustments.temperature == 0.1 && model.historyCursor == 1 && manager.canRedo, "toolbar undo after native undo")
        manager.redo()
        try require(model.adjustments.temperature == 0.2 && model.historyCursor == 2, "native redo after toolbar undo")
        model.redo()
        try require(model.adjustments.temperature == 0.3 && !manager.canRedo, "toolbar redo after native redo")
        model.restoreHistory(id: model.editHistory[1].id)
        try require(model.adjustments.temperature == 0.1 && manager.canUndo && manager.canRedo, "history jump lost native stacks")
        manager.redo()
        try require(model.adjustments.temperature == 0.2, "native redo after history jump")
        edit(0.4)
        try require(!manager.canRedo && model.editHistory.count == 4, "native redo survived a new branch")
        manager.undo(); manager.redo()
        try require(model.adjustments.temperature == 0.4 && model.historyCursor == 3, "native branch undo/redo")
        let replacement = UndoManager()
        model.undoManager = replacement
        try require(!manager.canUndo && !manager.canRedo && replacement.canUndo, "manager replacement retained stale actions")
        model.restoreHistory(id: model.editHistory[0].id)
        try require(!replacement.canUndo && replacement.canRedo && model.adjustments.temperature == 0, "jump to initial state")
        replacement.redo()
        try require(model.adjustments.temperature == 0.1, "replacement redo cursor")
        model.setExposure(0.7) // Native Undo can arrive before the slider debounce settles.
        replacement.undo()
        for _ in 0..<4 { await Task.yield() }
        try require(model.exposureEV == 0 && model.adjustments.temperature == 0.1 && replacement.canUndo && replacement.canRedo,
                    "pending slider native undo skipped the pending edit or lost stacks")
        replacement.redo()
        try require(model.exposureEV == 0.7, "pending slider native redo")
        for index in 1...70 { edit(Double(index) / 100) }
        try require(model.editHistory.count == 61 && model.historyCursor == 60, "native history bound")
        let oldest = model.editHistory[0].snapshot
        for _ in 0..<60 { replacement.undo() }
        try require(!replacement.canUndo && replacement.canRedo && model.historyCursor == 0 && model.adjustments == oldest.adjustments,
                    "native undo exceeded bounded timeline")
        for _ in 0..<60 { replacement.redo() }
        try require(!replacement.canRedo && model.historyCursor == 60 && model.adjustments.temperature == 0.7,
                    "native redo failed across bounded timeline")
        model.undoManager = nil
        model.undo()
        try require(model.historyCursor == 59 && model.canRedo, "nil native manager broke toolbar history")
        model.undoManager = replacement
        replacement.beginUndoGrouping()
        edit(0.81); edit(0.82)
        replacement.endUndoGrouping()
        // UIKit's implicit outer event group closes on the next run-loop turn.
        // The bridge must defer until then instead of closing someone else's group.
        for _ in 0..<20 {
            if replacement.groupingLevel == 0 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        logLine("LITEFILM_NATIVE_HISTORY_EXTERNAL_GROUP \(nativeState(replacement))")
        try require(replacement.groupingLevel == 0 && replacement.canUndo && !replacement.canRedo,
                    "external undo group blocked timeline synchronization: \(nativeState(replacement))")
        replacement.undo()
        try require(model.adjustments.temperature == 0.81, "native edits were accidentally grouped together")
        logLine("LITEFILM_NATIVE_HISTORY_SELFTEST_OK")
    }

    private static func settled(_ model: LabModel, _ phase: String) async throws {
        await model.waitUntilSettled()
        try require(!model.busy && model.errorText == nil, "\(phase): \(model.errorText ?? "render did not settle")")
    }
}
