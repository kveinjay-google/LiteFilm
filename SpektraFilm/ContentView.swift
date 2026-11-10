import PhotosUI
import SwiftUI

struct ContentView: View {
    @StateObject private var model = LabModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showAbout = false
    @State private var showSettings = false
    @State private var showFrames = false
    @State private var showExport = false
    @State private var fullscreen = false
    @Environment(\.undoManager) private var undoManager

    private var filmEntries: [WheelEntry] {
        WheelEntry.make([
            ("彩色负片", model.catalog.colorNegatives),
            ("反转片", model.catalog.slides),
            ("黑白", model.catalog.blackAndWhiteFilms),
        ])
    }

    private var paperEntries: [WheelEntry] {
        WheelEntry.make([
            ("彩色相纸", model.catalog.colorPapers),
            ("黑白相纸", model.catalog.blackAndWhitePapers),
        ])
    }

    var body: some View {
        ZStack {
            Ink.void.ignoresSafeArea()
            switch model.stage {
            case .home:
                HomeColorChartView(model: model, pickerItem: $pickerItem) {
                    model.openGallery()
                }
            case .gallery:
                ImportGalleryView(model: model, pickerItem: $pickerItem)
            case .editor:
                if fullscreen {
                    fullscreenLab
                } else {
                    editor
                }
            }

            if let notice = model.noticeText {
                VStack {
                    Text(notice)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundStyle(Ink.ivory)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Color.black.opacity(0.72),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(Ink.amber.opacity(0.55), lineWidth: 1))
                        .padding(.top, 10)
                        .padding(.horizontal, 24)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.42, dampingFraction: 0.86), value: model.noticeText)
                .allowsHitTesting(false)
                .zIndex(20)
            }
        }
        .statusBarHidden(fullscreen && model.stage == .editor)
        .animation(.spring(response: 0.46, dampingFraction: 0.86), value: fullscreen)
        .animation(.easeInOut(duration: 0.28), value: model.stage)
        .task {
            if CommandLine.arguments.contains("--self-test") {
                let code = await Task.detached(priority: .userInitiated) {
                    SelfTest.run()
                }.value
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
        .onChange(of: undoManager) { _, manager in
            model.undoManager = manager
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                await model.load(item: item)
                pickerItem = nil
            }
        }
        .onChange(of: model.stage) { _, stage in
            if stage != .editor { fullscreen = false }
        }
        .sheet(isPresented: $showAbout) {
            AboutSheet()
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(model: model)
        }
        .sheet(isPresented: $showFrames) {
            FrameGallerySheet(model: model)
        }
        .sheet(isPresented: $showExport) {
            ExportOptionsSheet(model: model)
        }
        .sheet(item: shareItem) { item in
            ActivityShare(url: item.url)
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            header(fullscreen: false)
            PrintViewport(model: model) { showFrames = true }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let errorText = model.errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(Ink.ember)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
            dock
        }
    }

    private var fullscreenLab: some View {
        VStack(spacing: 0) {
            header(fullscreen: true)
            PrintViewport(model: model) { showFrames = true }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let errorText = model.errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(Ink.ember)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }
            dock
        }
        .background(Ink.void)
    }

    private func header(fullscreen: Bool) -> some View {
        HStack(spacing: 6) {
            if fullscreen {
                iconButton("chevron.down", label: "退出全屏") { setFullscreen(false) }
            } else {
                iconButton("house", label: "首页") { model.openHome() }
            }

            Spacer(minLength: 8)

            Text(fullscreen ? (model.catalog.film(model.filmID)?.name ?? "LiteFilm") : "LiteFilm")
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundStyle(Ink.mute)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsHitTesting(false)

            Spacer(minLength: 8)

            exportButton
            iconButton("gearshape", label: "设置") { showSettings = true }
            overflowMenu(fullscreen: fullscreen)
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 2)
    }

    private func overflowMenu(fullscreen: Bool) -> some View {
        Menu {
            Section {
                Button {
                    model.openGallery()
                } label: {
                    Label("画廊", systemImage: "square.grid.2x2")
                }
                PhotosPicker(
                    selection: $pickerItem,
                    matching: PhotoImport.pickerFilter,
                    preferredItemEncoding: PhotoImport.preferredEncoding
                ) {
                    Label("选照片", systemImage: "photo")
                }
                Button {
                    Task { await model.showSample() }
                } label: {
                    Label("色卡样张", systemImage: "rectangle.split.3x1")
                }
                .disabled(model.busy)
            }

            Section {
                Button {
                    model.undo()
                } label: {
                    Label("撤销", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo)

                Button {
                    model.saveCurrentLookToGallery()
                } label: {
                    Label("保存方案", systemImage: "bookmark")
                }
                .disabled(model.preview == nil || model.busy)

                Button {
                    showFrames = true
                } label: {
                    Label("画幅与比例", systemImage: "aspectratio")
                }

                Toggle(isOn: watermarkEnabledBinding) {
                    Label("水印", systemImage: "signature")
                }
            }

            Section {
                Button {
                    setFullscreen(!fullscreen)
                } label: {
                    Label(
                        fullscreen ? "退出全屏" : "全屏预览",
                        systemImage: fullscreen
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right"
                    )
                }
                .disabled(model.preview == nil && !fullscreen)

                Button {
                    showAbout = true
                } label: {
                    Label("关于", systemImage: "info.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Ink.ivory)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay(Circle().stroke(Ink.hairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("更多")
    }

    private var watermarkEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.watermark.enabled },
            set: { model.setWatermarkEnabled($0) }
        )
    }

    private var dock: some View {
        VStack(spacing: 4) {
            wheelPair
            exposureControl
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .background(dockBackground)
    }

    private var wheelPair: some View {
        HStack(alignment: .top, spacing: 8) {
            DenseWheel(
                title: "胶片",
                entries: filmEntries,
                selectedID: model.filmID,
                space: "film-wheel"
            ) { id in
                model.previewFilm(id)
            }
            DenseWheel(
                title: "相纸",
                entries: paperEntries,
                selectedID: model.paperID,
                space: "paper-wheel"
            ) { id in
                model.previewPaper(id)
            }
        }
    }

    private var exposureControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.min")
                .font(.caption)
                .foregroundStyle(Ink.mute)
            Text("曝光")
                .font(.caption2)
                .foregroundStyle(Ink.mute)
            Slider(value: exposureBinding, in: -2...2, step: 0.1)
                .tint(Ink.amber)
            Button {
                model.setExposure(0)
            } label: {
                Text(String(format: "%+.1f EV", model.exposureEV))
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(model.exposureEV == 0 ? Ink.ivory : Ink.amber)
                    .frame(minWidth: 64, minHeight: 44, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("曝光补偿，点按回到零")
        }
    }

    private var exportButton: some View {
        Button {
            showExport = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.12, green: 0.09, blue: 0.06))
                .frame(width: 44, height: 44)
                .background(Ink.amber, in: Circle())
                .overlay(Circle().stroke(Ink.amber.opacity(0.35), lineWidth: 1))
                .contentShape(Circle())
        }
        .disabled(model.preview == nil || model.busy)
        .opacity((model.preview == nil || model.busy) ? 0.4 : 1)
        .accessibilityLabel("导出")
        .buttonStyle(.plain)
    }

    private func iconButton(_ system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Ink.ivory)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay(Circle().stroke(Ink.hairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var dockBackground: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(Color.black.opacity(0.42))
            Rectangle()
                .fill(Ink.hairline)
                .frame(height: 1)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var exposureBinding: Binding<Double> {
        Binding(
            get: { model.exposureEV },
            set: { model.setExposure($0) }
        )
    }

    private var shareItem: Binding<ShareItem?> {
        Binding(
            get: { model.shareURL.map(ShareItem.init(url:)) },
            set: { model.shareURL = $0?.url }
        )
    }

    private func setFullscreen(_ on: Bool) {
        withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) {
            fullscreen = on
        }
    }
}

private struct WheelEntry: Identifiable {
    var stock: Stock
    var section: String
    var startsSection: Bool
    var id: String { stock.id }

    static func make(_ groups: [(String, [Stock])]) -> [WheelEntry] {
        groups.flatMap { name, stocks in
            stocks.enumerated().map { index, stock in
                WheelEntry(stock: stock, section: name, startsSection: index == 0)
            }
        }
    }
}

private struct DenseWheel: View {
    let title: String
    let entries: [WheelEntry]
    let selectedID: String
    let space: String
    var onPreview: (String) -> Void

    @State private var position: String?
    @State private var tick = 0
    @State private var adjusting = false

    /// One full row, with a sliver of the neighbors. The whole window is the swipe target.
    /// 44pt row, 8pt peek each side, 96pt window — about twice the old 22 / 46 pair.
    private let rowHeight: CGFloat = 44
    private let peek: CGFloat = 8
    private var wheelHeight: CGFloat { 96 }
    private var openingInset: CGFloat { (wheelHeight - rowHeight - peek * 2) / 2 }

    var body: some View {
        ZStack {
            scroll
                .mask {
                    Rectangle().padding(.vertical, openingInset)
                }
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Ink.amber.opacity(0.16))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Ink.amber.opacity(0.9), lineWidth: 1.5)
                }
                .frame(height: rowHeight)
                .padding(.horizontal, 4)
                .allowsHitTesting(false)
        }
        .frame(height: wheelHeight)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Ink.hairline, lineWidth: 1)
        }
        .sensoryFeedback(.selection, trigger: tick)
    }

    private var scroll: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    row(entry)
                        .frame(height: rowHeight)
                        .id(entry.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: $position, anchor: .center)
        .contentMargins(.vertical, (wheelHeight - rowHeight) / 2, for: .scrollContent)
        .coordinateSpace(name: space)
        .task(id: entries.count) {
            guard !entries.isEmpty else { return }
            let target = entries.contains(where: { $0.id == selectedID }) ? selectedID : entries[0].id
            if position != target {
                position = target
            }
        }
        .onChange(of: selectedID) { _, id in
            guard entries.contains(where: { $0.id == id }), position != id else { return }
            adjusting = true
            withAnimation(.snappy(duration: 0.38)) {
                position = id
            }
        }
        .onChange(of: position) { old, id in
            guard let id else { return }
            if adjusting {
                if id == selectedID { adjusting = false }
                return
            }
            guard let old, old != id, entries.contains(where: { $0.id == id }) else { return }
            tick &+= 1
            guard id != selectedID else { return }
            onPreview(id)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(centered?.stock.name ?? "")
        .accessibilityAdjustableAction { direction in
            nudge(direction)
        }
    }

    private func row(_ entry: WheelEntry) -> some View {
        ZStack {
            if entry.startsSection, entry.id != entries.first?.id {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Ink.amber.opacity(0.55))
                        .frame(height: 1)
                    Spacer(minLength: 0)
                }
            }
            Text(entry.stock.name)
                .font(.system(size: 21, weight: .medium, design: .serif))
                .foregroundStyle(Ink.ivory)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var centered: WheelEntry? {
        let id = position ?? selectedID
        return entries.first { $0.id == id }
    }

    private func nudge(_ direction: AccessibilityAdjustmentDirection) {
        guard let current = entries.firstIndex(where: { $0.id == (position ?? selectedID) }) else { return }
        let next = direction == .increment ? current + 1 : current - 1
        guard entries.indices.contains(next) else { return }
        let id = entries[next].id
        withAnimation(.snappy(duration: 0.2)) {
            position = id
        }
    }
}

