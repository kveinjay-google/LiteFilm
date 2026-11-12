import SwiftUI

private enum AdjustmentTool: String, CaseIterable, Identifiable {
    case crop = "裁剪", light = "光线", color = "色彩", curve = "曲线", hsl = "HSL", local = "局部", repair = "修复"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .crop: "crop.rotate"
        case .light: "sun.max"
        case .color: "circle.lefthalf.filled"
        case .curve: "point.topleft.down.to.point.bottomright.curvepath"
        case .hsl: "slider.horizontal.3"
        case .local: "paintbrush.pointed"
        case .repair: "bandage"
        }
    }
}

private enum ToneControl: String, CaseIterable {
    case exposure = "曝光", highlights = "高光", shadows = "阴影", whites = "白场", blacks = "黑场", contrast = "对比度"
    case temperature = "色温", tint = "色调", saturation = "饱和度"

    static let light: [Self] = [.exposure, .highlights, .shadows, .whites, .blacks, .contrast]
    static let color: [Self] = [.temperature, .tint, .saturation]

    var keyPath: WritableKeyPath<PhotoAdjustments, Double>? {
        switch self {
        case .temperature: \.temperature
        case .tint: \.tint
        case .blacks: \.blacks
        case .whites: \.whites
        case .exposure: nil
        case .highlights: \.highlights
        case .shadows: \.shadows
        case .contrast: \.contrast
        case .saturation: \.saturation
        }
    }
}

struct AdjustmentControls: View {
    @ObservedObject var model: LabModel
    @State private var group = AdjustmentTool.light
    @State private var lightControl = ToneControl.exposure
    @State private var colorControl = ToneControl.temperature
    @State private var destination: AdjustmentTool?
    @State private var opening: AdjustmentTool?

    private var selected: ToneControl { group == .color ? colorControl : lightControl }
    private var controls: [ToneControl] { group == .color ? ToneControl.color : ToneControl.light }
    private var value: Binding<Double> {
        // Capture the parameter so a late slider event cannot edit the next group.
        let control = selected
        return Binding(get: {
            if let keyPath = control.keyPath { return model.adjustments[keyPath: keyPath] }
            return model.exposureEV
        }, set: { newValue in
            if let keyPath = control.keyPath { model.setAdjustment(keyPath, newValue) }
            else { model.setExposure(newValue) }
        })
    }

    var body: some View {
        VStack(spacing: 6) {
            toolRail
            Rectangle().fill(Ink.hairline).frame(height: 0.5).padding(.horizontal, 20)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(controls, id: \.self) { control in
                            Button {
                                model.finishPendingEdits()
                                if group == .color { colorControl = control } else { lightControl = control }
                            } label: {
                                Text(control.rawValue)
                                    .font(.subheadline.weight(selected == control ? .semibold : .regular))
                                    .foregroundStyle(selected == control ? Ink.ivory : Ink.mute)
                                    .padding(.horizontal, 12).frame(minHeight: 44)
                                    .background(selected == control ? Ink.surface : .clear,
                                                in: RoundedRectangle(cornerRadius: 10))
                            }
                            .id(control)
                            .accessibilityAddTraits(selected == control ? [.isSelected] : [])
                            .accessibilityIdentifier("adjust.parameter.\(control.rawValue)")
                        }
                    }.padding(.horizontal, 16)
                }
                .onChange(of: group) { _, _ in proxy.scrollTo(selected, anchor: .center) }
            }
            VStack(spacing: 2) {
                HStack(alignment: .center) {
                    Text(selected.rawValue).font(.subheadline).foregroundStyle(Ink.mute)
                    Spacer()
                    Text(selected == .exposure
                         ? String(format: "%+.1f EV", value.wrappedValue)
                         : String(format: "%+.0f", value.wrappedValue * 100))
                        .font(.system(.title3, design: .monospaced).weight(.medium))
                        .foregroundStyle(Ink.amber).contentTransition(.numericText())
                    Button { value.wrappedValue = 0 } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 44, height: 44)
                    }
                    .foregroundStyle(Ink.mute)
                    .disabled(abs(value.wrappedValue) < 0.0001)
                    .accessibilityLabel("重置\(selected.rawValue)")
                }
                Slider(value: value, in: selected == .exposure ? -2...2 : -1...1,
                       step: selected == .exposure ? 0.1 : 0.01)
                    .tint(Ink.amber).accessibilityLabel(selected.rawValue)
                    .id(selected)
            }.padding(.horizontal, 20)
        }
        .foregroundStyle(Ink.ivory)
        .fullScreenCover(item: $destination) { tool in
            switch tool {
            case .curve, .hsl:
                if let image = model.globalEditingPreview {
                    AdvancedColorEditor(image: image, settings: model.adjustments,
                        section: tool == .curve ? .curve : .hsl, onApply: model.applyAdjustments)
                }
            case .local, .repair:
                if let image = model.retouchBasePreview {
                    RetouchEditor(image: image, edits: model.adjustments.retouch,
                        initialTool: tool == .repair ? .repair : .radial, onApply: model.applyRetouch)
                }
            default: EmptyView()
            }
        }
    }

    private var toolRail: some View {
        GeometryReader { geometry in
            let width = max(48, (geometry.size.width - 32) / CGFloat(AdjustmentTool.allCases.count))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(AdjustmentTool.allCases) { tool in
                        let active = (opening ?? destination ?? (model.showCropEditor ? .crop : group)) == tool
                        Button { open(tool) } label: {
                            VStack(spacing: 7) {
                                Image(systemName: tool.symbol)
                                    .font(.system(size: 19, weight: active ? .semibold : .regular))
                                    .frame(height: 22)
                                Text(tool.rawValue).font(.caption.weight(active ? .semibold : .medium))
                            }
                            .foregroundStyle(active ? Ink.amber : Ink.mute)
                            .frame(width: width, height: 58)
                            .background {
                                if active {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Ink.amber.opacity(0.09)).padding(.horizontal, 3)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .disabled(unavailable(tool) || opening != nil)
                        .accessibilityAddTraits(active ? [.isSelected] : [])
                        .accessibilityLabel(tool.rawValue)
                        .accessibilityIdentifier("adjust.tool.\(tool.rawValue)")
                    }
                }.padding(.horizontal, 16)
            }
        }.frame(height: 58)
    }

    private func unavailable(_ tool: AdjustmentTool) -> Bool {
        switch tool {
        case .light, .color: false
        case .crop: model.editingSourcePreview == nil || model.busy
        case .curve, .hsl: model.globalEditingPreview == nil || model.busy
        case .local, .repair: model.retouchBasePreview == nil || model.busy
        }
    }

    private func open(_ tool: AdjustmentTool) {
        model.finishPendingEdits()
        if tool == .light || tool == .color {
            group = tool
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }
        opening = tool
        Task { @MainActor in
            defer { opening = nil }
            await model.waitUntilSettled()
            guard !model.busy, model.errorText == nil else { return }
            if tool == .crop { model.showCropEditor = true }
            else { destination = tool }
        }
    }
}
