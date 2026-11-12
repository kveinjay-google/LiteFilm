import SwiftUI
import CoreImage

/// Serialized off-main rendering prevents rapid strokes from launching concurrent image jobs.
private actor RetouchPreviewRenderer {
    private var source: CGImage?
    private let context = CIContext(options: [.cacheIntermediates: false])
    func render(_ original: CGImage, edits: RetouchEdits) throws -> CGImage {
        try Task.checkCancellation()
        if source == nil {
            let scale = min(1, 1400 / Double(max(original.width, original.height)))
            if scale < 1 {
                let small = CIImage(cgImage: original).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                let bounds = CGRect(x: 0, y: 0, width: max(1, floor(small.extent.width)), height: max(1, floor(small.extent.height)))
                source = context.createCGImage(small, from: bounds)
            } else { source = original }
        }
        guard let source else { throw EngineError.message("无法创建局部编辑预览。") }
        return try PhotoRetouchProcessor.apply(source, edits: edits)
    }
}

struct RetouchEditor: View {
    let image: UIImage
    let onApply: (RetouchEdits) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RetouchEdits
    @State private var tool: RetouchKind = .radial
    @State private var radius = 0.12
    @State private var feather = 0.6
    @State private var exposure = 0.5
    @State private var saturation = 0.0
    @State private var selectedID: UUID?
    @State private var strokeID: UUID?
    @State private var source: RetouchPoint?
    @State private var choosingSource = false
    @State private var undoStack: [RetouchEdits] = []
    @State private var rendered: CGImage?
    @State private var errorText: String?
    @State private var rendering = false
    @State private var showOverlay = true
    @State private var renderer = RetouchPreviewRenderer()

    init(image: UIImage, edits: RetouchEdits, onApply: @escaping (RetouchEdits) -> Void) {
        self.image = image; self.onApply = onApply
        _draft = State(initialValue: edits.sanitized())
    }