private struct ExportOptionsSheet: View {
    @ObservedObject var model: LabModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Toggle(isOn: frameBinding) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("携带当前相框")
                            .font(.system(.body, design: .serif))
                        Text(frameCaption)
                            .font(.caption)
                            .foregroundStyle(Ink.mute)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Ink.amber)

                Toggle(isOn: watermarkBinding) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("携带水印")
                            .font(.system(.body, design: .serif))
                        Text(watermarkCaption)
                            .font(.caption)
                            .foregroundStyle(Ink.mute)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Ink.amber)
                .disabled(!model.watermark.enabled)

                Text("文件里只有照片、相框和水印。预览上的名称徽标不会写进去。")
                    .font(.caption)
                    .foregroundStyle(Ink.mute)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    ForEach(ExportFormat.allCases) { format in
                        Button {
                            let includeFrame = model.exportIncludeFrame
                            let includeWatermark = model.exportIncludeWatermark
                            dismiss()
                            model.export(format, includeFrame: includeFrame, includeWatermark: includeWatermark)
                        } label: {
                            Text(format.title)
                                .font(.system(.body, design: .serif))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(Color(red: 0.12, green: 0.09, blue: 0.06))
                                .background(Ink.amber, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Ink.void)
            .navigationTitle("导出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Ink.ivory)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var frameCaption: String {
        if model.frame.enabled {
            return "关闭后只保留处理后的照片。当前是\(model.frameBadge)。"
        }
        return "当前是无框，打开这一项也不会另加相框。"
    }

    private var watermarkCaption: String {
        if model.watermark.enabled {
            return "当前是\(model.watermarkBadge)。关闭后文件不带这层字。"
        }
        return "预览里还没有选中水印。上下滑动可以选。"
    }

    private var frameBinding: Binding<Bool> {
        Binding(get: { model.exportIncludeFrame }, set: { model.setExportIncludeFrame($0) })
    }

    private var watermarkBinding: Binding<Bool> {
        Binding(get: { model.exportIncludeWatermark }, set: { model.setExportIncludeWatermark($0) })
    }
}

enum Ink {
    static let void = Color(red: 0.055, green: 0.050, blue: 0.045)
    static let ivory = Color(red: 0.96, green: 0.93, blue: 0.88)
    static let mute = Color(red: 0.64, green: 0.58, blue: 0.50)
    static let amber = Color(red: 0.79, green: 0.54, blue: 0.29)
    static let ember = Color(red: 0.86, green: 0.42, blue: 0.32)
    static let hairline = Color.white.opacity(0.10)
}

private struct SettingsSheet: View {
    @ObservedObject var model: LabModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayName: String = ""
    @State private var studioName: String = ""
    @State private var copyrightLine: String = ""
    @State private var monogram: String = ""
    @State private var siteURL: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sectionCard(title: "水印", subtitle: "署名会印在照片开窗里，不会压到卡纸或外框。长按预览上的水印可拖动，松手自动保存。") {
                        VStack(alignment: .leading, spacing: 14) {
                            field(title: "署名姓名", text: $displayName, prompt: "空则 Spektra", onCommit: {
                                model.updateWatermarkContent(displayName: displayName)
                            })
                            hairline
                            field(title: "工作室 / 品牌", text: $studioName, prompt: "空则 SPEKTRA", onCommit: {
                                model.updateWatermarkContent(studioName: studioName)
                            })
                            hairline
                            field(title: "版权行", text: $copyrightLine, prompt: "空则 © 工作室 年份", onCommit: {
                                model.updateWatermarkContent(copyrightLine: copyrightLine)
                            })
                            hairline
                            field(title: "花押字母", text: $monogram, prompt: "1–2 字，空则自动", onCommit: {
                                let clipped = String(monogram.filter { !$0.isWhitespace }.prefix(2))
                                monogram = clipped
                                model.updateWatermarkContent(monogram: clipped)
                            })
                            hairline
                            field(title: "短网址", text: $siteURL, prompt: "空则 SPEKTRA.FILM", onCommit: {
                                model.updateWatermarkContent(siteURL: siteURL)
                            })
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        Button {
                            model.resetWatermarkOffset()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Ink.amber)
                                Text("复位水印位置")
                                    .font(.system(.body, design: .serif))
                                Spacer()
                                Text(offsetCaption)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Ink.mute)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .foregroundStyle(Ink.ivory)
                            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Ink.hairline, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(model.watermark.offsetX == 0 && model.watermark.offsetY == 0)
                        .opacity((model.watermark.offsetX == 0 && model.watermark.offsetY == 0) ? 0.45 : 1)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }

                    sectionCard(title: "切换", subtitle: nil) {
                        VStack(spacing: 10) {
                            ForEach(PreviewTransition.settingsOrder, id: \.self) { item in
                                row(item)
                            }
                        }
                        .padding(12)

                        Text(note)
                            .font(.caption)
                            .foregroundStyle(Ink.mute)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Ink.void)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Ink.amber)
                }
            }
            .onAppear(perform: loadWatermarkFields)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(height: 1)
            .padding(.leading, 2)
    }

    private func sectionCard<Content: View>(title: String, subtitle: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(Ink.amber)
                    .frame(width: 3, height: 14)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .tracking(1.4)
                    .foregroundStyle(Ink.ivory)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, subtitle == nil ? 10 : 6)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Ink.mute)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Ink.hairline, lineWidth: 1)
        }
    }

    private var offsetCaption: String {
        let x = model.watermark.offsetX
        let y = model.watermark.offsetY
        if abs(x) < 0.0005 && abs(y) < 0.0005 { return "默认" }
        return String(format: "x %.2f  y %.2f", x, y)
    }

    private var note: String {
        var text = "左右换相框、上下换水印用同一种效果。拖动时画面不挪位置，只是略微变淡。卷页只有上下两个方向，左右换成沿书脊翻转；翻页播不出来时退回渐隐。导出的文件不播放这些动画。"
        if reduceMotion {
            text += " 正在减少动态效果，切换会直接变化。"
        }
        return text
    }

    private func loadWatermarkFields() {
        displayName = model.watermark.displayName
        studioName = model.watermark.studioName
        copyrightLine = model.watermark.copyrightLine
        monogram = model.watermark.monogram
        siteURL = model.watermark.siteURL
    }

    private func field(
        title: String,
        text: Binding<String>,
        prompt: String,
        onCommit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .tracking(0.9)
                .foregroundStyle(Ink.mute)
            TextField(prompt, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .serif))
                .foregroundStyle(Ink.ivory)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Ink.hairline, lineWidth: 1)
                }
                .onSubmit(onCommit)
                .onChange(of: text.wrappedValue) { _, _ in
                    onCommit()
                }
        }
    }

    private func row(_ item: PreviewTransition) -> some View {
        let selected = model.previewTransition == item
        return Button {
            model.setPreviewTransition(item)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.system(.body, design: .serif))
                        if item == .dissolve {
                            Text("默认")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color(red: 0.12, green: 0.09, blue: 0.06))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Ink.amber, in: Capsule())
                        }
                    }
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(Ink.mute)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? Ink.amber : Ink.mute)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Ink.ivory)
            .background(
                Color.white.opacity(selected ? 0.08 : 0.03),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? Ink.amber.opacity(0.9) : Ink.hairline, lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item == .dissolve ? "\(item.title)，默认" : item.title)
        .accessibilityHint(item.detail)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct AboutSheet: View {
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
            } else {
                creditsFailed = true
            }
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LiteFilm")
                .font(.system(size: 36, weight: .medium, design: .serif))
                .foregroundStyle(Ink.ivory)
            Text("暗房感的胶片成像 · powered by spektrafilm")
                .font(.system(.subheadline, design: .serif))
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
                    .font(.system(size: 13, weight: .semibold, design: .serif))
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
