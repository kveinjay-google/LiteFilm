import CoreGraphics
import Foundation
import UIKit

enum FrameCheck: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

enum FrameSelfTest {
    @MainActor
    static func run() async -> Int32 {
        logLine("SPEKTRAFILM_FRAME_SELFTEST_START")
        if let url = FrameLog.url {
            logLine("SPEKTRAFILM_FRAME_LOG \(url.path)")
        }
        var failed = false
        let gesture = FrameGestureDecider.selfCheck()
        let sequence = FrameGestureDecider.sequenceCheck()
        if gesture.isEmpty && sequence.failures.isEmpty {
            logLine("SPEKTRAFILM_FRAME_GESTURE_OK")
            logLine("SPEKTRAFILM_FRAME_GESTURE_SEQUENCE commits=\(sequence.commits) resets=\(sequence.resets) doubleFire=0")
        } else {
            failed = true
            let names = gesture + sequence.failures
            logLine("SPEKTRAFILM_FRAME_GESTURE_FAIL \(names.joined(separator: ","))")
        }
        let galleryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spektrafilm-gallery-selftest-\(UUID().uuidString)", isDirectory: true)
        let galleryFails = await MainActor.run {
            ImportGalleryStore.selfCheck(in: galleryRoot)
        }
        if galleryFails.isEmpty {
            logLine("SPEKTRAFILM_GALLERY_STORE_OK")
        } else {
            failed = true
            logLine("SPEKTRAFILM_GALLERY_STORE_FAIL \(galleryFails.joined(separator: ","))")
        }
        let preferences = PreviewTransition.preferenceFailures()
        if preferences.isEmpty {
            logLine("SPEKTRAFILM_TRANSITION_PREF_OK")
        } else {
            failed = true
            logLine("SPEKTRAFILM_TRANSITION_PREF_FAIL \(preferences.joined(separator: ","))")
        }
        do {
            let catalog = try FrameCatalog.load()
            try checkWatermarkIdentityAndSelection()
            try checkCatalog(catalog)
            try checkLayouts(catalog)
            try checkPixels(catalog)
            logLine("SPEKTRAFILM_FRAME_PIXEL_OK")
        } catch {
            failed = true
            logLine("SPEKTRAFILM_FRAME_PIXEL_FAIL \(error.localizedDescription)")
        }
        if await checkEngine() != 0 {
            failed = true
        }
        logLine(failed ? "SPEKTRAFILM_FRAME_SELFTEST_FAIL" : "SPEKTRAFILM_FRAME_SELFTEST_OK")
        return failed ? 1 : 0
    }

    @MainActor
    private static func checkWatermarkIdentityAndSelection() throws {
        let identity = WatermarkIdentity.blank
        guard identity.resolvedStudio == "LITEFILM",
              identity.resolvedSignature == "LiteFilm",
              identity.resolvedMonogram == "LF",
              identity.resolvedInitial == "L",
              identity.resolvedSite == "SUPERAITEST.COM/LITEFILM"
        else { throw FrameCheck.message("LiteFilm 默认署名") }
        let custom = WatermarkIdentity(displayName: "Kevin", studioName: "Spektra Lab", copyrightLine: "© Custom", monogram: "KV", siteURL: "kevin.film")
        guard custom.resolvedSignature == "Kevin", custom.resolvedStudio == "SPEKTRA LAB",
              custom.resolvedCopyright(year: "2026") == "© Custom",
              custom.resolvedMonogram == "KV", custom.resolvedSite == "KEVIN.FILM"
        else { throw FrameCheck.message("自定义署名被改写") }
        let suite = "litefilm.watermark.selection.selftest"
        guard let defaults = UserDefaults(suiteName: suite) else { throw FrameCheck.message("测试设置") }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = LabModel(defaults: defaults)
        model.watermark.displayName = "Kevin"
        model.watermark.offsetX = 0.1
        let before = model.watermark
        model.chooseWatermark("invalid-id")
        guard model.watermark == before, !model.canUndo else { throw FrameCheck.message("无效水印改变编辑") }
        let pendingPaper = try FilmCatalog.load().papers.last?.id ?? model.paperID
        model.previewPaper(pendingPaper)
        model.chooseWatermark("wm_17")
        model.chooseWatermark("wm_17")
        guard model.watermark.enabled, model.watermark.activeID == "wm_17",
              model.watermark.displayName == before.displayName, model.watermark.offsetX == before.offsetX,
              let data = defaults.data(forKey: "spektrafilm.edit.v1"),
              let saved = try? JSONDecoder().decode(PersistedEdit.self, from: data),
              saved.watermark == model.watermark, saved.paperID == pendingPaper,
              model.paperID == pendingPaper
        else { throw FrameCheck.message("水印直接选择与保存") }
        model.undo()
        guard model.watermark == before, model.engineRenderCount == 0 else { throw FrameCheck.message("水印直接选择撤销") }
        logLine("SPEKTRAFILM_WATERMARK_SELECTION_IDENTITY_OK")
    }

