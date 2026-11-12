import SwiftUI
import UIKit

enum BatchValidationError: LocalizedError {
    case invalidLongEdge, invalidSizeLimit, invalidCount, missingPreset
    var errorDescription: String? {
        switch self {
        case .invalidLongEdge: return "请选择有效的导出长边。"
        case .invalidSizeLimit: return "每张体积上限请输入 1–1,000,000 KB 的整数。"
        case .invalidCount: return "每批请选择 1–50 张照片。"
        case .missingPreset: return "所选配方不可用，请重新选择。"
        }
    }
}

struct BatchExportOptions: @unchecked Sendable {
    var format: ExportFormat = .jpeg
    /// Zero means native dimensions subject to the shared device-memory ceiling.
    var longEdge = 2048
    var maxBytes: Int? = nil
    var includeFrame = true
    var includeWatermark = true
    var includeText = true

    func validate() throws {
        guard [0, 1280, 2048, 4096].contains(longEdge) else { throw BatchValidationError.invalidLongEdge }
        if let maxBytes, !(1...(ExportSizeLimit.maximumKB * 1000)).contains(maxBytes) {
            throw BatchValidationError.invalidSizeLimit
        }
    }
}

enum BatchRecipe {
    static func resolve(saved: GalleryRecipe?, fallback: GalleryRecipe, override: GalleryRecipe?) -> GalleryRecipe {
        if override == nil, let saved { return saved }
        var recipe = override ?? fallback
        var adjustments = recipe.adjustments ?? PhotoAdjustments()
        // Spatial edits always belong to the destination photo, never to a preset.
        adjustments.geometry = saved?.adjustments?.geometry ?? PhotoGeometry()
        adjustments.retouch = saved?.adjustments?.retouch ?? RetouchEdits()
        recipe.adjustments = adjustments.sanitized()
        return recipe
    }
}

struct BatchInput: Sendable {
    let id: String
    let title: String
    let sourceURL: URL
    let recipe: GalleryRecipe
}

struct BatchSnapshot: @unchecked Sendable {
    static let maximumCount = 50
    let inputs: [BatchInput]
    let options: BatchExportOptions
    let films: FilmCatalog
    let frames: FrameCatalog
    let watermarks: WatermarkCatalog
    let dateText: String

    func validate() throws {
        try options.validate()
        guard (1...Self.maximumCount).contains(inputs.count) else { throw BatchValidationError.invalidCount }
    }
}

struct BatchOutput: Identifiable, Sendable {
    let id: String
    let title: String
    let url: URL?
    let detail: String
    var succeeded: Bool { url != nil }
}

