import SwiftUI
import UIKit

/// The proof is composed by the same frame/watermark painter as the editor.
struct ObsidianExportSheet: View {
    @ObservedObject var model: LabModel
    @Environment(\.dismiss) private var dismiss
    @State private var format: ExportFormat = .jpeg
    @State private var proof: UIImage?
    @State private var request: ExportRequest?
    @AppStorage("litefilm.export.limitEnabled") private var limitEnabled = false
    @AppStorage("litefilm.export.limitKB") private var limitKB = "500"
    @FocusState private var limitFocused: Bool

    private var maxBytes: Int? { limitEnabled ? ExportSizeLimit.bytes(fromKB: limitKB) : nil }
    private var invalidLimit: Bool { limitEnabled && maxBytes == nil }

    private struct ExportRequest {
        let format: ExportFormat
        let frame: Bool
        let watermark: Bool
        let maxBytes: Int?
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("完成这一张。")
                            .font(.system(size: 30, weight: .semibold))
                        Text("确认画面，再带走你的作品。")
                            .font(.subheadline)
                            .foregroundStyle(Ink.mute)
                    }
                    if let proof {
                        Image(uiImage: proof)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 390)
                            .accessibilityLabel("导出预览，包含当前选择的相框和水印")
                    } else {
                        VStack(spacing: 12) {
                            ProgressView().tint(Ink.amber)
                            Text("正在准备预览")
                                .font(.subheadline)
                                .foregroundStyle(Ink.mute)
                        }
                        .frame(maxWidth: .infinity, minHeight: 220)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        ObsidianSectionLabel(title: "文件格式")
                        HStack(spacing: 8) {
                            ForEach(ExportFormat.allCases) { item in
                                Button {
                                    format = item
                                } label: {
                                    Text(item.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                        .foregroundStyle(format == item ? Ink.void : Ink.ivory)
                                        .background(format == item ? Ink.amber : Ink.surface, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(format == item ? .isSelected : [])
                            }
                        }
                    }
                    sizeLimitControls
                    VStack(spacing: 0) {
                        Toggle(isOn: frameBinding) {
                            optionLabel("携带相框", detail: model.frame.enabled ? model.frameBadge : "当前未使用相框")
                        }
                        .disabled(!model.frame.enabled)
                        .padding(.vertical, 16)
                        Divider().overlay(Ink.hairline)
                        Toggle(isOn: watermarkBinding) {
                            optionLabel("携带水印", detail: model.watermark.enabled ? model.watermarkBadge : "当前未使用水印")
                        }
                        .disabled(!model.watermark.enabled)
                        .padding(.vertical, 16)
                    }
                    .tint(Ink.amber)
                    Text("预览中的操作界面不会写入照片。导出完成后，可在系统分享菜单保存或分享。")
                        .font(.footnote)
                        .foregroundStyle(Ink.mute)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .background(Ink.void)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    guard !invalidLimit else { return }
                    limitFocused = false
                    request = ExportRequest(format: format, frame: model.exportIncludeFrame,
                                            watermark: model.exportIncludeWatermark, maxBytes: maxBytes)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up")
                        Text(model.busy ? "正在处理照片…" : "导出 \(format.title)")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(Ink.void)
                    .background(Ink.amber, in: RoundedRectangle(cornerRadius: 15))
                    .opacity(model.busy || proof == nil || invalidLimit ? 0.45 : 1)
                }
                .buttonStyle(.plain)
                .disabled(model.busy || proof == nil || request != nil || invalidLimit)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Ink.void)
            }
            .navigationTitle("导出作品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.foregroundStyle(Ink.mute)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { limitFocused = false }
                }
            }
            .toolbarBackground(Ink.void, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .foregroundStyle(Ink.ivory)
        .tint(Ink.amber)
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: refreshProof)
        .onChange(of: model.exportIncludeFrame) { _, _ in refreshProof() }
        .onChange(of: model.exportIncludeWatermark) { _, _ in refreshProof() }
        .onReceive(model.$preview) { _ in refreshProof() }
        .onDisappear {
            // Begin only after this sheet has left, allowing the parent share sheet to present.
            guard let pending = request else { return }
            request = nil
            model.export(pending.format, includeFrame: pending.frame,
                         includeWatermark: pending.watermark, maxBytes: pending.maxBytes)
        }
    }

    private var sizeLimitControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("限制文件大小", isOn: $limitEnabled)
                .font(.system(size: 16, weight: .medium))
            if limitEnabled {
                HStack(spacing: 12) {
                    Text("不超过").foregroundStyle(Ink.mute)
                    TextField("例如 500", text: $limitKB)
                        .keyboardType(.numberPad)
                        .focused($limitFocused)
                        .multilineTextAlignment(.trailing)
                        .font(.body.monospacedDigit())
                        .padding(12)
                        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("文件大小上限，单位 KB")
                    Text("KB")
                }
                HStack(spacing: 10) {
                    ForEach([100, 500, 1000], id: \.self) { kb in
                        Button("\(kb) KB") { limitKB = String(kb); limitFocused = false }
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 8))
                    }
                }.buttonStyle(.plain)
                Text(invalidLimit ? "请输入 1–1,000,000 之间的整数。" :
                     (format == .png ? "PNG 会按需缩小尺寸，保留透明区域。1 KB = 1,000 字节。" :
                      "优先压缩画质，必要时缩小尺寸。上限越小，清晰度越低。1 KB = 1,000 字节。"))
                    .font(.footnote)
                    .foregroundStyle(invalidLimit ? Ink.ember : Ink.mute)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.tint(Ink.amber)
    }

    private func refreshProof() {
        proof = model.proofStill(includeFrame: model.exportIncludeFrame, includeWatermark: model.exportIncludeWatermark).map { UIImage(cgImage: $0) }
    }

    private func optionLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 16, weight: .medium))
            Text(detail).font(.footnote).foregroundStyle(Ink.mute)
        }
    }

    private var frameBinding: Binding<Bool> {
        Binding(get: { model.exportIncludeFrame }, set: { model.setExportIncludeFrame($0) })
    }

    private var watermarkBinding: Binding<Bool> {
        Binding(get: { model.exportIncludeWatermark }, set: { model.setExportIncludeWatermark($0) })
    }
}