    private static func checkCatalog(_ catalog: FrameCatalog) throws {
        let ids = Set(catalog.frames.map(\.id))
        guard catalog.frames.count == 36, ids.count == 36 else {
            throw FrameCheck.message("相框数量 \(catalog.frames.count)")
        }
        guard catalog.families.count == 6 else { throw FrameCheck.message("系列数量") }
        for family in catalog.families {
            guard catalog.frames(in: family.id).count == 6 else {
                throw FrameCheck.message("系列 \(family.id) 不是 6 款")
            }
        }
        guard catalog.ratioOptions.count == 12 else { throw FrameCheck.message("比例数量") }
        let required = ["source", "auto", "1:1", "4:5", "3:4", "2:3", "4:3", "3:2", "16:9", "9:16", "65:24", "5:7"]
        for id in required where !catalog.ratioOptions.contains(where: { $0.id == id }) {
            throw FrameCheck.message("缺少比例 \(id)")
        }
        guard catalog.frame("gallery_01") != nil else { throw FrameCheck.message("缺少 gallery_01") }
        let structures = Set(catalog.frames.map(\.structure))
        guard structures.count >= 10 else { throw FrameCheck.message("结构种类太少") }
        let navigation = catalog.globalNavigationFailures()
        guard navigation.isEmpty else { throw FrameCheck.message("全局切框 \(navigation.joined(separator: ","))") }
        let marks = WatermarkCatalog.builtin
        guard marks.presets.count >= 30 else { throw FrameCheck.message("水印只有 \(marks.presets.count)") }
        let markNavigation = marks.navigationFailures()
        guard markNavigation.isEmpty else { throw FrameCheck.message("水印顺序 \(markNavigation.joined(separator: ","))") }
        let old = Data(#"{"schemaVersion":1,"filmID":"kodak_portra_400","exposureEV":0.2}"#.utf8)
        let decoded = try JSONDecoder().decode(PersistedEdit.self, from: old)
        guard decoded.watermark == nil, decoded.exportIncludeFrame == nil, decoded.previewTransition == nil else {
            throw FrameCheck.message("旧存档被新字段挡住")
        }
        let round = PersistedEdit(
            schemaVersion: 4,
            filmID: "kodak_portra_400",
            paperID: nil,
            exposureEV: 0.2,
            frame: nil,
            watermark: nil,
            exportIncludeFrame: true,
            exportIncludeWatermark: false,
            previewTransition: "slideFade"
        )
        let encoded = try JSONEncoder().encode(round)
        let back = try JSONDecoder().decode(PersistedEdit.self, from: encoded)
        guard back.previewTransition == "slideFade",
              back.filmID == "kodak_portra_400",
              back.exposureEV == 0.2,
              PreviewTransition.resolve(back.previewTransition) == .slideFade
        else {
            throw FrameCheck.message("切换效果没有随存档走")
        }
        logLine("SPEKTRAFILM_FRAME_CATALOG_OK ids=36 families=6 ratios=12 structures=\(structures.count)")
        logLine("SPEKTRAFILM_FRAME_GLOBAL_OK forward=\(catalog.frames.count) reverse=\(catalog.frames.count) ends=gallery_01,none")
        logLine("SPEKTRAFILM_WATERMARK_CATALOG count=\(marks.presets.count) kinds=\(Set(marks.presets.map(\.kind)).count)")
    }

    private static func checkLayouts(_ catalog: FrameCatalog) throws {
        guard let preset = catalog.frame("gallery_01") else { throw FrameCheck.message("gallery_01") }
        let cases: [(String, CGSize, String)] = [
            ("landscape", CGSize(width: 3000, height: 2000), "source"),
            ("portrait", CGSize(width: 2000, height: 3000), "source"),
            ("square", CGSize(width: 2000, height: 2000), "1:1"),
            ("panorama", CGSize(width: 6500, height: 2400), "65:24"),
            ("auto", CGSize(width: 3000, height: 2000), "auto"),
            ("four-five", CGSize(width: 2000, height: 3000), "4:5"),
        ]
        for item in cases {
            let mode = catalog.canvasMode(ratioID: item.2, source: item.1)
            let layout = try FrameGeometry.layout(
                sourceWidth: item.1.width,
                sourceHeight: item.1.height,
                insets: preset.inset,
                mode: mode,
                longEdge: 1024
            )
            let got = layout.photo.width / layout.photo.height
            let want = item.1.width / item.1.height
            guard abs(Double(got - want) / Double(want)) < 0.01 else {
                throw FrameCheck.message("\(item.0) 照片比例 \(got) != \(want)")
            }
            guard layout.photo.minX >= -0.6, layout.photo.minY >= -0.6,
                  layout.photo.maxX <= layout.canvasWidth + 0.6,
                  layout.photo.maxY <= layout.canvasHeight + 0.6
            else { throw FrameCheck.message("\(item.0) 照片超出画布") }
            logLine(String(
                format: "SPEKTRAFILM_FRAME_LAYOUT %@ canvas=%.0fx%.0f photo=%.1f,%.1f %.1fx%.1f",
                item.0, layout.canvasWidth, layout.canvasHeight,
                layout.photo.minX, layout.photo.minY, layout.photo.width, layout.photo.height
            ))
        }
        let wide = try FrameGeometry.layout(
            sourceWidth: 6500, sourceHeight: 2400,
            insets: preset.inset,
            mode: catalog.canvasMode(ratioID: "65:24", source: CGSize(width: 6500, height: 2400)),
            longEdge: 2048
        )
        let canvasAspect = wide.canvasWidth / wide.canvasHeight
        guard abs(canvasAspect - CGFloat(65.0 / 24.0)) < 0.02 else {
            throw FrameCheck.message("65:24 画布比例 \(canvasAspect)")
        }
    }

    private static func checkPixels(_ catalog: FrameCatalog) throws {
        guard let photo = FramePainter.syntheticPhoto(width: 96, height: 64),
              let raw = FramePainter.pixels8(photo)
        else { throw FrameCheck.message("做不出测试图") }
        let left = sample(raw, 1, 32)
        let right = sample(raw, 94, 32)
        logLine("SPEKTRAFILM_FRAME_GRADIENT left=\(left) right=\(right)")
        guard left.r > 200, left.b < 40, right.b > 200, right.r < 40 else {
            throw FrameCheck.message("测试图通道不对 left=\(left) right=\(right)")
        }
        let source = CGSize(width: 96, height: 64)
        for preset in catalog.frames {
            let request = PaintRequest(
                photo: photo,
                preset: preset,
                mode: .originalAspect,
                sourceWidth: 96,
                sourceHeight: 64,
                filmLabel: preset.annotation.mode == "selected_film" ? "Portra 400" : "",
                bits: 8,
                opaqueBackdrop: false
            )
            guard let image = FramePainter.composite(request),
                  let pixels = FramePainter.pixels8(image)
            else { throw FrameCheck.message("\(preset.id) 没有画出来") }
            let layout = try FrameGeometry.layout(
                sourceWidth: 96, sourceHeight: 64,
                insets: preset.inset, mode: .originalAspect,
                longEdge: 96
            )
            let y = Int(layout.photo.midY.rounded())
            let leftX = Int((layout.photo.minX + layout.photo.width * 0.22).rounded())
            let rightX = Int((layout.photo.minX + layout.photo.width * 0.78).rounded())
            let leftPixel = sample(pixels, leftX, y)
            let rightPixel = sample(pixels, rightX, y)
            guard leftPixel.a > 200, rightPixel.a > 200,
                  leftPixel.r > rightPixel.r + 12, rightPixel.b > leftPixel.b + 12
            else {
                throw FrameCheck.message("\(preset.id) 照片窗口被挡住 left=\(leftPixel) right=\(rightPixel)")
            }
            let marginX = max(1, Int((layout.left * 0.45).rounded()))
            let margin = sample(pixels, marginX, y)
            guard margin.a > 180 else {
                throw FrameCheck.message("\(preset.id) 纸边是透明的")
            }
            let proofIDs = [
                "gallery_01", "gallery_02", "gallery_03", "gallery_04", "gallery_05", "gallery_06",
                "darkroom_01", "film_01", "instant_01", "editorial_01", "editorial_02",
                "archive_02", "archive_03", "archive_06",
            ]
            if proofIDs.contains(preset.id) {
                _ = try writeProof(image, name: "synthetic-\(preset.id)")
            }
            let matCleanIDs = [
                "gallery_01", "gallery_03", "gallery_05",
                "editorial_01", "editorial_02",
                "archive_03", "archive_06",
            ]
            if matCleanIDs.contains(preset.id) {
                _ = try writeProof(image, name: "mat-clean-\(preset.id)")
            }
            // Flat light/near-gray mats must be solid paper — no grain speckles or accent stains.
            try assertFlatLightMat(preset: preset, image: image, layout: layout, pixels: pixels)
            _ = source
        }
        guard let wide = FramePainter.syntheticPhoto(width: 480, height: 320),
              let bar = WatermarkCatalog.builtin.preset("wm_09"),
              let marked = WatermarkPainter.apply(wide, preset: bar, info: .blank),
              let before = FramePainter.pixels8(wide),
              let after = FramePainter.pixels8(marked),
              changed(before, after)
        else { throw FrameCheck.message("水印没有画出来") }
        guard let signature = WatermarkCatalog.builtin.preset("wm_01") else {
            throw FrameCheck.message("缺少右下签名")
        }
        guard let paper = solidCard(width: 480, height: 320, color: UIColor(red: 0.96, green: 0.945, blue: 0.91, alpha: 1)),
              let onPaper = WatermarkPainter.apply(paper, preset: signature, info: .blank),
              let paperBefore = FramePainter.pixels8(paper),
              let paperAfter = FramePainter.pixels8(onPaper),
              changed(paperBefore, paperAfter)
        else { throw FrameCheck.message("亮纸上看不见右下签名") }
        guard let dark = solidCard(width: 480, height: 320, color: UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)),
              let onDark = WatermarkPainter.apply(dark, preset: signature, info: .blank),
              let darkBefore = FramePainter.pixels8(dark),
              let darkAfter = FramePainter.pixels8(onDark),
              changed(darkBefore, darkAfter)
        else { throw FrameCheck.message("暗底上看不见右下签名") }
        let identity = WatermarkIdentity(displayName: "KEVINZX", studioName: "DARKROOM", monogram: "KX")
        guard let named = WatermarkPainter.apply(paper, preset: signature, info: .blank, identity: identity),
              let plain = WatermarkPainter.apply(paper, preset: signature, info: .blank),
              changed(named, plain)
        else { throw FrameCheck.message("自定义署名没有进画") }
        let content = CGRect(x: 72, y: 48, width: 336, height: 224)
        guard let boxed = WatermarkPainter.apply(
            paper,
            preset: signature,
            info: .blank,
            identity: identity,
            contentRect: content
        ),
              let paperPixels = FramePainter.pixels8(paper),
              let boxedPixels = FramePainter.pixels8(boxed)
        else { throw FrameCheck.message("内容区水印没有画出来") }
        // Mat / outer canvas corners must stay untouched when the credit is clipped to contentRect.
        for (x, y) in [(2, 2), (paper.width - 3, 2), (2, paper.height - 3), (paper.width - 3, paper.height - 3)] {
            let before = sample(paperPixels, x, y)
            let after = sample(boxedPixels, x, y)
            guard before == after else {
                throw FrameCheck.message("水印画到内容区外 corner=\(x),\(y)")
            }
        }
        guard changed(paper, boxed) else { throw FrameCheck.message("开窗内看不见水印") }
        // A mid-left mat sample outside the opening must stay identical.
        let outsideX = max(2, Int(content.minX * 0.35))
        let outsideY = Int(content.midY)
        let beforeOut = sample(paperPixels, outsideX, outsideY)
        let afterOut = sample(boxedPixels, outsideX, outsideY)
        guard beforeOut == afterOut else { throw FrameCheck.message("水印画到开窗外的卡纸上") }
        guard let shifted = WatermarkPainter.apply(
            paper,
            preset: signature,
            info: .blank,
            identity: identity,
            contentRect: content,
            offset: CGSize(width: -0.18, height: -0.12)
        ), changed(boxed, shifted)
        else { throw FrameCheck.message("水印偏移没有生效") }
        try writeWatermarkSheet()
        logLine("SPEKTRAFILM_WATERMARK_PIXEL_OK")
        logLine("SPEKTRAFILM_WATERMARK_CONTENT_OK")
        logLine("SPEKTRAFILM_MAT_CLEAN_OK")
        logLine("SPEKTRAFILM_FRAME_WINDOWS_OK count=36")
    }

