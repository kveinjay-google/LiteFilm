import SwiftUI

/// A single executor keeps Core Image preview work bounded while slider updates cancel stale requests.
private actor CropPreviewRenderer {
    static let shared = CropPreviewRenderer()

    func render(_ image: CGImage, geometry: PhotoGeometry) throws -> CGImage {
        try Task.checkCancellation()
        return try autoreleasepool {
            try PhotoProcessor.geometry(image, settings: geometry, includeCrop: false)
        }
    }
}

private enum CropRatio: String, CaseIterable {
    case free = "自由", original = "原始", square = "1:1", fourThree = "4:3", threeFour = "3:4"
    case threeTwo = "3:2", twoThree = "2:3", wide = "16:9", tall = "9:16"

    func aspect(original: Double) -> Double? {
        switch self {
        case .free: nil
        case .original: original
        case .square: 1
        case .fourThree: 4.0 / 3
        case .threeFour: 3.0 / 4
        case .threeTwo: 3.0 / 2
        case .twoThree: 2.0 / 3
        case .wide: 16.0 / 9
        case .tall: 9.0 / 16
        }
    }
}

private enum GeometryControl: String, CaseIterable {
    case angle = "拉直", vertical = "垂直透视", horizontal = "水平透视", distortion = "镜头"
    var keyPath: WritableKeyPath<PhotoGeometry, Double> {
        switch self {
        case .angle: \.angle
        case .vertical: \.vertical
        case .horizontal: \.horizontal
        case .distortion: \.distortion
        }
    }
}

struct CropEditor: View {
    @ObservedObject var model: LabModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PhotoGeometry
    @State private var ratio = CropRatio.free
    @State private var control = GeometryControl.angle
    @State private var rendered: CGImage?
    @State private var renderedGeometry: PhotoGeometry?
    @State private var error: String?
    private let source: CGImage?

    init(model: LabModel) {
        self.model = model
        source = model.editingSourcePreview?.cgImage
        _draft = State(initialValue: model.adjustments.geometry)
    }

    private var previewGeometry: PhotoGeometry {
        var geometry = draft
        geometry.crop = PhotoCrop()
        return geometry
    }