struct ObsidianSettingsSheet: View {
    @ObservedObject var model: LabModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAbout = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("你的创作习惯。")
                            .font(.system(size: 30, weight: .semibold))
                        Text("署名、浏览方式，以及关于 LiteFilm 的一切。")
                            .font(.subheadline)
                            .foregroundStyle(Ink.mute)
                    }
                    settingsGroup("个人署名") {
                        NavigationLink {
                            ObsidianSignaturePage(model: model)
                        } label: {
                            ObsidianSettingsRow(icon: "signature", title: "署名与水印", detail: model.watermark.displayName.isEmpty ? "设置姓名、品牌和版权信息" : model.watermark.displayName)
                        }
                    }
                    settingsGroup("浏览体验") {
                        NavigationLink {
                            ObsidianTransitionPage(model: model)
                        } label: {
                            ObsidianSettingsRow(icon: "rectangle.on.rectangle", title: "切换效果", detail: model.previewTransition.title)
                        }
                    }
                    if reduceMotion {
                        Text("系统已开启「减少动态效果」，预览将直接切换；你的效果偏好仍会保留。")
                            .font(.footnote)
                            .foregroundStyle(Ink.mute)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    settingsGroup("帮助与信息") {
                        VStack(spacing: 0) {
                            Link(destination: URL(string: "https://www.superaitest.com/litefilm/#support")!) {
                                ObsidianSettingsRow(icon: "questionmark.circle", title: "使用帮助", external: true)
                            }
                            groupDivider
                            Link(destination: URL(string: "mailto:kveinjay@gmail.com")!) {
                                ObsidianSettingsRow(icon: "envelope", title: "联系开发者", external: true)
                            }
                            groupDivider
                            Link(destination: URL(string: "https://www.superaitest.com/litefilm/privacy.html")!) {
                                ObsidianSettingsRow(icon: "hand.raised", title: "隐私政策", external: true)
                            }
                            groupDivider
                            Button { showAbout = true } label: {
                                ObsidianSettingsRow(icon: "info.circle", title: "关于与开源许可")
                            }
                            groupDivider
                            Link(destination: URL(string: "https://github.com/kveinjay-google/LiteFilm")!) {
                                ObsidianSettingsRow(icon: "chevron.left.forwardslash.chevron.right", title: "源代码", external: true)
                            }
                        }
                    }
                    VStack(spacing: 7) {
                        Text("LiteFilm").font(.system(size: 19, weight: .semibold))
                        Text(versionLine).font(.caption).foregroundStyle(Ink.mute)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
            .background(Ink.void)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.fontWeight(.semibold)
                }
            }
            .toolbarBackground(Ink.void, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .foregroundStyle(Ink.ivory)
        .tint(Ink.amber)
        .buttonStyle(.plain)
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showAbout) { AboutSheet() }
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        return "版本 \(info?["CFBundleShortVersionString"] as? String ?? "—") · \(info?["CFBundleVersion"] as? String ?? "—")"
    }

    private var groupDivider: some View {
        Divider().overlay(Ink.hairline).padding(.leading, 52)
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ObsidianSectionLabel(title: title)
            content()
                .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct ObsidianSignatureSheet: View {
    @ObservedObject var model: LabModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ObsidianSignaturePage(model: model)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
        }
        .foregroundStyle(Ink.ivory).tint(Ink.amber)
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct ObsidianSignaturePage: View {
    @ObservedObject var model: LabModel
    @State private var displayName = ""
    @State private var studioName = ""
    @State private var copyrightLine = ""
    @State private var monogram = ""
    @State private var siteURL = ""
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("让作品留下你的名字。")
                    .font(.system(size: 25, weight: .semibold))
                Text("内容自动保存。不同水印样式会使用对应字段；留空时使用默认署名。")
                    .font(.subheadline)
                    .foregroundStyle(Ink.mute)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 24) {
                    field("署名姓名", prompt: "LiteFilm", text: $displayName)
                    field("工作室 / 品牌", prompt: "LITEFILM", text: $studioName)
                    field("版权行", prompt: "© 工作室 年份", text: $copyrightLine)
                    field("花押字母", prompt: "1–2 字，留空自动生成", text: $monogram)
                    field("短网址", prompt: "superaitest.com/litefilm", text: $siteURL, keyboard: .URL)
                }
                Divider().overlay(Ink.hairline)
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        model.resetWatermarkOffset()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("复位水印位置")
                            Spacer()
                            if offsetIsDefault {
                                Text("默认位置").font(.footnote).foregroundStyle(Ink.mute)
                            }
                        }
                        .font(.system(size: 15, weight: .medium))
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Ink.amber)
                    .disabled(offsetIsDefault)
                    Text("在编辑预览中长按水印即可拖动，松手保存。水印位于照片内，不会覆盖外框。")
                        .font(.footnote)
                        .foregroundStyle(Ink.mute)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Ink.void)
        .navigationTitle("署名与水印")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            displayName = model.watermark.displayName
            studioName = model.watermark.studioName
            copyrightLine = model.watermark.copyrightLine
            monogram = model.watermark.monogram
            siteURL = model.watermark.siteURL
            loaded = true
        }
        .onChange(of: displayName) { _, value in if loaded { model.updateWatermarkContent(displayName: value) } }
        .onChange(of: studioName) { _, value in if loaded { model.updateWatermarkContent(studioName: value) } }
        .onChange(of: copyrightLine) { _, value in if loaded { model.updateWatermarkContent(copyrightLine: value) } }
        .onChange(of: siteURL) { _, value in if loaded { model.updateWatermarkContent(siteURL: value) } }
        .onChange(of: monogram) { _, value in
            guard loaded else { return }
            let clipped = String(value.filter { !$0.isWhitespace }.prefix(2))
            if monogram != clipped { monogram = clipped }
            model.updateWatermarkContent(monogram: clipped)
        }
    }

    private var offsetIsDefault: Bool {
        model.watermark.offsetX == 0 && model.watermark.offsetY == 0
    }

    private func field(_ title: String, prompt: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ObsidianSectionLabel(title: title)
            TextField(prompt, text: text)
                .font(.system(size: 16))
                .foregroundStyle(Ink.ivory)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .padding(16)
                .background(Ink.surface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(title)
        }
    }
}