    private static func writeWatermarkSheet() throws {
        let presets = WatermarkCatalog.builtin.presets
        let columns = 6
        let photoSize = CGSize(width: 400, height: 260)
        let caption: CGFloat = 28
        let rows = (presets.count + columns - 1) / columns
        let size = CGSize(
            width: photoSize.width * CGFloat(columns),
            height: (photoSize.height + caption) * CGFloat(rows)
        )
        guard let photo = duskCard(width: Int(photoSize.width), height: Int(photoSize.height)) else {
            throw FrameCheck.message("水印样张底图")
        }
        let info = WatermarkContext(
            filmName: "Portra 400",
            frameName: "暖白画廊",
            frameCode: "gallery_01",
            frameNumber: "01",
            frameTotal: "36",
            dateText: "2026.10.31"
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor(white: 0.07, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor(white: 0.86, alpha: 1),
            ]
            for (index, preset) in presets.enumerated() {
                guard let marked = WatermarkPainter.apply(photo, preset: preset, info: info) else { continue }
                let column = CGFloat(index % columns)
                let row = CGFloat(index / columns)
                let rect = CGRect(
                    x: column * photoSize.width,
                    y: row * (photoSize.height + caption),
                    width: photoSize.width,
                    height: photoSize.height
                )
                UIImage(cgImage: marked).draw(in: rect)
                let title = "\(preset.id)  \(preset.nameZh)" as NSString
                title.draw(at: CGPoint(x: rect.minX + 8, y: rect.maxY + 7), withAttributes: attrs)
            }
        }
        guard let sheet = image.cgImage else { throw FrameCheck.message("水印总览没有画出来") }
        _ = try writeProof(sheet, name: "watermark-sheet")
    }

