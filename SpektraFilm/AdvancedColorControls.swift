import SwiftUI
import CoreImage

/// Per-sheet executor: one bounded source and one render at a time, never a task per pixel.
private actor AdvancedColorPreviewRenderer {
    private var boundedSource: CGImage?

    func render(_ source: CGImage, settings: PhotoAdjustments) throws -> CGImage {
        try Task.checkCancellation()
        return try autoreleasepool {
            let input: CGImage
            if let boundedSource {
                input = boundedSource
            } else {
                let longest = max(source.width, source.height)
                if longest <= 1000 {
                    input = source
                } else {
                    let scale = 1000.0 / Double(longest)
                    let image = CIImage(cgImage: source).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    let extent = CGRect(x: 0, y: 0, width: max(1, floor(Double(source.width) * scale)),
                                        height: max(1, floor(Double(source.height) * scale)))
                    let context = CIContext(options: [.cacheIntermediates: false])
                    guard let resized = context.createCGImage(image, from: extent, format: .RGBA16,
                        colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!) else {
                        throw EngineError.message("无法生成调色预览。")
                    }
                    input = resized
                }
                boundedSource = input
            }
            try Task.checkCancellation()
            let result = try PhotoProcessor.apply(input, settings: settings)
            try Task.checkCancellation()
            return result
        }
    }
}

enum AdvancedColorSection {
    case curve, hsl
    var title: String { self == .curve ? "曲线" : "HSL 色彩" }
}