private struct ObsidianTransitionPage: View {
    @ObservedObject var model: LabModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("选择照片之间的节奏。")
                    .font(.system(size: 25, weight: .semibold))
                VStack(spacing: 0) {
                    ForEach(PreviewTransition.settingsOrder, id: \.self) { item in
                        Button {
                            model.setPreviewTransition(item)
                        } label: {
                            HStack(spacing: 18) {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(item.title + (item == .dissolve ? " · 默认" : ""))
                                        .font(.system(size: 16, weight: .medium))
                                    Text(item.detail)
                                        .font(.footnote)
                                        .foregroundStyle(Ink.mute)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: model.previewTransition == item ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 21))
                                    .foregroundStyle(model.previewTransition == item ? Ink.amber : Ink.mute)
                            }
                            .padding(18)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.previewTransition == item ? .isSelected : [])
                        if item != PreviewTransition.settingsOrder.last {
                            Divider().overlay(Ink.hairline).padding(.horizontal, 18)
                        }
                    }
                }
                .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16))
                Text("相框和水印使用同一切换效果。翻页无法播放时使用渐隐渐显。动画仅用于预览，不会写入导出文件。")
                    .font(.footnote)
                    .foregroundStyle(Ink.mute)
                Text(reduceMotion ? "系统已开启「减少动态效果」，目前直接切换画面。所选偏好会保留。" : "开启系统「减少动态效果」后，预览会直接切换画面。")
                    .font(.footnote)
                    .foregroundStyle(reduceMotion ? Ink.amber : Ink.mute)
            }
            .padding(24)
        }
        .background(Ink.void)
        .navigationTitle("切换效果")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ObsidianSectionLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Ink.mute)
    }
}

private struct ObsidianSettingsRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var external = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Ink.amber)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 16, weight: .medium))
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(Ink.mute)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: external ? "arrow.up.right" : "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Ink.mute)
        }
        .foregroundStyle(Ink.ivory)
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }
}