    private var selected: RetouchLayer? { draft.layers.first { $0.id == selectedID } }
    private var hint: String {
        switch tool {
        case .linear: "从亮端拖向原图端，设置渐变范围"
        case .radial: "点按放置圆心；拖动设置半径"
        case .brush: "在照片上涂抹，局部改变曝光和饱和度"
        case .repair: choosingSource || source == nil ? "先点按干净区域作为取样源" : "涂抹要修复的区域；每笔保持源点偏移"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(RetouchKind.allCases) { kind in
                        Button {
                            tool = kind; selectedID = nil
                            choosingSource = kind == .repair && source == nil
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: kind.symbol)
                                Text(kind.title).font(.caption)
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(tool == kind ? Ink.amber.opacity(0.18) : Ink.hairline, in: RoundedRectangle(cornerRadius: 10))
                        }.foregroundStyle(tool == kind ? Ink.amber : Ink.ivory)
                    }
                }.padding(.horizontal, 16)
                preview.frame(maxHeight: .infinity)
                HStack {
                    Text(hint).font(.caption).foregroundStyle(Ink.mute).frame(maxWidth: .infinity, alignment: .leading)
                    if rendering { ProgressView().controlSize(.small).accessibilityLabel("正在更新预览") }
                }.padding(.horizontal, 16)
                ScrollView {
                    VStack(spacing: 13) {
                        HStack {
                            Toggle("显示蒙版轮廓", isOn: $showOverlay).font(.caption)
                            if tool == .repair {
                                Button(choosingSource ? "正在选源点" : "重选源点") { choosingSource = true; selectedID = nil }
                                    .font(.caption).buttonStyle(.bordered)
                            }
                        }
                        if tool != .linear {
                            control("大小", value: parameter(\.radius, fallback: $radius), range: 0.005...0.5, format: "%")
                            control("羽化", value: parameter(\.feather, fallback: $feather), range: 0...1, format: "%")
                        }
                        if tool != .repair {
                            control("曝光", value: parameter(\.exposure, fallback: $exposure), range: -2...2, format: "EV")
                            control("饱和度", value: parameter(\.saturation, fallback: $saturation), range: -1...1, format: "%")
                        } else {
                            Text("将源区域像素柔和覆盖到目标，适合灰尘、小瑕疵和简单背景；复杂纹理可能需要重选源点。")
                                .font(.caption).foregroundStyle(Ink.mute).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let selected, !selected.points.isEmpty {
                            DisclosureGroup("移动所选区域") {
                                control("水平", value: position(\.x), range: 0...1, format: "%")
                                control("垂直", value: position(\.y), range: 0...1, format: "%")
                            }.font(.caption)
                        }
                        HStack {
                            Text("图层 \(draft.layers.count)/\(RetouchEdits.maximumLayers)").font(.caption).foregroundStyle(Ink.mute)
                            Spacer()
                            Button("撤销") {
                                if let previous = undoStack.popLast() { draft = previous; selectedID = nil }
                            }.disabled(undoStack.isEmpty)
                            Button("清空", role: .destructive) { remember(); draft = RetouchEdits(); selectedID = nil }
                                .disabled(draft.isEmpty)
                        }.font(.caption)
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(Array(draft.layers.enumerated()), id: \.element.id) { index, layer in
                                    HStack(spacing: 8) {
                                        Button {
                                            selectedID = layer.id; tool = layer.kind
                                            radius = layer.radius; feather = layer.feather
                                            exposure = layer.exposure; saturation = layer.saturation
                                            if layer.kind == .repair { source = layer.source }
                                        } label: {
                                            Label("\(index + 1) · \(layer.kind.title)", systemImage: layer.kind.symbol)
                                        }
                                        Button(role: .destructive) {
                                            remember(); draft.layers.removeAll { $0.id == layer.id }
                                            if selectedID == layer.id { selectedID = nil }
                                        } label: { Image(systemName: "xmark.circle.fill") }
                                            .accessibilityLabel("删除第 \(index + 1) 个\(layer.kind.title)图层")
                                    }.font(.caption).padding(10)
                                        .background(selectedID == layer.id ? Ink.amber.opacity(0.18) : Ink.hairline, in: Capsule())
                                }
                            }
                        }
                        if let errorText { Text(errorText).font(.caption).foregroundStyle(.red) }
                    }.padding(.horizontal, 16).padding(.bottom, 8)
                }.frame(maxHeight: 285)
            }
            .padding(.top, 8).background(Ink.void)
            .navigationTitle("局部调整与修复").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") { onApply(draft.sanitized()); dismiss() }
                        .fontWeight(.semibold).disabled(strokeID != nil || errorText != nil)
                }
            }
        }
        .tint(Ink.amber).preferredColorScheme(.dark).interactiveDismissDisabled()
        .task(id: draft) {
            rendering = true
            do {
                try await Task.sleep(nanoseconds: 90_000_000)
                guard let cg = image.cgImage else { throw EngineError.message("照片预览不可用。") }
                let result = try await renderer.render(cg, edits: draft)
                try Task.checkCancellation()
                rendered = result; errorText = nil; rendering = false
            } catch is CancellationError { /* A newer recipe owns the next result. */ }
            catch { if !Task.isCancelled { errorText = error.localizedDescription; rendering = false } }
        }
    }

    private var preview: some View {
        GeometryReader { geometry in
            let sourceSize = CGSize(width: image.cgImage?.width ?? 1, height: image.cgImage?.height ?? 1)
            let scale = min(geometry.size.width / sourceSize.width, geometry.size.height / sourceSize.height)
            let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            ZStack {
                Image(uiImage: rendered.map { UIImage(cgImage: $0) } ?? image).resizable()
                if showOverlay {
                    Canvas { context, canvasSize in
                        for layer in draft.layers {
                            draw(layer, context: &context, size: canvasSize, active: layer.id == selectedID)
                        }
                        if tool == .repair, let source {
                            let point = CGPoint(x: source.x * canvasSize.width, y: source.y * canvasSize.height)
                            var cross = Path()
                            cross.move(to: CGPoint(x: point.x - 10, y: point.y)); cross.addLine(to: CGPoint(x: point.x + 10, y: point.y))
                            cross.move(to: CGPoint(x: point.x, y: point.y - 10)); cross.addLine(to: CGPoint(x: point.x, y: point.y + 10))
                            context.stroke(cross, with: .color(.cyan), lineWidth: 2)
                        }
                    }.allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height).clipped().contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in stroke(value, size: size) }
                .onEnded { _ in
                    if choosingSource { choosingSource = false }
                    strokeID = nil
                })
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .accessibilityLabel("照片局部编辑画布。\(hint)")
        }
    }

    private func remember() {
        undoStack.append(draft)
        if undoStack.count > 30 { undoStack.removeFirst(undoStack.count - 30) }
    }

    private func parameter(_ key: WritableKeyPath<RetouchLayer, Double>, fallback: Binding<Double>) -> Binding<Double> {
        Binding(get: { selected?[keyPath: key] ?? fallback.wrappedValue }, set: { value in
            fallback.wrappedValue = value
            if let index = draft.layers.firstIndex(where: { $0.id == selectedID }) { draft.layers[index][keyPath: key] = value }
        })
    }

    private func position(_ key: WritableKeyPath<RetouchPoint, Double>) -> Binding<Double> {
        Binding(get: { selected?.points.first?[keyPath: key] ?? 0.5 }, set: { value in
            guard let index = draft.layers.firstIndex(where: { $0.id == selectedID }), let first = draft.layers[index].points.first else { return }
            let coordinates = draft.layers[index].points.map { $0[keyPath: key] }
            let delta = min(1 - (coordinates.max() ?? 1), max(-(coordinates.min() ?? 0), value - first[keyPath: key]))
            draft.layers[index].points = draft.layers[index].points.map { point in
                var moved = point; moved[keyPath: key] += delta; return moved
            }
        })
    }

    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        HStack {
            Text(title).font(.caption).frame(width: 44, alignment: .leading)
            Slider(value: value, in: range, onEditingChanged: { editing in if editing { remember() } })
                .accessibilityLabel(title)
            Text(format == "EV" ? String(format: "%+.1f", value.wrappedValue) : "\(Int(value.wrappedValue * 100))%")
                .font(.caption.monospacedDigit()).frame(width: 44, alignment: .trailing)
        }
    }

    private func stroke(_ value: DragGesture.Value, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        func point(_ location: CGPoint) -> RetouchPoint {
            RetouchPoint(x: Double(location.x / size.width), y: Double(location.y / size.height)).sanitized()
        }
        let current = point(value.location), start = point(value.startLocation)
        if tool == .repair && (choosingSource || source == nil) {
            source = current; choosingSource = true; return
        }
        if strokeID == nil {
            guard draft.layers.count < RetouchEdits.maximumLayers else {
                errorText = "最多 24 个图层，请先删除不需要的图层。"; return
            }
            remember()
            var layer = RetouchLayer(kind: tool)
            layer.points = tool == .linear ? [start, current] : [start]
            layer.radius = radius; layer.feather = feather; layer.exposure = exposure; layer.saturation = saturation
            layer.source = tool == .repair ? source : nil
            draft.layers.append(layer); strokeID = layer.id; selectedID = layer.id
        }
        guard let index = draft.layers.firstIndex(where: { $0.id == strokeID }) else { return }
        switch tool {
        case .linear: draft.layers[index].points = [start, current]
        case .radial:
            let distance = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
            if distance > 4 { draft.layers[index].radius = min(0.5, max(0.005, distance / min(size.width, size.height))) }
        case .brush, .repair:
            guard let last = draft.layers[index].points.last else { return }
            if hypot(current.x - last.x, current.y - last.y) > 0.002,
               draft.layers[index].points.count < RetouchEdits.maximumPoints { draft.layers[index].points.append(current) }
        }
    }

    private func draw(_ layer: RetouchLayer, context: inout GraphicsContext, size: CGSize, active: Bool) {
        guard let start = layer.points.first else { return }
        let points = layer.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        let color: Color = layer.kind == .repair ? .cyan : Ink.amber
        var path = Path()
        if layer.kind == .radial {
            let radius = layer.radius * min(size.width, size.height)
            path.addEllipse(in: CGRect(x: points[0].x - radius, y: points[0].y - radius, width: radius * 2, height: radius * 2))
        } else {
            path.move(to: points[0]); for point in points.dropFirst() { path.addLine(to: point) }
            if layer.kind == .brush || layer.kind == .repair {
                let width = layer.radius * min(size.width, size.height) * 2
                if points.count == 1 {
                    path.addEllipse(in: CGRect(x: points[0].x - width / 2, y: points[0].y - width / 2, width: width, height: width))
                    context.fill(path, with: .color(color.opacity(active ? 0.13 : 0.06)))
                } else {
                    context.stroke(path, with: .color(color.opacity(active ? 0.13 : 0.06)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                }
            }
        }
        context.stroke(path, with: .color(color.opacity(active ? 1 : 0.45)), style: StrokeStyle(lineWidth: active ? 2 : 1, dash: [5, 4]))
        let center = CGPoint(x: start.x * size.width, y: start.y * size.height)
        context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(color))
        if layer.kind == .repair, let source = layer.source {
            var link = Path(); link.move(to: center)
            link.addLine(to: CGPoint(x: source.x * size.width, y: source.y * size.height))
            context.stroke(link, with: .color(.cyan.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }
}
