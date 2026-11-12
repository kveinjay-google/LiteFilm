import SwiftUI

private enum ToneControl: String, CaseIterable {
    case exposure = "曝光", temperature = "色温", tint = "色调", highlights = "高光", shadows = "阴影"
    case blacks = "黑场", whites = "白场", contrast = "对比度", saturation = "饱和度"

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
    @State private var selected = ToneControl.exposure
    @State private var advanced = false
    @State private var retouch = false

    private var value: Binding<Double> {
        Binding(get: {
            if let keyPath = selected.keyPath { return model.adjustments[keyPath: keyPath] }
            return model.exposureEV
        }, set: { newValue in
            if let keyPath = selected.keyPath { model.setAdjustment(keyPath, newValue) }
            else { model.setExposure(newValue) }
        })
    }

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    Button {
                        model.finishPendingEdits()
                        Task {
                            await model.waitUntilSettled()
                            if !model.busy, model.errorText == nil { model.showCropEditor = true }
                        }
                    } label: {
                        Label("裁剪", systemImage: "crop.rotate")
                            .font(.subheadline)
                            .foregroundStyle(Ink.ivory)
                            .frame(minHeight: 44)
                    }
                    .disabled(model.editingSourcePreview == nil || model.busy)
                    ForEach(ToneControl.allCases, id: \.self) { control in
                        Button { selected = control } label: {
                            Text(control.rawValue)
                                .font(.subheadline.weight(selected == control ? .semibold : .regular))
                                .foregroundStyle(selected == control ? Ink.amber : Ink.mute)
                                .frame(minHeight: 36)
                        }
                        .accessibilityAddTraits(selected == control ? [.isSelected] : [])
                    }
                }.padding(.horizontal, 20)
            }
            VStack(spacing: 6) {
                HStack {
                    Text(selected.rawValue).font(.subheadline)
                    Spacer()
                    Text(selected == .exposure
                         ? String(format: "%+.1f EV", value.wrappedValue)
                         : String(format: "%+.0f", value.wrappedValue * 100))
                        .font(.body.monospacedDigit()).foregroundStyle(Ink.amber)
                }
                Slider(value: value, in: selected == .exposure ? -2...2 : -1...1,
                       step: selected == .exposure ? 0.1 : 0.01)
                    .tint(Ink.amber)
                    .accessibilityLabel(selected.rawValue)
                HStack {
                    Spacer()
                    Button("重置\(selected.rawValue)") { value.wrappedValue = 0 }
                        .frame(minHeight: 44)
                        .disabled(abs(value.wrappedValue) < 0.0001)
                }.font(.subheadline)
            }.padding(.horizontal, 20)
            HStack(spacing: 20) {
                Button {
                    model.finishPendingEdits()
                    Task {
                        await model.waitUntilSettled()
                        if !model.busy, model.errorText == nil { advanced = true }
                    }
                } label: {
                    Label("曲线与 HSL", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }.disabled(model.busy || model.globalEditingPreview == nil)
                Button {
                    model.finishPendingEdits()
                    Task {
                        await model.waitUntilSettled()
                        if !model.busy, model.errorText == nil { retouch = true }
                    }
                } label: {
                    Label("局部与修复", systemImage: "paintbrush.pointed")
                }.disabled(model.busy || model.retouchBasePreview == nil)
                Spacer(minLength: 0)
            }
            .font(.subheadline).frame(minHeight: 44).padding(.horizontal, 20)
        }
        .foregroundStyle(Ink.ivory)
        .fullScreenCover(isPresented: $advanced) {
            if let image = model.globalEditingPreview {
                AdvancedColorEditor(image: image, settings: model.adjustments, onApply: model.applyAdjustments)
            }
        }
        .fullScreenCover(isPresented: $retouch) {
            if let image = model.retouchBasePreview {
                RetouchEditor(image: image, edits: model.adjustments.retouch, onApply: model.applyRetouch)
            }
        }
    }
}