    private var previewReady: Bool { rendered != nil && renderedGeometry == previewGeometry }
    private var imageAspect: Double {
        guard let image = rendered ?? source else { return 1 }
        return Double(image.width) / Double(image.height)
    }
    private var lockedAspect: Double? {
        aspect(for: ratio)
    }
    private func aspect(for ratio: CropRatio) -> Double? {
        guard let source else { return ratio.aspect(original: 1) }
        let original = Double(source.width) / Double(source.height)
        return ratio.aspect(original: draft.rotation % 2 == 0 ? original : 1 / original)
    }
    private func supports(_ ratio: CropRatio) -> Bool {
        guard let aspect = aspect(for: ratio) else { return true }
        return (0.05...20).contains(aspect / imageAspect)
    }
    private var controlValue: Binding<Double> {
        Binding(get: { draft[keyPath: control.keyPath] },
                set: { draft[keyPath: control.keyPath] = $0 })
    }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            VStack(spacing: 0) {
                header
                if landscape {
                    HStack(spacing: 12) {
                        canvas
                        ScrollView { controls }.frame(width: min(320, geometry.size.width * 0.40))
                    }.padding(.horizontal, 12)
                } else {
                    canvas.padding(.horizontal, 16)
                    controls.padding(.bottom, 8)
                }
            }
        }
        .background(Ink.void.ignoresSafeArea())
        .foregroundStyle(Ink.ivory)
        .tint(Ink.amber)
        .buttonStyle(.plain)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .task(id: previewGeometry) { await renderPreview() }
    }

    private var header: some View {
        HStack {
            Button("取消") { dismiss() }.frame(minWidth: 58, minHeight: 44)
            Spacer()
            Text("裁剪与校正").font(.headline)
            Spacer()
            Button("完成") {
                model.applyGeometry(draft.sanitized())
                dismiss()
            }
            .fontWeight(.semibold).foregroundStyle(Ink.amber)
            .frame(minWidth: 58, minHeight: 44).disabled(!previewReady)
            .opacity(previewReady ? 1 : 0.4)
        }.padding(.horizontal, 12).padding(.bottom, 4)
    }

    private var canvas: some View {
        GeometryReader { proxy in
            let available = CGSize(width: max(1, proxy.size.width - 24), height: max(1, proxy.size.height - 24))
            let width = min(available.width, available.height * imageAspect)
            let size = CGSize(width: width, height: width / imageAspect)
            ZStack {
                if let image = rendered ?? source {
                    Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)
                    CropSelection(crop: $draft.crop, size: size,
                                  normalizedAspect: lockedAspect.map { $0 / imageAspect })
                        .frame(width: size.width, height: size.height)
                        .allowsHitTesting(previewReady)
                }
                if let error {
                    Text(error).font(.callout).multilineTextAlignment(.center)
                        .padding().background(Ink.surface, in: RoundedRectangle(cornerRadius: 8))
                } else if !previewReady {
                    ProgressView().tint(Ink.amber).padding(14)
                        .background(Ink.void.opacity(0.8), in: Circle())
                }
            }.frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(CropRatio.allCases, id: \.self) { item in
                        Button {
                            ratio = item
                            fitLockedCrop()
                        } label: {
                            Text(item.rawValue).font(.subheadline)
                                .foregroundStyle(ratio == item ? Ink.amber : Ink.mute)
                                .frame(minHeight: 44)
                        }
                        .disabled(!supports(item))
                        .opacity(supports(item) ? 1 : 0.35)
                        .accessibilityAddTraits(ratio == item ? [.isSelected] : [])
                        .accessibilityHint(supports(item) ? "锁定裁剪比例" : "照片过于狭长，无法使用此比例")
                    }
                }.padding(.horizontal, 20)
            }
            Rectangle().fill(Ink.hairline).frame(height: 0.5).padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(GeometryControl.allCases, id: \.self) { item in
                        Button { control = item } label: {
                            Text(item.rawValue).font(.subheadline)
                                .foregroundStyle(control == item ? Ink.amber : Ink.mute)
                                .frame(minHeight: 36)
                        }.accessibilityAddTraits(control == item ? [.isSelected] : [])
                    }
                }.padding(.horizontal, 20)
            }
            HStack {
                Text(control == .distortion ? "镜头畸变" : control.rawValue).font(.caption)
                Spacer()
                Text(control == .angle ? String(format: "%+.1f°", controlValue.wrappedValue)
                     : String(format: "%+.0f", controlValue.wrappedValue * 100))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(Ink.amber)
                Button {
                    controlValue.wrappedValue = 0
                } label: {
                    Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 36)
                }.accessibilityLabel("重置\(control.rawValue)")
                    .disabled(controlValue.wrappedValue == 0)
            }.padding(.leading, 20).padding(.trailing, 8)
            Slider(value: controlValue, in: control == .angle ? -45...45 : -1...1,
                   step: control == .angle ? 0.1 : 0.01)
                .accessibilityLabel(control == .distortion ? "镜头畸变" : control.rawValue)
                .padding(.horizontal, 20)
            HStack {
                Button {
                    draft.rotation = (draft.rotation + 1) % 4
                    // A turn starts from the whole new orientation, then reapplies the chosen ratio.
                    draft.crop = PhotoCrop()
                } label: {
                    Label("旋转 90°", systemImage: "rotate.right").frame(minHeight: 44)
                }
                Spacer()
                Button("全部复位") {
                    draft = PhotoGeometry()
                    ratio = .free
                }.frame(minHeight: 44)
            }.font(.subheadline).padding(.horizontal, 20)
        }
    }

    @MainActor private func renderPreview() async {
        let requested = previewGeometry
        guard let source else { error = "暂时无法读取照片，请返回后重试。"; return }
        do {
            try await Task.sleep(nanoseconds: 90_000_000)
            let image = try await CropPreviewRenderer.shared.render(source, geometry: requested)
            try Task.checkCancellation()
            guard previewGeometry == requested else { return }
            rendered = image
            renderedGeometry = requested
            error = nil
            fitLockedCrop()
        } catch is CancellationError {
            // Superseded slider work must never replace a newer preview.
        } catch {
            guard !Task.isCancelled, previewGeometry == requested else { return }
            self.error = "无法完成这次校正，请调整数值后重试。"
        }
    }

    private func fitLockedCrop() {
        guard let aspect = lockedAspect else { return }
        let normalized = aspect / imageAspect
        var crop = draft.crop
        let centerX = crop.x + crop.width / 2
        let centerY = crop.y + crop.height / 2
        let minimumWidth = max(0.05, 0.05 * normalized)
        let maximumWidth = min(1, normalized)
        guard minimumWidth <= maximumWidth else {
            // A quarter turn can make a previously valid ratio unavailable on a panorama.
            ratio = .free
            return
        }
        let width = min(maximumWidth, max(minimumWidth, min(crop.width, crop.height * normalized)))
        crop.width = width
        crop.height = width / normalized
        crop.x = min(1 - crop.width, max(0, centerX - crop.width / 2))
        crop.y = min(1 - crop.height, max(0, centerY - crop.height / 2))
        draft.crop = crop.sanitized()
    }
}

