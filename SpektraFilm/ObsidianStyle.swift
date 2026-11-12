import SwiftUI

enum Ink {
    static let void = Color(red: 16/255, green: 24/255, blue: 22/255)
    static let surface = Color(red: 26/255, green: 36/255, blue: 32/255)
    static let ivory = Color(red: 245/255, green: 242/255, blue: 233/255)
    static let mute = Color(red: 164/255, green: 175/255, blue: 166/255)
    static let amber = Color(red: 222/255, green: 199/255, blue: 154/255)
    static let ember = Color(red: 1, green: 0.48, blue: 0.40)
    static let hairline = Color.white.opacity(0.10)
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
                .tracking(brand ? 0.4 : 0)
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
            .background(Ink.amber, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The same master artwork is used by the home-screen icon and the in-app identity.
struct BrandMark: View {
    var size: CGFloat = 64
    var body: some View {
        Image("BrandIcon").resizable().scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct StudioPanel: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Ink.hairline, lineWidth: 0.5))
    }
}
