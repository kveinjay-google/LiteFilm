import CoreGraphics
import Foundation
import PhotosUI
import SwiftUI
import UIKit

struct EditSnapshot: Equatable {
    var filmID: String
    var paperID: String
    var exposureEV: Double
    var frame: FrameEditState
    var watermark: WatermarkEditState
    var adjustments: PhotoAdjustments
}

@MainActor
final class LabModel: ObservableObject {
    @Published var preview: UIImage?
    /// Upright source, bounded to the same edge as the working preview, without edits.
    @Published private(set) var originalPreview: UIImage?
    @Published private(set) var catalogThumbs: [String: UIImage] = [:]
    @Published private(set) var watermarkThumbs: [String: UIImage] = [:]
    @Published var busy = false
    @Published var showCropEditor = false
    @Published var status = "正在准备引擎"
    @Published var errorText: String?
    @Published var filmID = "kodak_portra_400"
    @Published var paperID = "kodak_portra_endura"
    @Published var exposureEV = 0.0
    @Published private(set) var adjustments = PhotoAdjustments()
    @Published private(set) var editingSourcePreview: UIImage?
    @Published private(set) var favoriteFilms: Set<String> = []
    @Published private(set) var favoritePapers: Set<String> = []
    @Published var sourceTitle = "内置色卡"
    @Published var shareURL: URL?
    @Published var catalog = FilmCatalog(films: [], papers: [])
    @Published var frameCatalog = FrameCatalog.empty
    @Published var frame = FrameEditState()
    @Published var watermarkCatalog = WatermarkCatalog.builtin
    @Published var watermark = WatermarkEditState()
    @Published var exportIncludeFrame = true
    @Published var exportIncludeWatermark = true
    @Published var previewTransition: PreviewTransition = .dissolve
    @Published var previewSwap = PreviewSwap()
    @Published var thumbs: [String: UIImage] = [:]
    @Published var canUndo = false
    @Published private(set) var engineRenderCount = 0
    @Published private(set) var frameCacheHits = 0
    @Published var stage: LabStage = .home
    @Published var gallery = ImportGalleryStore()
    /// Short non-blocking banner (e.g. RAW import note). Cleared automatically.
    @Published var noticeText: String?

