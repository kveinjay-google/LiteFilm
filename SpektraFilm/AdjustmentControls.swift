import SwiftUI

private enum ToneControl: String, CaseIterable {
    case exposure = "曝光", highlights = "高光", shadows = "阴影", contrast = "对比度", saturation = "饱和度"

    var keyPath: WritableKeyPath<PhotoAdjustments, Double>? {
        switch self {
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
                    Button { model.showCropEditor = true } label: {
                        Label("裁剪与校正", systemImage: "crop.rotate")
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
        }
        .foregroundStyle(Ink.ivory)
    }
}