/// Shared serial actor: at most one batch image is decoded/rendered/encoded at a
/// time, even if another caller bypasses the sheet. This engine never owns editor state.
actor BatchProcessor {
    static let shared = BatchProcessor()
    private let engine = EngineClient()
    private var started = false

    func render(_ input: BatchInput, snapshot: BatchSnapshot) throws -> BatchOutput {
        try snapshot.validate()
        guard snapshot.inputs.contains(where: { $0.id == input.id && $0.sourceURL == input.sourceURL }) else {
            throw BatchValidationError.invalidCount
        }
        if !started {
            guard let resources = Bundle.main.url(forResource: "engine", withExtension: nil) else {
                throw EngineError.message("安装包里没有渲染引擎资源。")
            }
            try engine.start(resources: resources)
            started = true
        }
        return try autoreleasepool {
            let options = snapshot.options
            var recipe = input.recipe
            guard snapshot.films.film(recipe.filmID) != nil, snapshot.films.paper(recipe.paperID) != nil else {
                throw EngineError.message("该照片的胶片或相纸配方已不可用。")
            }
            recipe.frame.sanitize(catalog: snapshot.frames)
            recipe.watermark.sanitize(catalog: snapshot.watermarks)
            let data = try Data(contentsOf: input.sourceURL, options: .mappedIfSafe)
            let native = ImageCodec.nativeLongEdge(data)
            let memoryEdge = MemoryTier.exportLongEdge(nativeLongEdge: native)
            let edge = options.longEdge == 0 ? memoryEdge : min(memoryEdge, options.longEdge)
            let buffer = try ImageCodec.decode(data, maxLongEdge: edge)
            let params = RenderParams(film: recipe.filmID, paper: recipe.paperID,
                exposureEV: recipe.exposureEV.isFinite ? min(2, max(-2, recipe.exposureEV)) : 0,
                previewLongEdge: MemoryTier.previewLongEdge)
            let rendered = try engine.export(frame: buffer, params: params)
            let adjusted = try PhotoProcessor.apply(rendered.image, settings: recipe.adjustments ?? PhotoAdjustments())
            let source = CGSize(width: adjusted.width, height: adjusted.height)
            let framePreset = recipe.frame.enabled ? snapshot.frames.frame(recipe.frame.activeFrameId) : nil
            let ratio = recipe.frame.ratio.mode == "followFrame" ? (framePreset?.defaultRatioId ?? "source") : recipe.frame.ratio.ratioId
            let filmLabel = snapshot.films.film(recipe.filmID)?.name ?? ""
            let request: PaintRequest?
            if options.includeFrame, let preset = framePreset {
                request = PaintRequest(photo: adjusted, preset: preset,
                    mode: snapshot.frames.canvasMode(ratioID: ratio, source: source),
                    sourceWidth: Double(source.width), sourceHeight: Double(source.height),
                    filmLabel: filmLabel, bits: 16, opaqueBackdrop: options.format != .png)
            } else { request = nil }
            let mark: WatermarkDraw?
            if options.includeWatermark, recipe.watermark.enabled,
               let preset = snapshot.watermarks.preset(recipe.watermark.activeID) {
                let frameIndex = framePreset.flatMap { snapshot.frames.index(of: $0.id) }
                let context = WatermarkContext(filmName: filmLabel, frameName: framePreset?.nameZh ?? "",
                    frameCode: framePreset?.id ?? "", frameNumber: frameIndex.map { String(format: "%02d", $0 + 1) } ?? "",
                    frameTotal: frameIndex == nil ? "" : String(snapshot.frames.frames.count), dateText: snapshot.dateText)
                mark = WatermarkDraw(preset: preset, context: context, identity: recipe.watermark.identity,
                    offsetX: recipe.watermark.offsetX, offsetY: recipe.watermark.offsetY)
            } else { mark = nil }
            let text = options.includeText ? PhotoTextLayer.sanitized(recipe.textLayers ?? []) : []
            guard let composed = LabModel.compose(photo: adjusted, frame: request, watermark: mark, text: text) else {
                throw EngineError.message("照片合成失败。")
            }
            // The final canvas, including a frame, obeys the chosen output ceiling.
            let final = FramePainter.downsample(composed, longEdge: edge)
            guard max(final.width, final.height) <= edge else {
                throw EngineError.message("无法将最终画面缩小到所选长边。")
            }
            let file = try ImageCodec.writeExport(final, format: options.format, maxBytes: options.maxBytes)
            return BatchOutput(id: input.id, title: input.title, url: file.url,
                detail: "\(file.width) × \(file.height) · \(ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file))")
        }
    }
}

@MainActor
private final class BatchRunState: ObservableObject {
    let model: LabModel
    let items: [GalleryItem]
    let totalSelected: Int
    let fallback: GalleryRecipe
    let presets: [SavedRecipe]
    let copied: GalleryRecipe?
    @Published var selection = "own"
    @Published var options = BatchExportOptions()
    @Published var capEnabled = false
    @Published var capKB = "2000"
    @Published private(set) var running = false
    @Published private(set) var cancelRequested = false
    @Published private(set) var completed = 0
    @Published private(set) var currentTitle = ""
    @Published private(set) var outputs: [BatchOutput] = []
    @Published private(set) var status = "设置只应用于本次批量导出"
    @Published private(set) var error: String?
    private var runID = UUID()
    private var task: Task<Void, Never>?