    private let engine = EngineClient()
    private let catalogEngine = EngineClient()
    private var catalogThumbTask: Task<Void, Never>?
    private var catalogThumbToken = 0
    private var catalogThumbContexts: [String: String] = [:]
    private var catalogActiveContext = ""
    private var catalogRequestedPapers: Bool?
    private var catalogSource: FrameBuffer?
    private var sourceRevision = 0
    private struct WatermarkThumbContext: Equatable, Sendable {
        var identity: WatermarkIdentity
        var context: WatermarkContext
        var presets: [WatermarkPreset]
    }
    private var watermarkThumbContext: WatermarkThumbContext?
    private var watermarkThumbTask: Task<Void, Never>?
    private var watermarkThumbToken = 0
    private let defaults: UserDefaults
    private var sourceData: Data?
    private var sourcePixel = CGSize(width: 3, height: 2)
    private var engineOpen = false
    private var inFlight = false
    private var dirty = false
    private var debounce: Task<Void, Never>?
    private var pendingFilm: String?
    private var pendingPaper: String?
    private var undoBaseline: EditSnapshot?
    private var undoStack: [EditSnapshot] = []
    private var started = false
    /// Nil means the built-in color chart is the working source.
    private var sourceImportID: String?
    private var processed: CGImage?
    private var processedKey: RenderParams?
    private var processedAdjustments: PhotoAdjustments?
    private var thumbPhoto: CGImage?
    private var thumbToken = 0
    private var thumbKey = ""
    private var thumbTask: Task<Void, Never>?
    private var frameToken = 0
    private var paintsInFlight = 0
    private var staged: FrameBuffer?
    var persistEnabled = true
    private var watermarkDragBaseline: EditSnapshot?
    var undoManager: UndoManager?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favoriteFilms = Set(defaults.stringArray(forKey: "litefilm.favoriteFilms") ?? [])
        favoritePapers = Set(defaults.stringArray(forKey: "litefilm.favoritePapers") ?? [])
    }

    func stocks(papers: Bool) -> [Stock] {
        let all = papers ? catalog.papers : catalog.films
        let favorites = papers ? favoritePapers : favoriteFilms
        return all.filter { favorites.contains($0.id) } + all.filter { !favorites.contains($0.id) }
    }

    func stockCode(_ id: String, papers: Bool) -> String {
        let all = papers ? catalog.papers : catalog.films
        guard let index = all.firstIndex(where: { $0.id == id }) else { return "—" }
        return String(format: "%@%02d", papers ? "P" : "F", index + 1)
    }

    func isFavorite(_ id: String, papers: Bool) -> Bool {
        (papers ? favoritePapers : favoriteFilms).contains(id)
    }

    func toggleFavorite(_ id: String, papers: Bool) {
        guard (papers ? catalog.paper(id) : catalog.film(id)) != nil else { return }
        var favorites = papers ? favoritePapers : favoriteFilms
        let added = !favorites.contains(id)
        if added { favorites.insert(id) } else { favorites.remove(id) }
        if papers { favoritePapers = favorites } else { favoriteFilms = favorites }
        defaults.set(favorites.sorted(), forKey: papers ? "litefilm.favoritePapers" : "litefilm.favoriteFilms")
        flashNotice(added ? "已收藏，置顶显示" : "已取消收藏")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    var filmLabel: String { catalog.film(filmID)?.name ?? "" }

    /// The current film treatment without any mat or watermark, for the no-frame option.
    var unframedThumbnail: UIImage? { thumbPhoto.map { UIImage(cgImage: $0) } }

    var frameBadge: String {
        guard frame.enabled, let preset = frameCatalog.frame(frame.activeFrameId) else { return "无框" }
        let number = (frameCatalog.index(of: preset.id) ?? 0) + 1
        return "\(preset.nameZh) · \(String(format: "%02d", number))/36"
    }

    var watermarkBadge: String {
        guard watermark.enabled, let preset = watermarkCatalog.preset(watermark.activeID) else { return "无水印" }
        return preset.nameZh
    }

    var watermarkContext: WatermarkContext {
        let number: String
        let total: String
        if frame.enabled, let index = frameCatalog.index(of: frame.activeFrameId) {
            number = String(format: "%02d", index + 1)
            total = frameCatalog.frames.isEmpty ? "" : String(frameCatalog.frames.count)
        } else {
            number = ""
            total = ""
        }
        let preset = frame.enabled ? frameCatalog.frame(frame.activeFrameId) : nil
        return WatermarkContext(
            filmName: filmLabel,
            frameName: preset?.nameZh ?? "",
            frameCode: preset?.id ?? "",
            frameNumber: number,
            frameTotal: total,
            dateText: WatermarkContext.dateText(Date())
        )
    }

    var resolvedRatioID: String {
        guard frame.enabled, let preset = frameCatalog.frame(frame.activeFrameId) else { return "source" }
        if frame.ratio.mode == "followFrame" { return preset.defaultRatioId }
        return frame.ratio.ratioId
    }

    func canMove(_ move: FrameMove) -> Bool {
        switch move {
        case .previousWatermark, .nextWatermark:
            return watermarkCatalog.step(watermark, move) != nil
        default:
            return frameCatalog.step(frame, move) != nil
        }
    }

    func bootstrap() async {
        do {
            catalog = try FilmCatalog.load()
            frameCatalog = (try? FrameCatalog.load()) ?? .empty
            logLine("SPEKTRAFILM_FRAME_CATALOG count=\(frameCatalog.frames.count) ratios=\(frameCatalog.ratioOptions.count)")
            gallery.reload()
            restorePersisted()
            guard let resources = Bundle.main.url(forResource: "engine", withExtension: nil),
                  let sampleURL = Bundle.main.url(forResource: "SampleBars", withExtension: "png")
            else {
                throw EngineError.message("安装包里没有引擎资源或色卡。")
            }
            let engine = self.engine
            try await Task.detached {
                try engine.start(resources: resources)
            }.value
            started = true

            // Restore last imported working photo into the editor; otherwise land on the chart home.
            if let importID = sourceImportID, let item = gallery.item(id: importID) {
                let data = try gallery.loadOriginalData(for: item)
                try await use(data: data, title: item.title, importID: item.id)
                stage = .editor
                logLine("SPEKTRAFILM_BOOT_RESTORE import=\(item.id)")
            } else {
                sourceImportID = nil
                let data = try Data(contentsOf: sampleURL)
                try await use(data: data, title: "内置色卡", importID: nil)
                stage = .home
                logLine("SPEKTRAFILM_BOOT_HOME sample=1 gallery=\(gallery.importCount)")
            }
        } catch {
            errorText = error.localizedDescription
            status = "引擎没有起来"
            logLine("SPEKTRAFILM_BOOT_FAIL \(error.localizedDescription)")
        }
    }

    func load(item: PhotosPickerItem) async {
        do {
            let data = try await PhotoImport.loadData(from: item)
            let info = ImageCodec.probe(data)
            let title = info.isRaw ? "RAW 照片" : "照片"
            let saved = try gallery.importPhoto(data: data, title: title)
            let previousAdjustments = adjustments
            adjustments = PhotoAdjustments()
            do { try await use(data: data, title: saved.title, importID: saved.id) }
            catch { adjustments = previousAdjustments; throw error }
            stage = .editor
            persist()
            if info.isRaw {
                let pixels = "\(Int(sourcePixel.width))x\(Int(sourcePixel.height))"
                logLine("SPEKTRAFILM_IMPORT_RAW uti=\(info.uti) pixels=\(pixels) bytes=\(data.count)")
                flashNotice("已用系统解码 RAW（非完整显影）")
            } else {
                logLine("SPEKTRAFILM_IMPORT_OK uti=\(info.uti) pixels=\(Int(sourcePixel.width))x\(Int(sourcePixel.height))")
            }
        } catch {
            let message = error.localizedDescription
            errorText = message
            busy = false
            logLine("SPEKTRAFILM_IMPORT_FAIL \(message)")
        }
    }

    func flashNotice(_ text: String, seconds: Double = 3.6) {
        noticeText = text
        let captured = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if noticeText == captured {
                noticeText = nil
            }
        }
    }

    func showSample() async {
        do {
            guard let sampleURL = Bundle.main.url(forResource: "SampleBars", withExtension: "png") else {
                throw EngineError.message("安装包里没有色卡。")
            }
            let data = try Data(contentsOf: sampleURL)
            flushPending()
            await waitUntilSettled()
            let previous = adjustments
            if sourceImportID != nil { adjustments = PhotoAdjustments() }
            do { try await use(data: data, title: "内置色卡", importID: nil) }
            catch { adjustments = previous; throw error }
            persist()
        } catch {
            errorText = error.localizedDescription
            logLine("SPEKTRAFILM_IMPORT_FAIL \(error.localizedDescription)")
        }
    }

    func openHome() {
        gallery.reload()
        stage = .home
        Task { await showSample() }
        logLine("SPEKTRAFILM_NAV home")
    }

    func openGallery() {
        gallery.reload()
        stage = .gallery
        logLine("SPEKTRAFILM_NAV gallery count=\(gallery.importCount)")
    }

    func openSampleInEditor() async {
        await showSample()
        stage = .editor
        logLine("SPEKTRAFILM_NAV editor source=sample")
    }

    func openImport(id: String) async {
        flushPending()
        await waitUntilSettled()
        let previous = snapshot()
        do {
            guard let item = gallery.item(id: id) else {
                errorText = "画廊里找不到这张照片。"
                return
            }
            let data = try gallery.loadOriginalData(for: item)
            if let recipe = item.recipe {
                applyRecipe(recipe)
            } else if sourceImportID != item.id {
                adjustments = PhotoAdjustments()
            }
            try await use(data: data, title: item.title, importID: item.id)
            stage = .editor
            persist()
            logLine("SPEKTRAFILM_NAV editor source=\(item.isVariant ? "variant" : "import") id=\(id)")
        } catch {
            filmID = previous.filmID
            paperID = previous.paperID
            exposureEV = previous.exposureEV
            frame = previous.frame
            watermark = previous.watermark
            adjustments = previous.adjustments
            errorText = error.localizedDescription
            logLine("SPEKTRAFILM_IMPORT_FAIL \(error.localizedDescription)")
        }
    }

    func deleteImport(id: String) async {
        let wasCurrent = sourceImportID == id
        do {
            try gallery.delete(id: id)
            if wasCurrent {
                await showSample()
                if stage == .editor {
                    stage = .gallery
                }
            }
            persist()
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Long-press / bookmark: fork an independent gallery entry with its own bytes + recipe.
    func saveCurrentLookToGallery() {
        guard let data = sourceData else {
            flashNotice("没有可保存的照片")
            return
        }
        flushPending()
        let recipe = GalleryRecipe(
            filmID: filmID,
            paperID: paperID,
            exposureEV: exposureEV,
            frame: frame,
            watermark: watermark,
            adjustments: adjustments
        )
        let thumb: Data? = {
            guard let preview else { return nil }
            let maxEdge: CGFloat = 720
            let longest = max(preview.size.width, preview.size.height)
            let scale = longest > maxEdge ? maxEdge / longest : 1
            let size = CGSize(width: max(1, preview.size.width * scale), height: max(1, preview.size.height * scale))
            let format = UIGraphicsImageRendererFormat.default()
            format.opaque = true
            format.scale = 1
            let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                preview.draw(in: CGRect(origin: .zero, size: size))
            }
            return scaled.jpegData(compressionQuality: 0.86)
        }()
        let title = variantTitle()
        do {
            let item = try gallery.saveVariant(
                originalData: data,
                title: title,
                recipe: recipe,
                previewJPEG: thumb,
                forkedFromID: sourceImportID
            )
            sourceImportID = item.id
            sourceTitle = item.title
            persist()
            flashNotice("已保存方案到画廊")
            logLine("SPEKTRAFILM_LOOK_SAVE id=\(item.id) film=\(filmID) frame=\(frame.enabled ? frame.activeFrameId : "none")")
        } catch {
            errorText = error.localizedDescription
            flashNotice("保存方案失败")
            logLine("SPEKTRAFILM_LOOK_SAVE_FAIL \(error.localizedDescription)")
        }
    }

    func previewFilm(_ id: String) {
        if undoBaseline == nil { undoBaseline = snapshot() }
        pendingFilm = id
        armSettle()
    }

    func previewPaper(_ id: String) {
        if undoBaseline == nil { undoBaseline = snapshot() }
        pendingPaper = id
        armSettle()
    }

    func selectFilm(_ id: String) {
        pendingFilm = nil
        pendingPaper = nil
        debounce?.cancel()
        debounce = nil
        let before = undoBaseline ?? snapshot()
        undoBaseline = nil
        applyFilm(id, paperOverride: nil)
        pushUndo(before)
        persist()
        kickNow(keepingPending: true)
    }

    func selectPaper(_ id: String) {
        pendingFilm = nil
        pendingPaper = nil
        debounce?.cancel()
        debounce = nil
        let before = undoBaseline ?? snapshot()
        undoBaseline = nil
        paperID = id
        pushUndo(before)
        persist()
        kickNow(keepingPending: true)
    }

    /// Snapshot the value still on screen, then move. One settled drag is one undo.
    func setExposure(_ value: Double) {
        guard value.isFinite else { return }
        let clamped = min(2, max(-2, (value * 10).rounded() / 10))
        guard abs(clamped - exposureEV) > 0.0001 else { return }
        if undoBaseline == nil { undoBaseline = snapshot() }
        exposureEV = clamped
        armSettle()
    }

    func setAdjustment(_ keyPath: WritableKeyPath<PhotoAdjustments, Double>, _ value: Double) {
        guard value.isFinite else { return }
        let bounded = min(1, max(-1, (value * 100).rounded() / 100))
        guard adjustments[keyPath: keyPath] != bounded else { return }
        if undoBaseline == nil { undoBaseline = snapshot() }
        adjustments[keyPath: keyPath] = bounded
        armSettle()
    }

    func applyGeometry(_ value: PhotoGeometry) {
        flushPending()
        let value = value.sanitized()
        guard value != adjustments.geometry else { return }
        let before = snapshot()
        adjustments.geometry = value
        pushUndo(before)
        persist()
        kickNow(keepingPending: true)
    }

    func resetAdjustments() {
        flushPending()
        guard adjustments != PhotoAdjustments() || exposureEV != 0 else { return }
        let before = snapshot()
        adjustments = PhotoAdjustments()
        exposureEV = 0
        pushUndo(before)
        persist()
        kickNow(keepingPending: true)
    }

    func commitMove(_ move: FrameMove) {
        flushPending()
        switch move {
        case .previousWatermark, .nextWatermark:
            guard let next = watermarkCatalog.step(watermark, move) else {
                logLine("SPEKTRAFILM_WATERMARK_GESTURE move=\(move.rawValue) result=edge mark=\(watermarkBadge) engineRenders=\(engineRenderCount)")
                return
            }
            let before = snapshot()
            watermark = next
            guard snapshot() != before else { return }
            pushUndo(before)
            persist()
            armPreviewSwap(move)
            logLine("SPEKTRAFILM_WATERMARK_GESTURE move=\(move.rawValue) result=ok mark=\(watermark.enabled ? watermark.activeID : "none") engineRenders=\(engineRenderCount)")
            refreshAppearance()
        default:
            guard let next = frameCatalog.step(frame, move) else {
                logLine("SPEKTRAFILM_FRAME_GESTURE_APPLIED move=\(move.rawValue) result=edge frame=\(frame.activeFrameId) engineRenders=\(engineRenderCount)")
                return
            }
            let before = snapshot()
            frame = next
            guard snapshot() != before else { return }
            pushUndo(before)
            persist()
            armPreviewSwap(move)
            logLine("SPEKTRAFILM_FRAME_GESTURE_APPLIED move=\(move.rawValue) result=ok frame=\(frame.enabled ? frame.activeFrameId : "none") engineRenders=\(engineRenderCount)")
            refreshAppearance()
        }
    }

    /// Stored with the edit archive. Does not touch film, paper, exposure, frame, or watermark.
    func setPreviewTransition(_ value: PreviewTransition) {
        guard previewTransition != value else { return }
        previewTransition = value
        persist()
        logLine("SPEKTRAFILM_TRANSITION_SET style=\(value.rawValue)")
    }

    func setExportIncludeFrame(_ value: Bool) {
        guard exportIncludeFrame != value else { return }
        exportIncludeFrame = value
        persist()
    }

    func setExportIncludeWatermark(_ value: Bool) {
        guard exportIncludeWatermark != value else { return }
        exportIncludeWatermark = value
        persist()
    }

    /// Settings 里改水印文案。立刻进预览，不增加 engineRenders。
    func updateWatermarkContent(
        displayName: String? = nil,
        studioName: String? = nil,
        copyrightLine: String? = nil,
        monogram: String? = nil,
        siteURL: String? = nil
    ) {
        let before = watermark
        var next = watermark
        if let displayName { next.displayName = displayName }
        if let studioName { next.studioName = studioName }
        if let copyrightLine { next.copyrightLine = copyrightLine }
        if let monogram { next.monogram = monogram }
        if let siteURL { next.siteURL = siteURL }
        next.sanitize(catalog: watermarkCatalog)
        guard next != before else { return }
        watermark = next
        persist()
        refreshAppearance()
    }

    func setWatermarkOffset(x: Double, y: Double, recordUndo: Bool = false) {
        var next = watermark
        next.offsetX = x
        next.offsetY = y
        next.sanitize(catalog: watermarkCatalog)
        guard next.offsetX != watermark.offsetX || next.offsetY != watermark.offsetY else { return }
        if recordUndo {
            let before = snapshot()
            watermark = next
            pushUndo(before)
        } else {
            watermark = next
        }
        persist()
        refreshAppearance()
    }

    func resetWatermarkOffset() {
        setWatermarkOffset(x: 0, y: 0, recordUndo: true)
    }

    /// Toolbar overflow: turn the active watermark on/off without scrubbing presets.
    func setWatermarkEnabled(_ on: Bool) {
        flushPending()
        var next = watermark
        if on {
            next.enabled = true
            if watermarkCatalog.preset(next.activeID) == nil {
                next.activeID = watermarkCatalog.presets.first?.id ?? next.activeID
            }
        } else {
            next.enabled = false
        }
        next.sanitize(catalog: watermarkCatalog)
        guard next != watermark else { return }
        let before = snapshot()
        watermark = next
        pushUndo(before)
        persist()
        refreshAppearance()
        logLine("SPEKTRAFILM_WATERMARK_TOGGLE on=\(on) mark=\(watermark.enabled ? watermark.activeID : "none")")
    }

    /// 长按拖动开始：记下 undo 基线。
    func beginWatermarkDrag() {
        if watermarkDragBaseline == nil {
            watermarkDragBaseline = snapshot()
        }
    }

    /// 拖动中更新归一化偏移，自动夹在内容区内（画家侧再夹一次）。
    func updateWatermarkDrag(offsetX: Double, offsetY: Double) {
        var next = watermark
        next.offsetX = offsetX
        next.offsetY = offsetY
        next.sanitize(catalog: watermarkCatalog)
        guard next.offsetX != watermark.offsetX || next.offsetY != watermark.offsetY else { return }
        watermark = next
        refreshAppearance()
    }

    /// 松手：写入 undo、persist。
    func endWatermarkDrag() {
        if let baseline = watermarkDragBaseline {
            watermarkDragBaseline = nil
            if baseline != snapshot() {
                pushUndo(baseline)
            }
        }
        persist()
        refreshAppearance()
        let markID = watermark.enabled ? watermark.activeID : "none"
        logLine("SPEKTRAFILM_WATERMARK_DRAG_SAVE x=\(watermark.offsetX) y=\(watermark.offsetY) mark=\(markID)")
    }

    func chooseWatermark(_ id: String) {
        flushPending()
        guard let preset = watermarkCatalog.preset(id) else { return }
        let before = snapshot()
        watermark.enabled = true
        watermark.activeID = preset.id
        guard snapshot() != before else { return }
        pushUndo(before)
        persist()
        refreshAppearance()
    }

    func chooseFrame(_ id: String) {
        flushPending()
        guard let preset = frameCatalog.frame(id) else { return }
        let before = snapshot()
        frame.enabled = true
        frame.activeFrameId = preset.id
        frame.activeFamilyId = preset.familyId
        frame.lastFrameByFamily[preset.familyId] = preset.id
        guard snapshot() != before else { return }
        pushUndo(before)
        persist()
        refreshAppearance()
    }

    func chooseNoFrame() {
        flushPending()
        let before = snapshot()
        frame.enabled = false
        guard snapshot() != before else { return }
        pushUndo(before)
        persist()
        refreshAppearance()
    }

    func lockRatio(_ id: String) {
        guard frameCatalog.ratioOptions.contains(where: { $0.id == id }) else { return }
        if frame.enabled,
           let preset = frameCatalog.frame(frame.activeFrameId),
           !preset.allowedRatioIds.contains(id) {
            return
        }
        flushPending()
        let before = snapshot()
        frame.ratio.mode = "locked"
        frame.ratio.ratioId = id
        guard snapshot() != before else { return }
        pushUndo(before)
        persist()
        refreshAppearance()
        thumbKey = ""
        scheduleThumbs()
    }

    func followFrameRatio() {
        flushPending()
        let before = snapshot()
        frame.ratio.mode = "followFrame"
        guard snapshot() != before else { return }
        pushUndo(before)
        persist()
        refreshAppearance()
        thumbKey = ""
        scheduleThumbs()
    }

    func undo() {
        if let undoManager, undoManager.canUndo {
            undoManager.undo()
            syncCanUndo()
            return
        }
        guard let previous = undoStack.popLast() else {
            syncCanUndo()
            return
        }
        restore(previous, recordInverse: true)
    }

    /// `includeFrame` and `includeWatermark` are the choices at the moment of the tap.
    /// Film, paper, exposure, frame, and watermark are copied before the export task starts.
    func export(_ format: ExportFormat, includeFrame: Bool, includeWatermark: Bool) {
        guard started, let data = sourceData, !inFlight else { return }
        let params = currentParams()
        let edits = adjustments
        let enabled = frame.enabled
        let preset = frameCatalog.frame(frame.activeFrameId)
        let catalog = frameCatalog
        let label = filmLabel
        let ratio = resolvedRatioID
        let frameID = enabled ? frame.activeFrameId : "none"
        let markOn = includeWatermark && watermark.enabled
        let mark = markOn ? watermarkCatalog.preset(watermark.activeID) : nil
        let overlay = includeWatermark ? watermarkDraw() : nil
        let drawFrame = includeFrame && enabled
        inFlight = true
        busy = true
        errorText = nil
        status = drawFrame ? "正在按导出分辨率渲染" : "正在导出照片"
        let engine = self.engine
        logLine("SPEKTRAFILM_EXPORT_BEGIN framed=\(drawFrame) watermark=\(mark != nil) format=\(format.rawValue) frame=\(frameID) mark=\(mark?.id ?? "none") ratio=\(ratio)")
        Task {
            do {
                let rendered = try await Task.detached {
                    let native = ImageCodec.nativeLongEdge(data)
                    let edge = MemoryTier.exportLongEdge(nativeLongEdge: native)
                    let buffer = try ImageCodec.decode(data, maxLongEdge: edge)
                    logLine("SPEKTRAFILM_EXPORT_ENGINE edge=\(edge)")
                    let output = try engine.export(frame: buffer, params: params)
                    let adjusted = try PhotoProcessor.apply(output.image, settings: edits)
                    let source = CGSize(width: adjusted.width, height: adjusted.height)
                    let mode = catalog.canvasMode(ratioID: ratio, source: source)
                    let request: PaintRequest?
                    if drawFrame, let preset {
                        request = PaintRequest(
                            photo: adjusted,
                            preset: preset,
                            mode: mode,
                            sourceWidth: Double(source.width),
                            sourceHeight: Double(source.height),
                            filmLabel: label,
                            bits: 16,
                            opaqueBackdrop: format != .png
                        )
                    } else {
                        request = nil
                    }
                    let image = LabModel.compose(photo: adjusted, frame: request, watermark: overlay) ?? adjusted
                    let url = try ImageCodec.write(image, format: format)
                    return (url, image.width, image.height, output.elapsedMS)
                }.value
                engineOpen = false
                shareURL = rendered.0
                status = "导出 \(rendered.1)×\(rendered.2) · \(Self.seconds(rendered.3))"
                logLine("SPEKTRAFILM_EXPORT_OK \(rendered.1)x\(rendered.2) \(rendered.0.path)")
            } catch {
                engineOpen = false
                errorText = error.localizedDescription
                status = "导出失败"
                logLine("SPEKTRAFILM_EXPORT_FAIL \(error.localizedDescription)")
            }
            inFlight = false
            busy = false
            if dirty {
                dirty = false
                kickNow()
            }
        }
    }

    func waitUntilSettled() async {
        for _ in 0..<600 {
            if !busy, !inFlight, debounce == nil, pendingFilm == nil, pendingPaper == nil, paintsInFlight == 0 {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        logLine("SPEKTRAFILM_WAIT_TIMEOUT busy=\(busy) inFlight=\(inFlight) paints=\(paintsInFlight)")
    }

    private func use(data: Data, title: String, importID: String?) async throws {
        let source = try await Task.detached {
            let decoded = try ImageCodec.decode(data, maxLongEdge: MemoryTier.previewLongEdge)
            return (decoded, try Self.originalImage(decoded))
        }.value
        let decoded = source.0
        while inFlight {
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        let backupData = sourceData
        let backupTitle = sourceTitle
        let backupPixel = sourcePixel
        let backupProcessed = processed
        let backupKey = processedKey
        let backupAdjustments = processedAdjustments
        let backupEditingSource = editingSourcePreview
        let backupThumb = thumbPhoto
        let backupPreview = preview
        let backupImport = sourceImportID
        sourceData = data
        sourcePixel = ImageCodec.orientedPixelSize(data) ?? CGSize(width: decoded.width, height: decoded.height)
        sourceTitle = title
        sourceImportID = importID
        engineOpen = false
        await renderNow(decoded: decoded)
        guard errorText == nil, preview != nil else {
            let message = errorText ?? "导入失败"
            sourceData = backupData
            sourceTitle = backupTitle
            sourcePixel = backupPixel
            processed = backupProcessed
            processedKey = backupKey
            processedAdjustments = backupAdjustments
            editingSourcePreview = backupEditingSource
            thumbPhoto = backupThumb
            preview = backupPreview
            sourceImportID = backupImport
            engineOpen = false
            errorText = message
            status = "导入失败"
            throw EngineError.message(message)
        }
        if backupImport != importID {
            // A previous photo's crop must never become this photo's Undo action.
            undoManager?.removeAllActions(withTarget: self)
            undoStack.removeAll()
            undoBaseline = nil
            pendingFilm = nil
            pendingPaper = nil
            debounce?.cancel()
            debounce = nil
            syncCanUndo()
        }
        originalPreview = UIImage(cgImage: source.1)
        sourceRevision += 1
        catalogThumbToken += 1
        catalogThumbTask?.cancel()
        catalogThumbTask = nil
        catalogActiveContext = ""
        catalogThumbContexts = [:]
        catalogThumbs = [:]
        catalogSource = nil
        if let papers = catalogRequestedPapers {
            Task { await requestCatalogThumbnails(papers: papers) }
        }
    }

    /// Convert the already orientation-corrected Display-P3 decode; never decode a full original for comparison.
    private nonisolated static func originalImage(_ frame: FrameBuffer) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: frame.width * frame.height * 4)
        for pixel in 0..<(frame.width * frame.height) {
            for channel in 0..<3 {
                bytes[pixel * 4 + channel] = UInt8(min(255, max(0, (frame.pixels[pixel * 3 + channel] * 255).rounded())))
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.displayP3),
              let image = CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: frame.width * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw EngineError.message("无法生成原图预览。") }
        return image
    }

    /// One small serial engine renders actual film/paper alternatives, without changing the editor session.
    /// Cache is limited to one 160px image per catalog entry for the current source/context.
    func requestCatalogThumbnails(papers: Bool) async {
        catalogRequestedPapers = papers
        guard started, let data = sourceData,
              let resources = Bundle.main.url(forResource: "engine", withExtension: nil) else { return }
        let prefix = papers ? "paper:" : "film:"
        let context = "\(prefix)\(sourceRevision)|\(filmID)|\(paperID)|\(exposureEV)"
        if catalogThumbContexts[prefix] != context {
            catalogThumbs = catalogThumbs.filter { !$0.key.hasPrefix(prefix) }
            catalogThumbContexts[prefix] = context
        }
        if catalogActiveContext == context, let task = catalogThumbTask {
            await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
            guard !Task.isCancelled, catalogThumbContexts[prefix] == context else { return }
        }
        let stocks = papers ? catalog.papers : catalog.films
        let jobs: [(String, RenderParams)] = stocks.compactMap { stock in
            let key = prefix + stock.id
            guard catalogThumbs[key] == nil else { return nil }
            let target = stock.targetPrint.flatMap { catalog.paper($0)?.id } ?? paperID
            return (key, RenderParams(film: papers ? filmID : stock.id,
                                      paper: papers ? stock.id : target,
                                      // The wire schema requires >=800; the engine never upscales the 160px source.
                                      exposureEV: exposureEV, previewLongEdge: 800))
        }
        guard !jobs.isEmpty else { return }
        catalogThumbToken += 1
        let token = catalogThumbToken
        catalogThumbTask?.cancel()
        catalogActiveContext = context
        let engine = catalogEngine
        let cachedSource = catalogSource
        let task = Task.detached(priority: .utility) { [weak self] in
            do {
                try Task.checkCancellation()
                let small = try cachedSource ?? ImageCodec.decode(data, maxLongEdge: 160)
                try Task.checkCancellation()
                await MainActor.run { [weak self] in
                    guard let self, self.catalogThumbToken == token else { return }
                    self.catalogSource = small
                }
                try engine.start(resources: resources)
                for (key, params) in jobs {
                    try Task.checkCancellation()
                    // Open on the captured frame every time: a canceled generation can never reuse a newer source session.
                    let output = try engine.renderPreview(frame: small, params: params)
                    try Task.checkCancellation()
                    await MainActor.run { [weak self] in
                        guard let self, self.catalogThumbToken == token else { return }
                        self.catalogThumbs[key] = UIImage(cgImage: output.image)
                    }
                }
            } catch is CancellationError {
                // The next source/tab owns the queue; stale results never reach the UI.
            } catch {
                logLine("LITEFILM_CATALOG_THUMBS_FAIL \(error.localizedDescription)")
            }
            await MainActor.run { [weak self] in
                guard let self, self.catalogThumbToken == token else { return }
                self.catalogThumbTask = nil
                self.catalogActiveContext = ""
            }
        }
        catalogThumbTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Actual preset drawings on a plain neutral surface; no sample photograph or invented metadata.
    func requestWatermarkThumbnails() async {
        let context = WatermarkThumbContext(identity: watermark.identity, context: watermarkContext,
                                            presets: watermarkCatalog.presets)
        if watermarkThumbContext != context {
            watermarkThumbToken += 1
            watermarkThumbTask?.cancel()
            watermarkThumbTask = nil
            watermarkThumbs = [:]
            watermarkThumbContext = context
        } else if let task = watermarkThumbTask {
            await task.value
            guard !Task.isCancelled, watermarkThumbContext == context else { return }
        }
        let jobs = context.presets.filter { watermarkThumbs[$0.id] == nil }
        guard !jobs.isEmpty else { return }
        watermarkThumbToken += 1
        let token = watermarkThumbToken
        let task = Task.detached(priority: .utility) { [weak self] in
            if !Task.isCancelled, let base = Self.watermarkThumbnailSurface(),
               let background = FramePainter.pixels8(base) {
                for preset in jobs {
                    if Task.isCancelled { break }
                    let image = autoreleasepool { () -> CGImage? in
                        guard let painted = WatermarkPainter.apply(base, preset: preset, info: context.context,
                                                                   identity: context.identity, offset: .zero)
                        else { return nil }
                        return Self.focusedWatermarkThumbnail(painted, background: background.bytes)
                    }
                    if Task.isCancelled { break }
                    if let image {
                        await MainActor.run { [weak self] in
                            guard let self, self.watermarkThumbToken == token else { return }
                            self.watermarkThumbs[preset.id] = UIImage(cgImage: image)
                        }
                    }
                }
            }
            await MainActor.run { [weak self] in
                guard let self, self.watermarkThumbToken == token else { return }
                self.watermarkThumbTask = nil
            }
        }
        watermarkThumbTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private nonisolated static func watermarkThumbnailSurface() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 960, height: 640, bitsPerComponent: 8,
                                      bytesPerRow: 960 * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(colorSpace: space, components: [23/255, 26/255, 30/255, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 960, height: 640))
        return context.makeImage()
    }

    /// Enlarge the entire visible mark, preserving the relative positions of multi-part presets.
    /// The source is fixed at 960×640; one scan and crop run at a time, and only a 240px result is cached.
    private nonisolated static func focusedWatermarkThumbnail(_ image: CGImage, background: [UInt8]) -> CGImage? {
        guard let pixels = FramePainter.pixels8(image), pixels.bytes.count == background.count else { return nil }
        var left = pixels.width
        var top = pixels.height
        var right = -1
        var bottom = -1
        for y in 0..<pixels.height {
            if y % 64 == 0, Task.isCancelled { return nil }
            for x in 0..<pixels.width {
                let i = (y * pixels.width + x) * 4
                let difference = max(abs(Int(pixels.bytes[i]) - Int(background[i])),
                                     abs(Int(pixels.bytes[i + 1]) - Int(background[i + 1])),
                                     abs(Int(pixels.bytes[i + 2]) - Int(background[i + 2])))
                if difference > 4 {
                    left = min(left, x)
                    right = max(right, x)
                    top = min(top, y)
                    bottom = max(bottom, y)
                }
            }
        }
        guard right >= left, bottom >= top else { return FramePainter.downsample(image, longEdge: 240) }
        // pixels8 explicitly flips the bitmap vertically; CGImage cropping uses its native row order.
        let bounds = CGRect(x: left, y: pixels.height - bottom - 1,
                            width: right - left + 1, height: bottom - top + 1)
        let padding = max(18, min(bounds.width, bounds.height) * 0.24)
        let paddedWidth = bounds.width + padding * 2
        let paddedHeight = bounds.height + padding * 2
        let width = min(CGFloat(image.width), max(paddedWidth, paddedHeight * 1.5))
        let height = min(CGFloat(image.height), width / 1.5)
        let x = max(0, min(CGFloat(image.width) - width, bounds.midX - width / 2))
        let y = max(0, min(CGFloat(image.height) - height, bounds.midY - height / 2))
        let rect = CGRect(x: x, y: y, width: width, height: height).integral
        return FramePainter.downsample(image.cropping(to: rect) ?? image, longEdge: 240)
    }

    private func applyFilm(_ id: String, paperOverride: String?) {
        filmID = id
        if let paperOverride {
            paperID = paperOverride
        } else if let target = catalog.film(id)?.targetPrint, catalog.paper(target) != nil {
            paperID = target
        }
    }

    private func armSettle() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let self else { return }
            self.debounce = nil
            self.commitWheel()
        }
    }

    private func flushPending() {
        guard debounce != nil || pendingFilm != nil || pendingPaper != nil || undoBaseline != nil else { return }
        debounce?.cancel()
        debounce = nil
        commitWheel()
    }

    private func commitWheel() {
        let baseline = undoBaseline
        let film = pendingFilm
        let paper = pendingPaper
        undoBaseline = nil
        pendingFilm = nil
        pendingPaper = nil
        if film == nil && paper == nil && baseline == nil { return }
        if let film {
            applyFilm(film, paperOverride: paper)
        } else if let paper {
            paperID = paper
        }
        let changed = baseline.map { $0 != snapshot() } ?? true
        guard changed else { return }
        if let baseline { pushUndo(baseline) }
        persist()
        kickNow(keepingPending: true)
    }

    /// Frame, ratio, and mat changes reuse `processed`. Only film, paper, and exposure reopen the engine.
    private func refreshAppearance() {
        guard started, sourceData != nil else { return }
        if processed != nil, processedKey == currentParams(), processedAdjustments == adjustments {
            frameCacheHits += 1
            logLine("SPEKTRAFILM_FRAME_CACHE_HIT hits=\(frameCacheHits) engineRenders=\(engineRenderCount) film=\(filmID) paper=\(paperID) ev=\(exposureEV) frame=\(frame.enabled ? frame.activeFrameId : "none") ratio=\(resolvedRatioID)")
            paintsInFlight += 1
            Task { await self.paintPreviewAndWait(alreadyMarked: true) }
            return
        }
        if inFlight {
            logLine("SPEKTRAFILM_FRAME_WAIT_ENGINE frame=\(frame.activeFrameId) engineRenders=\(engineRenderCount)")
            return
        }
        kickNow(keepingPending: true)
    }

    private func kickNow(keepingPending: Bool = false, decoded: FrameBuffer? = nil) {
        if !keepingPending {
            pendingFilm = nil
            pendingPaper = nil
            undoBaseline = nil
        }
        debounce?.cancel()
        debounce = nil
        guard started, sourceData != nil else { return }
        if inFlight {
            dirty = true
            if decoded != nil { staged = decoded }
            return
        }
        inFlight = true
        busy = true
        let buffer = decoded
        Task { await self.renderBody(decoded: buffer) }
    }

    private func renderNow(decoded: FrameBuffer?) async {
        guard started, sourceData != nil else { return }
        if inFlight {
            dirty = true
            staged = decoded ?? staged
            return
        }
        inFlight = true
        busy = true
        await renderBody(decoded: decoded)
    }

    private func renderBody(decoded: FrameBuffer?) async {
        guard let data = sourceData else {
            inFlight = false
            busy = false
            return
        }
        errorText = nil
        let params = currentParams()
        let edits = adjustments
        let reopen = !engineOpen || decoded != nil
        let engine = self.engine
        status = reopen ? "正在渲染预览" : "正在换胶片"
        logLine("SPEKTRAFILM_ENGINE_RENDER reopen=\(reopen) film=\(params.film) paper=\(params.paper) ev=\(params.exposureEV)")
        do {
            let result = try await Task.detached {
                let base: Rendered
                if reopen {
                    let frame = try decoded ?? ImageCodec.decode(data, maxLongEdge: MemoryTier.previewLongEdge)
                    base = try engine.renderPreview(frame: frame, params: params)
                } else {
                    base = try engine.renderAgain(params: params)
                }
                let toned = try PhotoProcessor.tone(base.image, settings: edits)
                let adjusted = try PhotoProcessor.geometry(toned, settings: edits.geometry)
                return (Rendered(image: adjusted, width: adjusted.width, height: adjusted.height, elapsedMS: base.elapsedMS), toned)
            }.value
            let rendered = result.0
            let stale = dirty || edits != adjustments || params != currentParams()
            engineRenderCount += 1
            logLine("SPEKTRAFILM_ENGINE_DONE count=\(engineRenderCount) \(rendered.width)x\(rendered.height) ms=\(Int(rendered.elapsedMS))")
            if stale {
                inFlight = false
                busy = false
                dirty = false
                let next = staged
                staged = nil
                engineOpen = true
                await renderNow(decoded: next)
                return
            }
            processed = rendered.image
            processedKey = params
            processedAdjustments = edits
            editingSourcePreview = UIImage(cgImage: result.1)
            engineOpen = true
            thumbPhoto = FramePainter.downsample(rendered.image, longEdge: 280)
            status = "预览 \(rendered.width)×\(rendered.height) · \(Self.seconds(rendered.elapsedMS))"
            inFlight = false
            busy = false
            await paintPreviewAndWait()
            scheduleThumbs()
        } catch {
            inFlight = false
            busy = false
            engineOpen = false
            errorText = error.localizedDescription
            status = "渲染失败"
            logLine("SPEKTRAFILM_ENGINE_FAIL \(error.localizedDescription)")
            if dirty {
                dirty = false
                let next = staged
                staged = nil
                await renderNow(decoded: next)
            }
        }
    }

    private func paintPreviewAndWait(alreadyMarked: Bool = false) async {
        if !alreadyMarked { paintsInFlight += 1 }
        defer { paintsInFlight -= 1 }
        guard let processed else { return }
        frameToken += 1
        let token = frameToken
        let photo = processed
        let request = makePaint(photo, bits: 8, opaque: false)
        let overlay = watermarkDraw()
        if request == nil && overlay == nil {
            preview = UIImage(cgImage: photo)
            return
        }
        let image = await Task.detached(priority: .userInitiated) {
            LabModel.compose(photo: photo, frame: request, watermark: overlay)
        }.value
        guard token == frameToken else {
            logLine("SPEKTRAFILM_FRAME_STALE_DROP token=\(token)")
            return
        }
        if let image {
            preview = UIImage(cgImage: image)
        }
    }

    /// Still used by the self-test for the four export combinations. Same painter path as `export`.
    func proofStill(includeFrame: Bool, includeWatermark: Bool) -> CGImage? {
        guard let processed else { return nil }
        let request: PaintRequest? = includeFrame ? makePaint(processed, bits: 8, opaque: false) : nil
        let overlay: WatermarkDraw? = includeWatermark ? watermarkDraw() : nil
        return LabModel.compose(photo: processed, frame: request, watermark: overlay)
    }

    private func watermarkDraw() -> WatermarkDraw? {
        guard watermark.enabled, let preset = watermarkCatalog.preset(watermark.activeID) else { return nil }
        return WatermarkDraw(
            preset: preset,
            context: watermarkContext,
            identity: watermark.identity,
            offsetX: watermark.offsetX,
            offsetY: watermark.offsetY
        )
    }

    /// Photo opening in the current preview/export canvas, or the full image when no frame.
    func previewContentRect(for photo: CGImage) -> CGRect {
        if let request = makePaint(photo, bits: 8, opaque: false),
           let layout = FramePainter.layout(for: request) {
            return layout.photo
        }
        return CGRect(x: 0, y: 0, width: photo.width, height: photo.height)
    }

    /// Pixel-space photo opening for the image currently on screen.
    func currentPreviewContentRect() -> CGRect? {
        if let processed {
            let rect = previewContentRect(for: processed)
            if let preview = preview?.cgImage,
               preview.width > 0,
               preview.height > 0,
               (preview.width != Int(rect.width.rounded()) || abs(CGFloat(preview.width) - rect.width) > 1) {
                // Framed canvas matches layout; scale if the published preview differs.
                if let request = makePaint(processed, bits: 8, opaque: false),
                   let layout = FramePainter.layout(for: request),
                   layout.canvasWidth > 1,
                   layout.canvasHeight > 1 {
                    let sx = CGFloat(preview.width) / layout.canvasWidth
                    let sy = CGFloat(preview.height) / layout.canvasHeight
                    return CGRect(
                        x: layout.photo.minX * sx,
                        y: layout.photo.minY * sy,
                        width: layout.photo.width * sx,
                        height: layout.photo.height * sy
                    )
                }
            }
            return rect
        }
        guard let preview = preview?.cgImage else { return nil }
        return CGRect(x: 0, y: 0, width: preview.width, height: preview.height)
    }

    nonisolated static func compose(photo: CGImage, frame: PaintRequest?, watermark: WatermarkDraw?) -> CGImage? {
        var image = photo
        var photoRect: CGRect?
        if let frame {
            photoRect = FramePainter.layout(for: frame)?.photo
            if let painted = FramePainter.composite(frame) {
                image = painted
            }
        }
        if let watermark {
            let rect = watermark.contentRect ?? photoRect
            if let marked = WatermarkPainter.apply(
                image,
                preset: watermark.preset,
                info: watermark.context,
                identity: watermark.identity,
                contentRect: rect,
                offset: CGSize(width: watermark.offsetX, height: watermark.offsetY)
            ) {
                image = marked
            }
        }
        return image
    }

    private func makePaint(_ photo: CGImage, bits: Int, opaque: Bool) -> PaintRequest? {
        guard frame.enabled, let preset = frameCatalog.frame(frame.activeFrameId) else { return nil }
        return PaintRequest(
            photo: photo,
            preset: preset,
            mode: frameCatalog.canvasMode(ratioID: resolvedRatioID, source: CGSize(width: photo.width, height: photo.height)),
            sourceWidth: Double(photo.width),
            sourceHeight: Double(photo.height),
            filmLabel: filmLabel,
            bits: bits,
            opaqueBackdrop: opaque
        )
    }

    private func scheduleThumbs() {
        let key = "\(engineRenderCount)|\(frame.ratio.mode)|\(frame.ratio.ratioId)"
        if key == thumbKey, !thumbs.isEmpty { return }
        thumbKey = key
        rebuildThumbs()
    }

    private func rebuildThumbs() {
        guard let thumbPhoto else { return }
        thumbToken += 1
        let token = thumbToken
        let shared = SharedImage(image: thumbPhoto)
        let source = CGSize(width: processed?.width ?? thumbPhoto.width, height: processed?.height ?? thumbPhoto.height)
        let label = filmLabel
        let jobs: [ThumbJob] = frameCatalog.frames.map { preset in
            let ratio = frame.ratio.mode == "followFrame" ? preset.defaultRatioId : frame.ratio.ratioId
            return ThumbJob(preset: preset, mode: frameCatalog.canvasMode(ratioID: ratio, source: source))
        }
        thumbs = [:]
        thumbTask?.cancel()
        thumbTask = Task.detached(priority: .utility) {
            await withTaskGroup(of: ThumbOut?.self) { group in
                var next = 0
                while next < min(3, jobs.count) {
                    let job = jobs[next]
                    next += 1
                    group.addTask { Self.renderThumb(job, photo: shared, source: source, label: label) }
                }
                while let item = await group.next() {
                    if let item {
                        await MainActor.run {
                            guard token == self.thumbToken else { return }
                            self.thumbs[item.id] = UIImage(cgImage: item.image)
                        }
                    }
                    if next < jobs.count {
                        let job = jobs[next]
                        next += 1
                        group.addTask { Self.renderThumb(job, photo: shared, source: source, label: label) }
                    }
                }
            }
        }
    }

    private nonisolated static func renderThumb(_ job: ThumbJob, photo: SharedImage, source: CGSize, label: String) -> ThumbOut? {
        if Task.isCancelled { return nil }
        let request = PaintRequest(
            photo: photo.image,
            preset: job.preset,
            mode: job.mode,
            sourceWidth: Double(source.width),
            sourceHeight: Double(source.height),
            filmLabel: label,
            bits: 8,
            opaqueBackdrop: false
        )
        guard let image = FramePainter.composite(request) else { return nil }
        return ThumbOut(id: job.preset.id, image: image)
    }

    private func currentParams() -> RenderParams {
        RenderParams(
            film: filmID,
            paper: paperID,
            exposureEV: exposureEV,
            previewLongEdge: MemoryTier.previewLongEdge
        )
    }

    private func applyRecipe(_ recipe: GalleryRecipe) {
        if catalog.film(recipe.filmID) != nil { filmID = recipe.filmID }
        if catalog.paper(recipe.paperID) != nil { paperID = recipe.paperID }
        if (-2.0...2.0).contains(recipe.exposureEV) { exposureEV = recipe.exposureEV }
        var nextFrame = recipe.frame
        nextFrame.sanitize(catalog: frameCatalog)
        frame = nextFrame
        var nextMark = recipe.watermark
        nextMark.sanitize(catalog: watermarkCatalog)
        watermark = nextMark
        adjustments = (recipe.adjustments ?? PhotoAdjustments()).sanitized()
        pendingFilm = nil
        pendingPaper = nil
        undoBaseline = nil
    }

    private func variantTitle() -> String {
        let film = catalog.film(filmID)?.name ?? "胶片"
        let frameName: String
        if frame.enabled, let preset = frameCatalog.frame(frame.activeFrameId) {
            frameName = preset.nameZh
        } else {
            frameName = "无框"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d HH:mm"
        return "\(film) · \(frameName) · \(formatter.string(from: Date()))"
    }

    private func snapshot() -> EditSnapshot {
        EditSnapshot(filmID: filmID, paperID: paperID, exposureEV: exposureEV, frame: frame, watermark: watermark, adjustments: adjustments)
    }

    private func pushUndo(_ previous: EditSnapshot) {
        guard previous != snapshot() else { return }
        if let undoManager {
            undoManager.registerUndo(withTarget: self) { target in
                target.restore(previous, recordInverse: true)
            }
            undoManager.setActionName("编辑")
        } else {
            undoStack.append(previous)
            if undoStack.count > 40 {
                undoStack.removeFirst(undoStack.count - 40)
            }
        }
        syncCanUndo()
    }

    private func restore(_ previous: EditSnapshot, recordInverse: Bool) {
        let current = snapshot()
        filmID = previous.filmID
        paperID = previous.paperID
        exposureEV = previous.exposureEV
        frame = previous.frame
        watermark = previous.watermark
        adjustments = previous.adjustments
        if recordInverse { pushUndo(current) }
        persist()
        let filmTouched = current.filmID != previous.filmID
            || current.paperID != previous.paperID
            || abs(current.exposureEV - previous.exposureEV) > 0.0001
            || current.adjustments != previous.adjustments
        if filmTouched {
            kickNow(keepingPending: true)
        } else {
            refreshAppearance()
        }
        syncCanUndo()
    }

    private func syncCanUndo() {
        let value = undoManager?.canUndo ?? !undoStack.isEmpty
        if canUndo != value { canUndo = value }
    }

    private func persist() {
        guard persistEnabled else { return }
        let payload = PersistedEdit(
            schemaVersion: 6,
            filmID: filmID,
            paperID: paperID,
            exposureEV: exposureEV,
            frame: frame,
            watermark: watermark,
            exportIncludeFrame: exportIncludeFrame,
            exportIncludeWatermark: exportIncludeWatermark,
            previewTransition: previewTransition.rawValue,
            sourceImportID: sourceImportID,
            adjustments: adjustments
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.persistKey)
    }

    private func restorePersisted() {
        guard let data = defaults.data(forKey: Self.persistKey),
              let saved = try? JSONDecoder().decode(PersistedEdit.self, from: data)
        else {
            frame = FrameEditState.makeDefault(catalog: frameCatalog)
            return
        }
        if let film = saved.filmID, catalog.film(film) != nil { filmID = film }
        if let paper = saved.paperID, catalog.paper(paper) != nil { paperID = paper }
        if let exposure = saved.exposureEV, (-2.0...2.0).contains(exposure) {
            exposureEV = exposure
        }
        if var savedFrame = saved.frame {
            savedFrame.sanitize(catalog: frameCatalog)
            frame = savedFrame
        } else {
            frame = FrameEditState.makeDefault(catalog: frameCatalog)
        }
        if var savedMark = saved.watermark {
            savedMark.sanitize(catalog: watermarkCatalog)
            watermark = savedMark
        }
        adjustments = (saved.adjustments ?? PhotoAdjustments()).sanitized()
        if let includeFrame = saved.exportIncludeFrame { exportIncludeFrame = includeFrame }
        if let includeWatermark = saved.exportIncludeWatermark { exportIncludeWatermark = includeWatermark }
        previewTransition = PreviewTransition.resolve(saved.previewTransition)
        if let importID = saved.sourceImportID, gallery.item(id: importID) != nil {
            sourceImportID = importID
        } else {
            sourceImportID = nil
        }
        logLine("SPEKTRAFILM_FRAME_RESTORED enabled=\(frame.enabled) id=\(frame.activeFrameId) ratio=\(frame.ratio.mode)/\(frame.ratio.ratioId) mark=\(watermark.enabled ? watermark.activeID : "none") transition=\(previewTransition.rawValue) import=\(sourceImportID ?? "sample")")
    }

    private func armPreviewSwap(_ move: FrameMove) {
        previewSwap = PreviewSwap(token: previewSwap.token + 1, move: move)
    }

    private static let persistKey = "spektrafilm.edit.v1"

    private static func seconds(_ milliseconds: Double) -> String {
        String(format: "%.1f 秒", milliseconds / 1000)
    }
}

private struct SharedImage: @unchecked Sendable {
    var image: CGImage
}

private struct ThumbJob: Sendable {
    var preset: FramePreset
    var mode: FrameCanvasMode
}

private struct ThumbOut: @unchecked Sendable {
    var id: String
    var image: CGImage
}

struct WatermarkDraw: Sendable {
    var preset: WatermarkPreset
    var context: WatermarkContext
    var identity: WatermarkIdentity = .blank
    var contentRect: CGRect? = nil
    var offsetX: Double = 0
    var offsetY: Double = 0
}
