import SwiftUI

struct PhotoTextPanel: View {
    @ObservedObject var model: LabModel
    @State private var editing: PhotoTextLayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("照片文字").font(.headline)
                Spacer()
                Button { editing = PhotoTextLayer(text: "写下这一刻") } label: {
                    Label("添加文字", systemImage: "plus")
                }.foregroundStyle(Ink.amber)
                .disabled(model.textLayers.count >= 8 || model.preview == nil || model.busy)
            }
            if model.textLayers.isEmpty {
                Text("给照片留一句话。字体、颜色和位置，都由你决定。")
                    .font(.subheadline).foregroundStyle(Ink.mute).padding(.top, 12)
            }
            ForEach(model.textLayers) { layer in
                HStack {
                    Button { editing = layer } label: {
                        HStack {
                            Image(systemName: "text.badge.plus")
                            Text(layer.text.replacingOccurrences(of: "\n", with: " ")).lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }.frame(minHeight: 40).contentShape(Rectangle())
                    }.disabled(model.busy)
                    Button(role: .destructive) { model.setTextLayers(model.textLayers.filter { $0.id != layer.id }) } label: {
                        Image(systemName: "trash").frame(width: 44, height: 44)
                    }.accessibilityLabel("删除文字：\(layer.text)")
                }.foregroundStyle(Ink.ivory)
            }
            if model.textLayers.count >= 8 {
                Text("最多添加 8 段文字").font(.caption).foregroundStyle(Ink.mute)
            }
        }
        .padding(.horizontal, 20)
        .sheet(item: $editing) { layer in
            PhotoTextEditor(model: model, layer: layer)
        }
    }
}

struct PhotoTextEditor: View {
    @ObservedObject var model: LabModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PhotoTextLayer
    @State private var dragOrigin: CGPoint?
    @State private var surface: PhotoTextSurface?
    @FocusState private var typing: Bool

    init(model: LabModel, layer: PhotoTextLayer) {
        self.model = model
        _draft = State(initialValue: layer)
    }
    private var layers: [PhotoTextLayer] {
        if model.textLayers.contains(where: { $0.id == draft.id }) {
            return model.textLayers.map { $0.id == draft.id ? draft : $0 }
        }
        return model.textLayers + [draft]
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    preview
                        .frame(height: 270)
                    HStack {
                        Text("拖动图片上的文字，调整位置").font(.caption).foregroundStyle(Ink.mute)
                        Spacer()
                        Button("居中") { draft.x = 0.5; draft.y = 0.5 }.font(.caption)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("内容"); Spacer(); Text("\(draft.text.count)/200").foregroundStyle(Ink.mute) }.font(.caption)
                        TextField("输入文字，可换行", text: $draft.text, axis: .vertical)
                            .lineLimit(2...5).padding(12)
                            .background(Ink.hairline, in: RoundedRectangle(cornerRadius: 12))
                            .focused($typing)
                            .onChange(of: draft.text) { _, text in
                                if text.count > 200 { draft.text = String(text.prefix(200)) }
                            }
                    }
                    HStack(spacing: 10) {
                        ForEach(PhotoTextFont.allCases) { face in
                            Button { draft.fontID = face.rawValue } label: {
                                VStack(spacing: 8) {
                                    Text("光影").font(Font(face.font(27)))
                                    Text(face.title).font(.caption)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(draft.fontID == face.rawValue ? Ink.amber.opacity(0.15) : Ink.hairline, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(draft.fontID == face.rawValue ? Ink.amber : .clear))
                            }
                            .foregroundStyle(draft.fontID == face.rawValue ? Ink.amber : Ink.ivory)
                            .accessibilityAddTraits(draft.fontID == face.rawValue ? [.isSelected] : [])
                        }
                    }
                    HStack {
                        Text("字号").font(.subheadline)
                        Slider(value: $draft.size, in: 0.025...0.20).accessibilityLabel("文字大小")
                        Text("\(Int(draft.size * 1000))").monospacedDigit().font(.caption).frame(width: 30)
                    }
                    HStack {
                        ForEach(PhotoTextLayer.colors, id: \.self) { key in
                            Button { draft.color = key } label: {
                                Circle().fill(Color(uiColor: PhotoTextLayer.ink(key)))
                                    .frame(width: 29, height: 29)
                                    .padding(5)
                                    .overlay(Circle().stroke(draft.color == key ? Ink.amber : .clear, lineWidth: 2))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .accessibilityLabel(PhotoTextLayer.colorTitle(key))
                            .accessibilityAddTraits(draft.color == key ? [.isSelected] : [])
                        }
                    }
                    Picker("对齐方式", selection: $draft.alignment) {
                        Label("左对齐", systemImage: "text.alignleft").tag("left")
                        Label("居中", systemImage: "text.aligncenter").tag("center")
                        Label("右对齐", systemImage: "text.alignright").tag("right")
                    }.pickerStyle(.segmented)
                    Toggle("文字阴影", isOn: $draft.shadow)
                    DisclosureGroup("精确位置") {
                        HStack { Text("水平"); Slider(value: $draft.x, in: 0...1).accessibilityLabel("文字水平位置") }
                        HStack { Text("垂直"); Slider(value: $draft.y, in: 0...1).accessibilityLabel("文字垂直位置") }
                    }.font(.subheadline)
                    Text("3 款内置字体均采用 SIL OFL 许可，可免费商用。完整许可见「关于」。")
                        .font(.caption).foregroundStyle(Ink.mute)
                }.padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Ink.void)
            .navigationTitle("文字").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { model.setTextLayers(layers); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("收起键盘") { typing = false } }
            }
        }
        .tint(Ink.amber).preferredColorScheme(.dark)
        .presentationDetents([.large])
        .interactiveDismissDisabled()
        .task { if surface == nil { surface = model.makeTextEditingSurface() } }
    }
    private var preview: some View {
        GeometryReader { geometry in
            if let surface, let cg = surface.render(layers) {
                let size = CGSize(width: cg.width, height: cg.height)
                let scale = min(geometry.size.width / size.width, geometry.size.height / size.height)
                let shown = CGSize(width: size.width * scale, height: size.height * scale)
                let area = surface.area
                let rect = PhotoTextPainter.layout(draft, in: area).rect
                ZStack(alignment: .topLeading) {
                    Image(uiImage: UIImage(cgImage: cg)).resizable().frame(width: shown.width, height: shown.height)
                    Rectangle().stroke(Ink.amber.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(width: max(1, rect.width * scale), height: max(1, rect.height * scale))
                        .offset(x: rect.minX * scale, y: rect.minY * scale)
                }
                .frame(width: shown.width, height: shown.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        typing = false
                        if dragOrigin == nil { dragOrigin = CGPoint(x: draft.x, y: draft.y) }
                        guard let origin = dragOrigin else { return }
                        draft.x = min(1, max(0, origin.x + value.translation.width / (area.width * scale)))
                        draft.y = min(1, max(0, origin.y + value.translation.height / (area.height * scale)))
                    }
                    .onEnded { _ in dragOrigin = nil })
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .accessibilityLabel("文字位置预览，可使用下方精确位置滑块调整")
            }
        }
    }
}