private struct CropSelection: View {
    @Binding var crop: PhotoCrop
    let size: CGSize
    let normalizedAspect: Double?
    @State private var dragStart: PhotoCrop?

    private var rect: CGRect {
        CGRect(x: crop.x * size.width, y: crop.y * size.height,
               width: crop.width * size.width, height: crop.height * size.height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(rect)
            }.fill(.black.opacity(0.58), style: FillStyle(eoFill: true)).allowsHitTesting(false)
            Rectangle().fill(.clear).contentShape(Rectangle())
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .gesture(moveGesture)
                .accessibilityLabel("移动裁剪区域")
                .accessibilityElement()
                .accessibilityAction(named: "向左") { nudge(x: -0.02, y: 0) }
                .accessibilityAction(named: "向右") { nudge(x: 0.02, y: 0) }
                .accessibilityAction(named: "向上") { nudge(x: 0, y: -0.02) }
                .accessibilityAction(named: "向下") { nudge(x: 0, y: 0.02) }
            Path { path in
                path.addRect(rect)
                for step in 1...2 {
                    let x = rect.minX + rect.width * CGFloat(step) / 3
                    let y = rect.minY + rect.height * CGFloat(step) / 3
                    path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x, y: rect.maxY))
                    path.move(to: CGPoint(x: rect.minX, y: y)); path.addLine(to: CGPoint(x: rect.maxX, y: y))
                }
            }.stroke(.white.opacity(0.75), lineWidth: 1).allowsHitTesting(false)
            ForEach(0..<4, id: \.self) { corner in
                cornerHandle(corner)
            }
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil { dragStart = crop }
                guard var moved = dragStart else { return }
                moved.x = min(1 - moved.width, max(0, moved.x + value.translation.width / size.width))
                moved.y = min(1 - moved.height, max(0, moved.y + value.translation.height / size.height))
                crop = moved.sanitized()
            }.onEnded { _ in dragStart = nil }
    }

    private func cornerHandle(_ corner: Int) -> some View {
        let left = corner % 2 == 0
        let top = corner < 2
        return ZStack {
            Color.clear
            Path { path in
                let x: CGFloat = left ? 20 : 24
                let y: CGFloat = top ? 20 : 24
                path.move(to: CGPoint(x: x, y: y + (top ? 16 : -16)))
                path.addLine(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + (left ? 16 : -16), y: y))
            }.stroke(Ink.amber, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .frame(width: 44, height: 44).contentShape(Rectangle())
        .position(x: left ? rect.minX : rect.maxX, y: top ? rect.minY : rect.maxY)
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            if dragStart == nil { dragStart = crop }
            guard let start = dragStart else { return }
            resize(corner: corner, start: start, translation: value.translation)
        }.onEnded { _ in dragStart = nil })
        .accessibilityLabel("\(top ? "上" : "下")\(left ? "左" : "右")裁剪角")
        .accessibilityElement()
        .accessibilityAdjustableAction { direction in
            let factor: Double = direction == .increment ? 0.02 : -0.02
            resize(corner: corner, start: crop,
                   translation: CGSize(width: (left ? -factor : factor) * size.width,
                                       height: (top ? -factor : factor) * size.height))
        }
    }

    private func resize(corner: Int, start: PhotoCrop, translation: CGSize) {
        let left = corner % 2 == 0
        let top = corner < 2
        let anchorX = left ? start.x + start.width : start.x
        let anchorY = top ? start.y + start.height : start.y
        let maxWidth = left ? anchorX : 1 - anchorX
        let maxHeight = top ? anchorY : 1 - anchorY
        let minimum = 0.05
        var width = max(minimum, start.width + (left ? -1 : 1) * translation.width / size.width)
        var height = max(minimum, start.height + (top ? -1 : 1) * translation.height / size.height)
        if let ratio = normalizedAspect {
            // Use the dominant drag axis and clamp both dimensions together to preserve the ratio.
            if abs(translation.width / size.width) >= abs(translation.height / size.height) * ratio {
                height = width / ratio
            } else { width = height * ratio }
            let minimumWidth = max(minimum, minimum * ratio)
            let maximumWidth = min(maxWidth, maxHeight * ratio)
            guard maximumWidth >= minimumWidth else { return }
            width = min(maximumWidth, max(minimumWidth, width))
            height = width / ratio
        } else {
            width = min(maxWidth, width); height = min(maxHeight, height)
        }
        var result = start
        result.width = width; result.height = height
        result.x = left ? anchorX - width : anchorX
        result.y = top ? anchorY - height : anchorY
        crop = result.sanitized()
    }

    private func nudge(x: Double, y: Double) {
        crop.x = min(1 - crop.width, max(0, crop.x + x))
        crop.y = min(1 - crop.height, max(0, crop.y + y))
    }
}
