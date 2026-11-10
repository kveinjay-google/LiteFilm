import SwiftUI

enum Ink {
    static let void = Color(red: 11/255, green: 13/255, blue: 16/255)
    static let surface = Color(red: 23/255, green: 26/255, blue: 30/255)
    static let ivory = Color(red: 241/255, green: 242/255, blue: 241/255)
    static let mute = Color(red: 152/255, green: 157/255, blue: 163/255)
    static let amber = Color(red: 210/255, green: 223/255, blue: 130/255)
    static let ember = Color(red: 1, green: 0.48, blue: 0.40)
    static let hairline = Color.white.opacity(0.14)
}

/// Equal side reservations keep the wordmark centered on the screen, not between controls.
struct ObsidianHeader<Leading: View, Trailing: View>: View {
    var title: String = "LiteFilm"
    var brand = true
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading().frame(width: 64, alignment: .leading)
            Text(title)
                .font(.system(size: brand ? 21 : 18, weight: .semibold))
                .tracking(brand ? 2.5 : 0)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            trailing().frame(width: 64, alignment: .trailing)
        }
        .foregroundStyle(Ink.ivory)
        .frame(minHeight: 56)
        .padding(.horizontal, 16)
        .background(Ink.void)
        .buttonStyle(.plain)
    }
}

struct ObsidianPrimaryButton: View {
    var title: String
    var systemImage: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(Ink.void)
            .background(Ink.amber, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