    init(model: LabModel, items: [GalleryItem]) {
        self.model = model
        self.totalSelected = items.count
        self.items = Array(items.prefix(BatchSnapshot.maximumCount))
        self.fallback = model.currentRecipe(portable: true)
        self.presets = model.recipeBook.presets
        self.copied = model.recipeBook.copied
    }

    var successfulURLs: [URL] { outputs.compactMap(\.url) }
    var invalidCap: Bool { capEnabled && ExportSizeLimit.bytes(fromKB: capKB) == nil }

    func cancel() {
        guard running else { return }
        cancelRequested = true
        status = "正在完成当前照片，随后停止；当前结果不会加入分享"
    }

    func start() {
        guard !running else { return }
        do {
            var options = options
            if capEnabled {
                guard let bytes = ExportSizeLimit.bytes(fromKB: capKB) else { throw BatchValidationError.invalidSizeLimit }
                options.maxBytes = bytes
            } else { options.maxBytes = nil }
            let override: GalleryRecipe?
            switch selection {
            case "own": override = nil
            case "current": override = fallback
            case "copied":
                guard let copied else { throw BatchValidationError.missingPreset }
                override = copied
            default:
                guard let preset = presets.first(where: { $0.id.uuidString == selection }) else { throw BatchValidationError.missingPreset }
                override = preset.recipe
            }
            let snapshot = BatchSnapshot(inputs: items.map { item in
                BatchInput(id: item.id, title: item.title, sourceURL: model.gallery.originalURL(for: item),
                    recipe: BatchRecipe.resolve(saved: item.recipe, fallback: fallback, override: override))
            }, options: options, films: model.catalog, frames: model.frameCatalog,
                watermarks: model.watermarkCatalog, dateText: WatermarkContext.dateText(Date()))
            try snapshot.validate()
            let identity = UUID(); runID = identity
            running = true; cancelRequested = false; completed = 0; outputs = []; error = nil
            status = "等待当前编辑完成…"
            task = Task {
                guard await model.beginBatchRendering() else {
                    error = "编辑器仍在处理照片，请稍后重试。"; running = false; task = nil
                    return
                }
                defer { model.endBatchRendering() }
                guard runID == identity else { return }
                for (index, input) in snapshot.inputs.enumerated() {
                    guard !cancelRequested, runID == identity else { break }
                    currentTitle = input.title
                    status = "正在处理 \(index + 1) / \(snapshot.inputs.count)"
                    let output: BatchOutput
                    do { output = try await BatchProcessor.shared.render(input, snapshot: snapshot) }
                    catch { output = BatchOutput(id: input.id, title: input.title, url: nil, detail: error.localizedDescription) }
                    // Cancellation may arrive while a synchronous engine call is finishing.
                    // Never publish that late result as a successful fresh output.
                    guard !cancelRequested, runID == identity else { break }
                    outputs.append(output); completed += 1
                }
                guard runID == identity else { return }
                let successes = successfulURLs.count
                let failures = outputs.count - successes
                status = "\(cancelRequested ? "已取消" : "处理完成") · 成功 \(successes) 张 · 失败 \(failures) 张"
                currentTitle = ""; running = false; task = nil
            }
        } catch { self.error = error.localizedDescription }
    }
}

struct BatchProcessingSheet: View {
    @StateObject private var state: BatchRunState
    @Environment(\.dismiss) private var dismiss
    @State private var showingShare = false