/// Edits remain local until Apply; Cancel never changes the active recipe.
struct AdvancedColorEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PhotoAdjustments
    @State private var selectedBand = 0
    @State private var renderer = AdvancedColorPreviewRenderer()
    @State private var rendered: CGImage?
    @State private var renderedSettings: PhotoAdjustments?
    @State private var previewError: String?
    private let source: CGImage?
    private let section: AdvancedColorSection
    private let onApply: (PhotoAdjustments) -> Void
    private static let bands = ["红", "黄", "绿", "青", "蓝", "洋红"]
    private static let colors: [Color] = [.red, .yellow, .green, .cyan, .blue, .purple]
    private static let anchors = ["黑场", "暗部", "中间调", "亮部", "白场"]

    init(image: UIImage, settings: PhotoAdjustments, section: AdvancedColorSection = .curve,
         onApply: @escaping (PhotoAdjustments) -> Void) {
        _draft = State(initialValue: settings.sanitized())
        self.onApply = onApply
        self.section = section
        source = image.cgImage
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                if proxy.size.width > proxy.size.height {
                    HStack(spacing: 12) {
                        preview.frame(maxWidth: .infinity, maxHeight: .infinity)
                        ScrollView { controls }
                            .frame(width: min(390, proxy.size.width * 0.45))
                    }.padding(.horizontal, 12)
                } else {
                    VStack(spacing: 0) {
                        preview.frame(height: min(320, max(150, proxy.size.height * 0.40)))
                            .padding(.horizontal, 12)
                        ScrollView { controls }
                    }
                }
            }
            .background(Ink.void)
            .foregroundStyle(Ink.ivory)
            .navigationTitle(section.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") { onApply(draft.sanitized()); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(renderedSettings != draft || previewError != nil)
                }
            }
        }
        .tint(Ink.amber)
        .preferredColorScheme(.dark)
        .task(id: draft) { await renderPreview() }
    }

    private var preview: some View {
        ZStack(alignment: .bottomTrailing) {
            if let rendered {
                Image(decorative: rendered, scale: 1).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("当前曲线和 HSL 调色预览")
            }
            if let previewError {
                Text(previewError).font(.callout).multilineTextAlignment(.center)
                    .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if renderedSettings != draft {
                ProgressView().tint(Ink.amber).padding(10)
                    .background(Ink.void.opacity(0.8), in: Circle()).padding(8)
                    .accessibilityLabel("正在更新调色预览")
            }
        }
    }

    @MainActor
    private func renderPreview() async {
        let requested = draft
        do {
            // Debounce before actor entry, so rapid gestures do not queue expensive work.
            try await Task.sleep(nanoseconds: 60_000_000)
            try Task.checkCancellation()
            guard let source else { throw EngineError.message("照片预览不可用，请重新打开照片。") }
            let result = try await renderer.render(source, settings: requested)
            try Task.checkCancellation()
            guard draft == requested else { return }
            rendered = result
            renderedSettings = requested
            previewError = nil
        } catch is CancellationError {
            // A newer draft owns the next update, or the sheet has been dismissed.
        } catch {
            guard !Task.isCancelled, draft == requested else { return }
            previewError = error.localizedDescription
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 24) {
            if section == .curve {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("主曲线").font(.headline)
                        Spacer()
                        Button("重置曲线") { draft.curve = ToneCurve() }
                            .font(.subheadline).frame(minHeight: 44)
                    }
                    curveGraph
                        .frame(height: 220)
                    Text("上下拖动控制点。相邻点保持明暗顺序。")
                        .font(.caption).foregroundStyle(Ink.mute)
                    ForEach(0..<5, id: \.self) { index in
                        valueSlider(Self.anchors[index], value: curveBinding(index), range: 0...1, signed: false)
                    }
                }
            }
            if section == .hsl {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("HSL 色彩").font(.headline)
                        Spacer()
                        Button("重置色彩") { draft.hsl = HSLBand.defaults }
                            .font(.subheadline).frame(minHeight: 44)
                    }
                    ViewThatFits(in: .horizontal) {
                        bandButtons
                        ScrollView(.horizontal, showsIndicators: false) { bandButtons }
                    }
                    valueSlider("色相", value: bandBinding(\.hue), range: -1...1)
                    valueSlider("饱和度", value: bandBinding(\.saturation), range: -1...1)
                    valueSlider("明度", value: bandBinding(\.luminance), range: -1...1)
                    Text("色相最多偏移 30°，相邻色段自然过渡。")
                        .font(.caption).foregroundStyle(Ink.mute)
                }
            }
        }
        .padding(20)
    }

    private var bandButtons: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                Button { selectedBand = index } label: {
                    VStack(spacing: 8) {
                        Circle().fill(Self.colors[index]).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(.white.opacity(selectedBand == index ? 1 : 0), lineWidth: 2).padding(-4))
                        Text(Self.bands[index]).font(.caption)
                    }
                    .frame(minWidth: 44, minHeight: 62)
                }
                .foregroundStyle(selectedBand == index ? Ink.ivory : Ink.mute)
                .accessibilityLabel("\(Self.bands[index])色通道")
                .accessibilityAddTraits(selectedBand == index ? [.isSelected] : [])
            }
        }
    }

    private var curveGraph: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 18
            let width = max(1, proxy.size.width - inset * 2)
            let height = max(1, proxy.size.height - inset * 2)
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Ink.hairline)
                Path { path in
                    for i in 0...4 {
                        let fraction = CGFloat(i) / 4
                        path.move(to: CGPoint(x: inset + width * fraction, y: inset))
                        path.addLine(to: CGPoint(x: inset + width * fraction, y: inset + height))
                        path.move(to: CGPoint(x: inset, y: inset + height * fraction))
                        path.addLine(to: CGPoint(x: inset + width, y: inset + height * fraction))
                    }
                }.stroke(Ink.mute.opacity(0.2), lineWidth: 1)
                Path { path in
                    path.move(to: CGPoint(x: inset, y: inset + height))
                    path.addLine(to: CGPoint(x: inset + width, y: inset))
                }.stroke(Ink.mute.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                Path { path in
                    for index in 0..<5 {
                        let point = CGPoint(x: inset + width * CGFloat(index) / 4,
                                            y: inset + height * (1 - draft.curve.points[index]))
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }.stroke(Ink.amber, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                ForEach(0..<5, id: \.self) { index in
                    Circle().fill(Ink.ivory).frame(width: 14, height: 14)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                        .position(x: inset + width * CGFloat(index) / 4,
                                  y: inset + height * (1 - draft.curve.points[index]))
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("toneCurve"))
                            .onChanged { gesture in
                                setAnchor(index, 1 - (gesture.location.y - inset) / height)
                            })
                        .accessibilityHidden(true)
                }
            }.coordinateSpace(name: "toneCurve")
        }
    }

    private func setAnchor(_ index: Int, _ value: Double) {
        let lower = index == 0 ? 0 : draft.curve.points[index - 1]
        let upper = index == 4 ? 1 : draft.curve.points[index + 1]
        draft.curve.points[index] = min(upper, max(lower, value))
    }

    private func curveBinding(_ index: Int) -> Binding<Double> {
        Binding(get: { draft.curve.points[index] }, set: { setAnchor(index, $0) })
    }

    private func bandBinding(_ keyPath: WritableKeyPath<HSLBand, Double>) -> Binding<Double> {
        Binding(get: { draft.hsl[selectedBand][keyPath: keyPath] },
                set: { draft.hsl[selectedBand][keyPath: keyPath] = $0 })
    }

    private func valueSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, signed: Bool = true) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(String(format: signed ? "%+.0f" : "%.0f", value.wrappedValue * 100))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(Ink.amber)
            }
            Slider(value: value, in: range, step: 0.01)
                .accessibilityLabel(signed ? "\(Self.bands[selectedBand])色\(title)" : "曲线\(title)")
                .accessibilityValue("\(Int((value.wrappedValue * 100).rounded()))")
        }
    }
}