    private static func duskCard(width: Int, height: Int) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { renderer in
            let colors = [
                UIColor(red: 0.15, green: 0.17, blue: 0.21, alpha: 1).cgColor,
                UIColor(red: 0.33, green: 0.30, blue: 0.27, alpha: 1).cgColor,
                UIColor(red: 0.55, green: 0.47, blue: 0.39, alpha: 1).cgColor,
            ] as CFArray
            let locations: [CGFloat] = [0, 0.58, 1]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: locations
            ) else { return }
            renderer.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: CGFloat(height)),
                options: []
            )
        }
        return image.cgImage
    }

    private static func solidCard(width: Int, height: Int, color: UIColor) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
            color.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height)).fill()
        }
        return image.cgImage
    }

    @MainActor
    private static func checkEngine() async -> Int32 {
        let suite = "spektrafilm.frame.selftest"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        guard let defaults = UserDefaults(suiteName: suite) else { return 1 }
        defaults.removePersistentDomain(forName: suite)
        let model = LabModel(defaults: defaults)
        model.persistEnabled = false
        model.undoManager = UndoManager()
        await model.bootstrap()
        await model.waitUntilSettled()
        guard model.preview != nil else {
            logLine("SPEKTRAFILM_FRAME_ENGINE_FAIL no preview \(model.errorText ?? "")")
            return 1
        }
        guard let original = model.originalPreview?.cgImage,
              max(original.width, original.height) <= MemoryTier.previewLongEdge,
              ImageCodec.lumaSpread(original) > 0.02
        else {
            logLine("SPEKTRAFILM_ORIGINAL_PREVIEW_FAIL")
            return 1
        }
        let baseline = model.engineRenderCount
        guard baseline >= 1 else {
            logLine("SPEKTRAFILM_FRAME_ENGINE_FAIL count=\(baseline)")
            return 1
        }
        logLine("SPEKTRAFILM_FRAME_ENGINE_BASE count=\(baseline)")
        let keptFrame = model.frame
        let keptFilm = model.filmID
        let keptPaper = model.paperID
        let keptExposure = model.exposureEV
        let keptMark = model.watermark
        model.setPreviewTransition(.pageTurn)
        if model.previewTransition != .pageTurn
            || model.frame != keptFrame
            || model.filmID != keptFilm
            || model.paperID != keptPaper
            || abs(model.exposureEV - keptExposure) > 0.0001
            || model.watermark != keptMark
            || model.engineRenderCount != baseline {
            logLine("SPEKTRAFILM_TRANSITION_KEEP_FAIL style=\(model.previewTransition.rawValue) engine=\(model.engineRenderCount) frame=\(model.frame.activeFrameId)")
            return 1
        }
        model.setPreviewTransition(.dissolve)
        if model.previewTransition != .dissolve || model.engineRenderCount != baseline || model.frame != keptFrame {
            logLine("SPEKTRAFILM_TRANSITION_KEEP_FAIL style=\(model.previewTransition.rawValue)")
            return 1
        }
        logLine("SPEKTRAFILM_TRANSITION_KEEP_OK style=dissolve engine=\(model.engineRenderCount)")
        let switches = ["gallery_02", "gallery_04", "gallery_06", "darkroom_01", "film_01", "instant_01", "editorial_02", "archive_02", "archive_03"]
        for id in switches {
            model.chooseFrame(id)
            await model.waitUntilSettled()
            if let image = model.preview?.cgImage {
                _ = try? writeProof(image, name: "live-\(id)")
            }
        }
        model.lockRatio("1:1")
        await model.waitUntilSettled()
        model.lockRatio("65:24")
        await model.waitUntilSettled()
        model.lockRatio("auto")
        await model.waitUntilSettled()
        model.followFrameRatio()
        await model.waitUntilSettled()
        model.lockRatio("source")
        await model.waitUntilSettled()
        model.chooseNoFrame()
        await model.waitUntilSettled()
        model.chooseFrame("gallery_01")
        await model.waitUntilSettled()
        model.chooseFrame("gallery_01")
        await model.waitUntilSettled()
        let order = model.frameCatalog.frames.map(\.id)
        let heldMark = model.watermark
        let startEdges = model.frameCatalog.horizontalEdges(model.frame)
        if order.first != "gallery_01" || order.last != "archive_06" || !startEdges.atStart || startEdges.atEnd {
            logLine("SPEKTRAFILM_FRAME_GLOBAL_FAIL start frame=\(model.frame.activeFrameId) atStart=\(startEdges.atStart) atEnd=\(startEdges.atEnd)")
            return 1
        }
        model.commitMove(.previousStyle)
        if model.frame.activeFrameId != "gallery_01" || model.engineRenderCount != baseline {
            logLine("SPEKTRAFILM_FRAME_GLOBAL_FAIL past-start frame=\(model.frame.activeFrameId) engine=\(model.engineRenderCount)")
            return 1
        }
        for id in order.dropFirst() {
            model.commitMove(.nextStyle)
            let edges = model.frameCatalog.horizontalEdges(model.frame)
            let seriesBoundary = id == "gallery_06" || id == "darkroom_01" || id == "archive_06"
            if model.frame.activeFrameId != id || !model.frame.enabled || model.watermark != heldMark || model.engineRenderCount != baseline
                || (seriesBoundary && (edges.atStart || edges.atEnd)) {
                logLine("SPEKTRAFILM_FRAME_GLOBAL_FAIL frame=\(model.frame.activeFrameId) want=\(id) atStart=\(edges.atStart) atEnd=\(edges.atEnd) engine=\(model.engineRenderCount)")
                return 1
            }
        }
        model.commitMove(.nextStyle)
        let endEdges = model.frameCatalog.horizontalEdges(model.frame)
        if model.frame.enabled || !endEdges.atEnd || endEdges.atStart || model.engineRenderCount != baseline {
            logLine("SPEKTRAFILM_FRAME_GLOBAL_FAIL end enabled=\(model.frame.enabled) atStart=\(endEdges.atStart) atEnd=\(endEdges.atEnd)")
            return 1
        }
        for id in order.reversed() {
            model.commitMove(.previousStyle)
            if model.frame.activeFrameId != id || !model.frame.enabled || model.engineRenderCount != baseline {
                logLine("SPEKTRAFILM_FRAME_GLOBAL_FAIL reverse frame=\(model.frame.activeFrameId) want=\(id) engine=\(model.engineRenderCount)")
                return 1
            }
        }
        let backEdges = model.frameCatalog.horizontalEdges(model.frame)
        if !backEdges.atStart || backEdges.atEnd || model.watermark != heldMark {
            logLine("SPEKTRAFILM_FRAME_GLOBAL_FAIL returned atStart=\(backEdges.atStart) mark=\(model.watermark.activeID)")
            return 1
        }
        await model.waitUntilSettled()
        if model.engineRenderCount != baseline {
            logLine("SPEKTRAFILM_FRAME_CACHE_FAIL engine=\(model.engineRenderCount) expected=\(baseline) hits=\(model.frameCacheHits)")
            return 1
        }
        logLine("SPEKTRAFILM_FRAME_GLOBAL_WALK forward=\(order.count) reverse=\(order.count) engineRenders=\(model.engineRenderCount)")
        let markEngine = model.engineRenderCount
        let frameWhileMarking = model.frame
        var seenMarks: [String] = []
        for _ in 0..<9 {
            model.commitMove(.nextWatermark)
            if model.watermark.enabled { seenMarks.append(model.watermark.activeID) }
        }
        model.commitMove(.previousWatermark)
        model.commitMove(.nextWatermark)
        await model.waitUntilSettled()
        if seenMarks != (1...9).map({ String(format: "wm_%02d", $0) })
            || model.watermark.activeID != "wm_09"
            || !model.watermark.enabled
            || model.engineRenderCount != markEngine
            || model.frame != frameWhileMarking {
            logLine("SPEKTRAFILM_WATERMARK_GESTURE_FAIL seen=\(seenMarks.joined(separator: ",")) mark=\(model.watermark.activeID) engine=\(model.engineRenderCount) base=\(markEngine)")
            return 1
        }
        let kept = model.watermark
        model.chooseFrame("editorial_02")
        await model.waitUntilSettled()
        if model.watermark != kept || model.engineRenderCount != markEngine || model.frame.activeFrameId != "editorial_02" {
            logLine("SPEKTRAFILM_WATERMARK_KEEP_FAIL mark=\(model.watermark.activeID) enabled=\(model.watermark.enabled) engine=\(model.engineRenderCount)")
            return 1
        }
        model.chooseFrame("gallery_01")
        await model.waitUntilSettled()
        if model.watermark != kept || model.engineRenderCount != markEngine {
            logLine("SPEKTRAFILM_WATERMARK_KEEP_FAIL after gallery mark=\(model.watermark.activeID) engine=\(model.engineRenderCount)")
            return 1
        }
        logLine("SPEKTRAFILM_WATERMARK_GESTURE steps=11 engineRenders=\(model.engineRenderCount)")
        logLine("SPEKTRAFILM_FRAME_CACHE_OK engine=\(model.engineRenderCount) hits=\(model.frameCacheHits)")
        let beforeExposure = model.engineRenderCount
        model.setExposure(0.4)
        await model.waitUntilSettled()
        if model.engineRenderCount != beforeExposure + 1 || abs(model.exposureEV - 0.4) > 0.05 || model.frame.activeFrameId != "gallery_01" {
            logLine("SPEKTRAFILM_FRAME_EXPOSURE_FAIL engine=\(model.engineRenderCount) before=\(beforeExposure) ev=\(model.exposureEV) frame=\(model.frame.activeFrameId)")
            return 1
        }
        guard let heldOriginal = model.originalPreview?.cgImage, !changed(original, heldOriginal) else {
            logLine("SPEKTRAFILM_ORIGINAL_PREVIEW_FAIL changed-with-edit")
            return 1
        }
        logLine("SPEKTRAFILM_ORIGINAL_PREVIEW_OK")
        logLine("SPEKTRAFILM_FRAME_EXPOSURE_OK engine=\(model.engineRenderCount)")
        model.undo()
        await model.waitUntilSettled()
        guard model.frame.enabled, model.frame.activeFrameId == "gallery_01", abs(model.exposureEV) < 0.05 else {
            logLine("SPEKTRAFILM_FRAME_UNDO_FAIL enabled=\(model.frame.enabled) frame=\(model.frame.activeFrameId) ev=\(model.exposureEV)")
            return 1
        }
        if model.engineRenderCount != beforeExposure + 2 {
            logLine("SPEKTRAFILM_FRAME_UNDO_FAIL engine=\(model.engineRenderCount) expected=\(beforeExposure + 2)")
            return 1
        }
        logLine("SPEKTRAFILM_FRAME_UNDO_OK ev=\(model.exposureEV) frame=\(model.frame.activeFrameId) engine=\(model.engineRenderCount)")
        if model.watermark != kept {
            logLine("SPEKTRAFILM_WATERMARK_UNDO_FAIL mark=\(model.watermark.activeID) enabled=\(model.watermark.enabled)")
            return 1
        }
        let proofs: [(Bool, Bool, String)] = [
            (true, true, "export-frame-on-watermark-on"),
            (true, false, "export-frame-on-watermark-off"),
            (false, true, "export-frame-off-watermark-on"),
            (false, false, "export-frame-off-watermark-off"),
        ]
        var rendered: [String: CGImage] = [:]
        for item in proofs {
            guard let image = model.proofStill(includeFrame: item.0, includeWatermark: item.1) else {
                logLine("SPEKTRAFILM_EXPORT_PROOF_FAIL \(item.2)")
                return 1
            }
            do {
                _ = try writeProof(image, name: item.2)
            } catch {
                logLine("SPEKTRAFILM_EXPORT_PROOF_FAIL \(item.2) \(error.localizedDescription)")
                return 1
            }
            rendered[item.2] = image
        }
        guard let both = rendered["export-frame-on-watermark-on"],
              let frameOnly = rendered["export-frame-on-watermark-off"],
              let markOnly = rendered["export-frame-off-watermark-on"],
              let photoOnly = rendered["export-frame-off-watermark-off"],
              changed(both, frameOnly),
              changed(markOnly, photoOnly),
              both.width != photoOnly.width || both.height != photoOnly.height || changed(frameOnly, photoOnly)
        else {
            logLine("SPEKTRAFILM_EXPORT_PROOF_FAIL combinations-look-alike")
            return 1
        }
        logLine("SPEKTRAFILM_EXPORT_PROOF_OK frame=\(both.width)x\(both.height) photo=\(photoOnly.width)x\(photoOnly.height)")
        do {
            try writeSignatureDetail(base: frameOnly, info: model.watermarkContext)
        } catch {
            logLine("SPEKTRAFILM_EXPORT_PROOF_FAIL signature \(error.localizedDescription)")
            return 1
        }
        model.export(.png, includeFrame: true, includeWatermark: true)
        await model.waitUntilSettled()
        model.export(.jpeg, includeFrame: false, includeWatermark: false)
        await model.waitUntilSettled()

                // Content / offset persist through the same UserDefaults archive.
        model.persistEnabled = true
        let contentEngine = model.engineRenderCount
        model.updateWatermarkContent(displayName: "Kevin", studioName: "Spektra Lab", monogram: "KV", siteURL: "kevin.film")
        model.setWatermarkOffset(x: 0.11, y: -0.07, recordUndo: false)
        await model.waitUntilSettled()
        if model.engineRenderCount != contentEngine {
            logLine("SPEKTRAFILM_WATERMARK_CONTENT_ENGINE_FAIL engine=\(model.engineRenderCount) base=\(contentEngine)")
            return 1
        }
let savedName = model.watermark.displayName
        let savedStudio = model.watermark.studioName
        let savedMono = model.watermark.monogram
        let savedSite = model.watermark.siteURL
        let savedX = model.watermark.offsetX
        let savedY = model.watermark.offsetY
        guard let archived = defaults.data(forKey: "spektrafilm.edit.v1"),
              let payload = try? JSONDecoder().decode(PersistedEdit.self, from: archived),
              var mark = payload.watermark
        else {
            logLine("SPEKTRAFILM_WATERMARK_PERSIST_FAIL missing-archive")
            return 1
        }
        mark.sanitize(catalog: WatermarkCatalog.builtin)
        if mark.displayName != savedName
            || mark.studioName != savedStudio
            || mark.monogram != savedMono
            || mark.siteURL != savedSite
            || abs(mark.offsetX - savedX) > 0.0001
            || abs(mark.offsetY - savedY) > 0.0001
            || (payload.schemaVersion ?? 0) < 4 {
            logLine("SPEKTRAFILM_WATERMARK_PERSIST_FAIL name=\(mark.displayName) x=\(mark.offsetX) schema=\(payload.schemaVersion ?? -1)")
            return 1
        }
        logLine("SPEKTRAFILM_WATERMARK_PERSIST_OK name=\(savedName) x=\(savedX) y=\(savedY)")

        // Compare actual PNG exports against the same custom mark drawn onto the actual unmarked export.
        // This catches accidentally dropping identity/drag offset in the export snapshot.
        model.shareURL = nil
        model.export(.png, includeFrame: false, includeWatermark: false)
        await model.waitUntilSettled()
        guard let plainURL = model.shareURL, let exportedPlain = UIImage(contentsOfFile: plainURL.path)?.cgImage else {
            logLine("SPEKTRAFILM_EXPORT_IDENTITY_FAIL plain")
            return 1
        }
        model.shareURL = nil
        model.export(.png, includeFrame: false, includeWatermark: true)
        await model.waitUntilSettled()
        guard let signedURL = model.shareURL, let exportedSigned = UIImage(contentsOfFile: signedURL.path)?.cgImage,
              let preset = model.watermarkCatalog.preset(model.watermark.activeID),
              let expectedSigned = WatermarkPainter.apply(exportedPlain, preset: preset, info: model.watermarkContext,
                                                         identity: model.watermark.identity,
                                                         offset: CGSize(width: model.watermark.offsetX, height: model.watermark.offsetY)),
              changed(exportedPlain, exportedSigned), !changed(expectedSigned, exportedSigned)
        else {
            logLine("SPEKTRAFILM_EXPORT_IDENTITY_FAIL custom-or-offset")
            return 1
        }
        logLine("SPEKTRAFILM_EXPORT_IDENTITY_OK")

        model.chooseFrame("editorial_02")
        model.watermark.enabled = true
        model.watermark.activeID = "wm_01"
        model.persistEnabled = false
        await model.waitUntilSettled()
        guard let framedOnly = model.proofStill(includeFrame: true, includeWatermark: false),
              let framedMark = model.proofStill(includeFrame: true, includeWatermark: true),
              changed(framedOnly, framedMark),
              let onlyPixels = FramePainter.pixels8(framedOnly),
              let markPixels = FramePainter.pixels8(framedMark)
        else {
            logLine("SPEKTRAFILM_WATERMARK_INSET_FAIL proof")
            return 1
        }
        // Outer mat corners should match; the credit lives in the photo opening.
        var cornerDrift = 0
        for (x, y) in [(3, 3), (framedOnly.width - 4, 3), (3, framedOnly.height - 4), (framedOnly.width - 4, framedOnly.height - 4)] {
            let a = sample(onlyPixels, x, y)
            let b = sample(markPixels, x, y)
            if abs(a.r - b.r) > 6 || abs(a.g - b.g) > 6 || abs(a.b - b.b) > 6 {
                cornerDrift += 1
            }
        }
        if cornerDrift > 0 {
            logLine("SPEKTRAFILM_WATERMARK_INSET_FAIL mat-corners=\(cornerDrift)")
            return 1
        }
        _ = try? writeProof(framedMark, name: "export-frame-on-watermark-on-inset")
        logLine("SPEKTRAFILM_WATERMARK_INSET_OK \(framedMark.width)x\(framedMark.height)")
        let fullCatalog = model.catalog
        let thumbnailEngineCount = model.engineRenderCount
        model.catalog.films = Array(fullCatalog.films.prefix(2))
        await model.requestCatalogThumbnails(papers: false)
        model.catalog.papers = Array(fullCatalog.papers.prefix(2))
        await model.requestCatalogThumbnails(papers: true)
        let expectedThumbKeys = model.catalog.films.map { "film:" + $0.id } + model.catalog.papers.map { "paper:" + $0.id }
        guard expectedThumbKeys.allSatisfy({ key in
            guard let image = model.catalogThumbs[key]?.cgImage else { return false }
            return max(image.width, image.height) <= 160 && image.width > 0 && image.height > 0
        }), model.engineRenderCount == thumbnailEngineCount else {
            logLine("SPEKTRAFILM_CATALOG_THUMBS_FAIL")
            return 1
        }
        model.catalog = fullCatalog
        logLine("SPEKTRAFILM_CATALOG_THUMBS_OK count=\(expectedThumbKeys.count) engineRenders=\(thumbnailEngineCount)")
        logLine("SPEKTRAFILM_FRAME_ENGINE_OK")
        return 0
    }

    private static func changed(
        _ lhs: (width: Int, height: Int, bytes: [UInt8]),
        _ rhs: (width: Int, height: Int, bytes: [UInt8])
    ) -> Bool {
        if lhs.width != rhs.width || lhs.height != rhs.height { return true }
        let count = min(lhs.bytes.count, rhs.bytes.count)
        var different = 0
        var index = 0
        while index + 3 < count {
            if abs(Int(lhs.bytes[index]) - Int(rhs.bytes[index])) > 8
                || abs(Int(lhs.bytes[index + 1]) - Int(rhs.bytes[index + 1])) > 8
                || abs(Int(lhs.bytes[index + 2]) - Int(rhs.bytes[index + 2])) > 8 {
                different += 1
                if different > 24 { return true }
            }
            // Scan every RGBA pixel: narrow glyphs can fall between a four-pixel stride.
            index += 4
        }
        return false
    }

    private static func changed(_ lhs: CGImage, _ rhs: CGImage) -> Bool {
        guard let left = FramePainter.pixels8(lhs), let right = FramePainter.pixels8(rhs) else { return false }
        return changed(left, right)
    }

    private static func sample(_ pixels: (width: Int, height: Int, bytes: [UInt8]), _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let clampedX = min(max(0, x), pixels.width - 1)
        let clampedY = min(max(0, y), pixels.height - 1)
        let index = (clampedY * pixels.width + clampedX) * 4
        let bytes = pixels.bytes
        guard bytes.count >= index + 4 else { return (0, 0, 0, 0) }
        return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]), Int(bytes[index + 3]))
    }

    private static func writeSignatureDetail(base: CGImage, info: WatermarkContext) throws {
        guard let preset = WatermarkCatalog.builtin.preset("wm_01"),
              let signed = WatermarkPainter.apply(base, preset: preset, info: info)
        else { throw FrameCheck.message("右下签名没有画出来") }
        guard changed(base, signed) else { throw FrameCheck.message("右下签名在装裱图上看不见") }
        _ = try writeProof(signed, name: "export-signature-br")
        guard let crop = cropBottomRight(signed, widthFraction: 0.42, heightFraction: 0.48) else {
            throw FrameCheck.message("右下签名特写")
        }
        _ = try writeProof(crop, name: "watermark-signature-detail")
        logLine("SPEKTRAFILM_SIGNATURE_PROOF_OK \(signed.width)x\(signed.height)")
    }

    private static func cropBottomRight(_ image: CGImage, widthFraction: CGFloat, heightFraction: CGFloat) -> CGImage? {
        let width = image.width
        let height = image.height
        let cropW = max(1, Int((CGFloat(width) * widthFraction).rounded()))
        let cropH = max(1, Int((CGFloat(height) * heightFraction).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: cropW, height: cropH), format: format).image { _ in
            UIImage(cgImage: image).draw(in: CGRect(
                x: CGFloat(cropW - width),
                y: CGFloat(cropH - height),
                width: CGFloat(width),
                height: CGFloat(height)
            ))
        }
        return rendered.cgImage
    }


    private static func isFlatLightHex(_ hex: String) -> Bool {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        let value = UInt32(text, radix: 16) ?? 0xFFFFFF
        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        let chroma = max(red, green, blue) - min(red, green, blue)
        return luminance >= 0.70 && chroma <= 0.12
    }

    private static func assertFlatLightMat(
        preset: FramePreset,
        image: CGImage,
        layout: FrameLayout,
        pixels: (width: Int, height: Int, bytes: [UInt8])
    ) throws {
        guard isFlatLightHex(preset.palette.outer) else { return }
        // Only assert on structures whose large visible field is meant to be flat paper.
        // double_mat / rails / letterbox / mounts keep intentional steps, bars, or holes.
        let flatStructures = Set(["simple", "inner_rule", "asymmetric", "linen", "deckle"])
        guard flatStructures.contains(preset.structure) else { return }

        var text = preset.palette.outer.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        let value = UInt32(text, radix: 16) ?? 0xFFFFFF
        let er = Int((value >> 16) & 0xFF)
        let eg = Int((value >> 8) & 0xFF)
        let eb = Int(value & 0xFF)

        // Sample outer-paper corners only. Mid-edge samples can land on double_mat cracks,
        // asymmetric keylines, or thin rails that are intentional structure — not "stains".
        let inset = 3
        let candidates: [(Int, Int)] = [
            (inset, inset),
            (pixels.width - 1 - inset, inset),
            (inset, pixels.height - 1 - inset),
            (pixels.width - 1 - inset, pixels.height - 1 - inset),
        ]
        // Keep a clear gap from the photo opening and from any double-mat inner plate.
        let keepOut = layout.photo.insetBy(dx: -max(4, layout.minMargin * 0.55), dy: -max(4, layout.minMargin * 0.55))
        var samples: [(r: Int, g: Int, b: Int, a: Int)] = []
        for (x, y) in candidates {
            let sx = min(max(0, x), pixels.width - 1)
            let sy = min(max(0, y), pixels.height - 1)
            if keepOut.contains(CGPoint(x: CGFloat(sx), y: CGFloat(sy))) { continue }
            let px = sample(pixels, sx, sy)
            guard px.a > 200 else { continue }
            // displayP3 vs sRGB hex can drift a few levels; stains are much larger.
            let dr = abs(px.r - er)
            let dg = abs(px.g - eg)
            let db = abs(px.b - eb)
            if max(dr, dg, db) > 14 {
                throw FrameCheck.message("\(preset.id) 浅色卡纸不纯 sample=\(px) want=#\(text) at=\(sx),\(sy)")
            }
            samples.append(px)
        }
        guard samples.count >= 2 else { return }
        let rs = samples.map(\.r)
        let gs = samples.map(\.g)
        let bs = samples.map(\.b)
        let spread = max(rs.max()! - rs.min()!, gs.max()! - gs.min()!, bs.max()! - bs.min()!)
        if spread > 8 {
            throw FrameCheck.message("\(preset.id) 浅色卡纸有色斑 spread=\(spread) samples=\(samples)")
        }
    }

    @discardableResult
    private static func writeProof(_ image: CGImage, name: String) throws -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = root.appendingPathComponent("frame-proof", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name).appendingPathExtension("png")
        try ImageCodec.write(image, format: .png, to: url)
        logLine("SPEKTRAFILM_FRAME_PROOF \(url.lastPathComponent) \(image.width)x\(image.height)")
        return url
    }
}