    @MainActor
    init(model: LabModel, items: [GalleryItem]) {
        _state = StateObject(wrappedValue: BatchRunState(model: model, items: items))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("本批 \(state.items.count) 张照片").font(.headline)
                    if state.totalSelected > BatchSnapshot.maximumCount {
                        Text("每批最多 50 张，本次仅处理所选列表中的前 50 张。")
                            .foregroundStyle(Ink.ember)
                    }
                    Picker("配方", selection: $state.selection) {
                        Text("各照片已存配方").tag("own")
                        Text("打开面板时的当前风格").tag("current")
                        if state.copied != nil { Text("已复制的配方").tag("copied") }
                        ForEach(state.presets) { preset in Text(preset.name).tag(preset.id.uuidString) }
                    }.accessibilityIdentifier("batch.recipe")
                    Text(state.selection == "own"
                        ? "有配方的照片保留原设置；未保存配方的导入照片使用打开面板时的当前风格。"
                        : "批量应用所选风格，保留每张照片自己的裁剪、透视与局部修饰。")
                        .font(.caption).foregroundStyle(Ink.mute)
                }.disabled(state.running)
                Section("导出设置") {
                    Picker("格式", selection: $state.options.format) {
                        ForEach(ExportFormat.allCases) { format in Text(format.title).tag(format) }
                    }
                    Picker("最长边", selection: $state.options.longEdge) {
                        Text("1280 像素").tag(1280)
                        Text("2048 像素").tag(2048)
                        Text("4096 像素").tag(4096)
                        Text("原尺寸（设备上限内）").tag(0)
                    }
                    Toggle("限制每张文件体积", isOn: $state.capEnabled)
                    if state.capEnabled {
                        HStack {
                            Text("每张上限")
                            TextField("KB", text: $state.capKB).keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing).accessibilityLabel("每张文件体积上限，KB")
                            Text("KB").foregroundStyle(Ink.mute)
                        }
                        if state.invalidCap { Text(BatchValidationError.invalidSizeLimit.localizedDescription).font(.caption).foregroundStyle(Ink.ember) }
                    }
                    Toggle("包含配方中的相框", isOn: $state.options.includeFrame)
                    Toggle("包含配方中的水印", isOn: $state.options.includeWatermark)
                    Toggle("包含配方中的照片文字", isOn: $state.options.includeText)
                    Text("不会放大小图；设备内存会进一步限制长边。体积限制可能降低画质和尺寸；相框、水印仅在配方已启用时添加。")
                        .font(.caption).foregroundStyle(Ink.mute)
                }.disabled(state.running)
                Section {
                    if state.running {
                        ProgressView(value: Double(state.completed), total: Double(max(1, state.items.count)))
                        if !state.currentTitle.isEmpty { Text(state.currentTitle).lineLimit(2).font(.subheadline) }
                    }
                    Text(state.status).font(.subheadline).accessibilityIdentifier("batch.status")
                    if let error = state.error { Text(error).foregroundStyle(Ink.ember) }
                    if state.running {
                        Button("取消剩余照片", role: .destructive) { state.cancel() }
                            .disabled(state.cancelRequested).accessibilityIdentifier("batch.cancel")
                    } else {
                        Button(state.outputs.isEmpty ? "开始批量导出" : "按当前设置重新导出") { state.start() }
                            .disabled(state.items.isEmpty || state.invalidCap)
                            .accessibilityIdentifier("batch.start")
                    }
                    if !state.successfulURLs.isEmpty {
                        Button { showingShare = true } label: {
                            Label("分享已完成的 \(state.successfulURLs.count) 张", systemImage: "square.and.arrow.up")
                        }.disabled(state.running).accessibilityIdentifier("batch.share")
                    }
                }
                if !state.outputs.isEmpty {
                    Section("逐张结果") {
                        ForEach(state.outputs) { output in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(output.title, systemImage: output.succeeded ? "checkmark.circle" : "exclamationmark.triangle")
                                Text(output.detail).font(.caption).foregroundStyle(output.succeeded ? Ink.mute : Ink.ember)
                            }.padding(.vertical, 3)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Ink.void)
            .navigationTitle("批量处理").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }.disabled(state.running)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
        }
        .tint(Ink.amber).preferredColorScheme(.dark)
        .interactiveDismissDisabled(state.running)
        .sheet(isPresented: $showingShare) { BatchShareSheet(urls: state.successfulURLs) }
    }
}

private struct BatchShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
