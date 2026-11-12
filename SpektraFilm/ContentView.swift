import PhotosUI
import SwiftUI

struct ContentView: View {
    @StateObject private var model = LabModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showSettings = false
    @State private var showSignature = false
    @State private var showFrames = false
    @State private var showExport = false
    @State private var showDetail = false
    @State private var showRecipes = false
    @State private var showHistory = false
    @State private var fullscreen = false
    @State private var comparing = false
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        ZStack(alignment: .top) {
            Ink.void.ignoresSafeArea()
            switch model.stage {
            case .home:
                HomeColorChartView(model: model, pickerItem: $pickerItem,
                    onOpenGallery: { model.openGallery() },
                    onOpenSettings: { showSettings = true })
            case .gallery:
                ImportGalleryView(model: model, pickerItem: $pickerItem)
            case .editor:
                editor
            }
            if let notice = model.noticeText {
                Text(notice)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Ink.ivory)
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .background(Ink.surface, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 24).padding(.top, 58)
                    .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Ink.amber)
        .task {
            if CommandLine.arguments.contains("--editing-suite-self-test") {
                do { try await EditingSuiteSelfTest.run(); logLine("LITEFILM_EDITING_SUITE_OK"); exit(0) }
                catch { logLine("LITEFILM_EDITING_SUITE_FAIL \(error)"); exit(1) }
            }
            if CommandLine.arguments.contains("--text-self-test") {
                do { try await PhotoTextSelfTest.run(); exit(0) }
                catch { logLine("LITEFILM_TEXT_SELFTEST_FAIL \(error)"); exit(1) }
            }
            if CommandLine.arguments.contains("--self-test") {
                let code = await Task.detached(priority: .userInitiated) { SelfTest.run() }.value
                logLine("SPEKTRAFILM_SELFTEST_EXIT \(code)")
                exit(Int32(code))
            }
            if CommandLine.arguments.contains("--frame-self-test") {
                let code = await FrameSelfTest.run()
                logLine("SPEKTRAFILM_FRAME_SELFTEST_EXIT \(code)")
                exit(Int32(code))
            }
            await model.bootstrap()
        }
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in model.undoManager = manager }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await model.load(item: item); pickerItem = nil }
        }
        .onChange(of: model.stage) { _, stage in
            if stage != .editor { fullscreen = false; comparing = false }
        }
        .sheet(isPresented: $showSettings) { ObsidianSettingsSheet(model: model) }
        .fullScreenCover(isPresented: $model.showCropEditor) { CropEditor(model: model) }
        .sheet(isPresented: $showSignature) { ObsidianSignatureSheet(model: model) }
        .sheet(isPresented: $showFrames) { FrameGallerySheet(model: model) }
        .sheet(isPresented: $showExport) { ObsidianExportSheet(model: model) }
        .sheet(isPresented: $showRecipes) { RecipeBookSheet(model: model) }
        .sheet(isPresented: $showHistory) { EditHistorySheet(model: model) }
        .fullScreenCover(isPresented: $showDetail) {
            if let image = model.inspectionPreview { PhotoDetailView(image: image, original: model.originalPreview) }
        }
        .sheet(item: shareItem) { ActivityShare(url: $0.url) }
    }

    private func openDetail() {
        model.finishPendingEdits()
        Task {
            await model.waitUntilSettled()
            if !model.busy, model.errorText == nil { showDetail = true }
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            ObsidianHeader {
                Button {
                    if fullscreen { fullscreen = false } else { model.openHome() }
                } label: {
                    Image(systemName: fullscreen ? "chevron.down" : "chevron.left")
                        .frame(width: 44, height: 44)
                }.accessibilityLabel(fullscreen ? "退出全屏" : "返回首页")
            } trailing: {
                Button { showExport = true } label: {
                    Text("导出").font(.subheadline.weight(.semibold))
                        .foregroundStyle(Ink.void)
                        .frame(width: 58, height: 34)
                        .background(Ink.amber, in: Capsule())
                        .frame(minHeight: 44)
                }
                .opacity(model.preview == nil || model.busy ? 0.4 : 1)
                .disabled(model.preview == nil || model.busy)
            }
            GeometryReader { geo in
                if fullscreen {
                    preview
                } else {
                    let landscape = geo.size.width > geo.size.height
                    // Keep EditorControls identity and presented drafts when the device rotates.
                    let layout = landscape ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
                    layout {
                        preview
                        controls(panelHeight: landscape
                            ? max(80, geo.size.height - 110)
                            : min(218, max(130, geo.size.height - 310)))
                            .frame(width: landscape ? min(360, geo.size.width * 0.46) : nil)
                    }
                }
            }
            if let error = model.errorText {
                Text(error).font(.caption).foregroundStyle(Ink.ember)
                    .padding(.horizontal, 20).padding(.vertical, 6)
            }
        }
    }

    private var preview: some View {
        ZStack {
            PrintViewport(model: model) { showFrames = true }
            if comparing, let original = model.originalPreview {
                Ink.void
                Image(uiImage: original).resizable().scaledToFit()
                    .accessibilityLabel("原始照片")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func controls(panelHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button { model.undo() } label: {
                    Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44)
                }.disabled(!model.canUndo || model.busy).accessibilityLabel("撤销")
                Button { model.redo() } label: {
                    Image(systemName: "arrow.uturn.forward").frame(width: 40, height: 44)
                }.disabled(!model.canRedo || model.busy).accessibilityLabel("重做")
                Button { openDetail() } label: {
                    Image(systemName: "plus.magnifyingglass").frame(width: 40, height: 44)
                }.disabled(model.preview == nil || model.busy).accessibilityLabel("放大与直方图")
                Spacer(minLength: 0)
                Text(comparing ? "原图" : "按住对比")
                    .font(.caption).foregroundStyle(Ink.mute)
                Image(systemName: "rectangle.lefthalf.inset.filled")
                    .frame(width: 44, height: 44).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { _ in comparing = true }
                        .onEnded { _ in comparing = false })
                    .accessibilityLabel("对比原图")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { comparing.toggle() }
                Menu {
                    Button("放大、直方图与过曝提示", systemImage: "plus.magnifyingglass") { openDetail() }
                        .disabled(model.preview == nil || model.busy)
                    Button("我的配方与复制调整", systemImage: "slider.horizontal.3") { model.finishPendingEdits(); showRecipes = true }
                    Button("编辑历史", systemImage: "clock.arrow.circlepath") { model.finishPendingEdits(); showHistory = true }
                    Button("全屏预览", systemImage: "arrow.up.left.and.arrow.down.right") { fullscreen = true }
                    Button("保存方案", systemImage: "bookmark") { model.saveCurrentLookToGallery() }
                        .disabled(model.busy || model.preview == nil)
                    Button("作品", systemImage: "square.grid.2x2") { model.openGallery() }
                    PhotosPicker(selection: $pickerItem, matching: PhotoImport.pickerFilter,
                                 preferredItemEncoding: PhotoImport.preferredEncoding) {
                        Label("导入照片", systemImage: "photo")
                    }
                    Button("设置", systemImage: "gearshape") { showSettings = true }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }.accessibilityLabel("更多")
            }
            .padding(.horizontal, 12)
            Rectangle().fill(Ink.hairline).frame(height: 0.5).padding(.horizontal, 20)
            EditorControls(model: model, panelHeight: panelHeight, onOpenFrames: { showFrames = true },
                           onEditIdentity: { showSignature = true })
        }
        .foregroundStyle(Ink.ivory)
        .background(Ink.void)
        .buttonStyle(.plain)
    }

    private var shareItem: Binding<ShareItem?> {
        Binding(get: { model.shareURL.map(ShareItem.init(url:)) },
                set: { model.shareURL = $0?.url })
    }
}

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var credits = ""
    @State private var creditsFailed = false

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "版本 \(short)（\(build)）"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    masthead

                    creditCard(
                        title: "光谱模型与剖面",
                        body: "spektrafilm，Andrea Volpato。代码 GPL-3.0 或更高版本。剖面、LUT 与直接衍生数据 CC BY-SA 4.0。"
                    )
                    creditCard(
                        title: "引擎",
                        body: "SpektraLab，Hanze Qiu。本应用链接的 C++ / Metal 引擎，GPL-3.0 或更高版本。SpektraLab 与 spektrafilm 没有从属或背书关系。"
                    )
                    creditCard(
                        title: "黑白剖面",
                        body: "Tri-X、T-Max、Neopan Acros II、HP5 Plus、Multigrade 与 CineStill 800T 别名是 SpektraLab 自己的数据。胶片和相纸名字是商标，只用来标明剖面依据的公开资料。"
                    )
                    creditCard(
                        title: "相框",
                        body: "36 款参数化相框随应用离线内置。边框按照片短边比例绘制，不拉伸固定矢量。frame_code 只是设计编号；胶片名用当前选择，不编造拍摄参数。"
                    )
                    creditCard(
                        title: "metal-cpp",
                        body: "Copyright Apple Inc.，Apache License 2.0。"
                    )

                    VStack(alignment: .leading, spacing: 14) {
                        Link("隐私政策", destination: URL(string: "https://www.superaitest.com/litefilm/privacy.html")!)
                        Link("使用帮助与技术支持", destination: URL(string: "https://www.superaitest.com/litefilm/#support")!)
                        Link("开源代码", destination: URL(string: "https://github.com/kveinjay-google/LiteFilm")!)
                    }
                    .foregroundStyle(Ink.amber)

                    creditsBlock
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Ink.void)
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Ink.amber)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .task {
            guard let url = Bundle.main.url(forResource: "CREDITS", withExtension: "txt", subdirectory: "Licenses") else {
                creditsFailed = true
                return
            }
            if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                credits = text
                for name in ["NotoSans-OFL", "NotoSerif-OFL", "LXGWWenKai-OFL"] {
                    if let file = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Licenses"),
                       let license = try? String(contentsOf: file, encoding: .utf8) {
                        credits += "\n\n" + name + "\n" + license
                    }
                }
            } else {
                creditsFailed = true
            }
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                BrandMark(size: 64)
                Text("LiteFilm")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Ink.ivory)
            }
            Text("暗房感的胶片成像 · powered by spektrafilm")
                .font(.system(.subheadline, design: .default))
                .foregroundStyle(Ink.amber)
            HStack(spacing: 8) {
                Text(versionLine)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Ink.mute)
                Text("·")
                    .foregroundStyle(Ink.mute.opacity(0.6))
                Text("离线本地渲染")
                    .font(.caption)
                    .foregroundStyle(Ink.mute)
            }
            .padding(.top, 2)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Ink.amber.opacity(0.85), Ink.amber.opacity(0.05), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1.5)
                .padding(.top, 8)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Ink.hairline, lineWidth: 1)
        }
    }

    private var creditsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(Ink.amber)
                    .frame(width: 3, height: 14)
                Text("许可全文")
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .tracking(1.2)
                    .foregroundStyle(Ink.ivory)
            }

            if !credits.isEmpty {
                Text(credits)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Ink.mute)
                    .textSelection(.enabled)
            } else if creditsFailed {
                Text("未能载入 CREDITS.txt。安装包里的 Licenses 目录可能缺失。")
                    .font(.caption)
                    .foregroundStyle(Ink.ember)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Ink.amber)
                    Text("正在载入许可说明…")
                        .font(.caption)
                        .foregroundStyle(Ink.mute)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Ink.hairline, lineWidth: 1)
        }
    }

    private func creditCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(Ink.amber.opacity(0.85))
                    .frame(width: 3, height: 12)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(Ink.mute)
            }
            Text(body)
                .font(.subheadline)
                .foregroundStyle(Ink.ivory.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Ink.hairline, lineWidth: 1)
        }
    }
}

private struct ShareItem: Identifiable {
    var url: URL
    var id: String { url.absoluteString }
}

private struct ActivityShare: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            let view = controller.view!
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

func logLine(_ text: String) {
    fputs(text + "\n", stdout)
    fflush(stdout)
    FrameLog.append(text)
}

enum FrameLog {
    private static let queue = DispatchQueue(label: "spektrafilm.framelog")

    static var url: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("spektrafilm-frames.log")
    }

    static func append(_ text: String) {
        queue.sync {
            guard let url else { return }
            let line = Data((text + "\n").utf8)
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            } else {
                try? line.write(to: url)
            }
        }
    }
}
