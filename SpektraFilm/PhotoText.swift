import UIKit
import CoreText

/// Unmodified, offline Chinese fonts distributed with their SIL OFL notices.
enum PhotoTextFont: String, CaseIterable, Identifiable, Sendable {
    case sans, serif, wenkai
    var id: String { rawValue }
    var title: String {
        switch self { case .sans: "Noto 黑体"; case .serif: "Noto 宋体"; case .wenkai: "霞鹜文楷" }
    }
    var file: String {
        switch self {
        case .sans: "NotoSansCJKsc-Regular.otf"
        case .serif: "NotoSerifCJKsc-Regular.otf"
        case .wenkai: "LXGWWenKai-Regular.ttf"
        }
    }
    var postScript: String {
        switch self {
        case .sans: "NotoSansCJKsc-Regular"
        case .serif: "NotoSerifCJKsc-Regular"
        case .wenkai: "LXGWWenKai-Regular"
        }
    }
    private static let registration: Void = {
        for face in allCases {
            if let url = Bundle.main.url(forResource: face.file, withExtension: nil, subdirectory: "Fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()
    var isAvailable: Bool { Self.registration; return UIFont(name: postScript, size: 20) != nil }
    func font(_ size: CGFloat) -> UIFont {
        Self.registration
        return UIFont(name: postScript, size: size) ?? .systemFont(ofSize: size)
    }
}

struct PhotoTextLayer: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id = UUID().uuidString
    var text = ""
    var fontID = PhotoTextFont.sans.rawValue
    var size: Double = 0.07
    var x: Double = 0.5
    var y: Double = 0.5
    var color = "ivory"
    var alignment = "center"
    var shadow = true

    static let colors = ["ivory", "black", "amber", "red", "blue", "green"]
    static func ink(_ key: String) -> UIColor {
        switch key {
        case "black": UIColor(white: 0.06, alpha: 1)
        case "amber": UIColor(red: 1, green: 0.76, blue: 0.35, alpha: 1)
        case "red": UIColor(red: 1, green: 0.35, blue: 0.33, alpha: 1)
        case "blue": UIColor(red: 0.45, green: 0.75, blue: 1, alpha: 1)
        case "green": UIColor(red: 0.60, green: 0.85, blue: 0.64, alpha: 1)
        default: UIColor(red: 1, green: 0.98, blue: 0.93, alpha: 1)
        }
    }
    static func colorTitle(_ key: String) -> String {
        switch key { case "black": "墨黑"; case "amber": "琥珀"; case "red": "珊瑚红"; case "blue": "晴蓝"; case "green": "浅绿"; default: "暖白" }
    }
    func sanitized() -> Self {
        var value = self
        value.text = String(text.prefix(200))
        value.size = size.isFinite ? min(0.20, max(0.025, size)) : 0.07
        value.x = x.isFinite ? min(1, max(0, x)) : 0.5
        value.y = y.isFinite ? min(1, max(0, y)) : 0.5
        if PhotoTextFont(rawValue: fontID) == nil { value.fontID = PhotoTextFont.sans.rawValue }
        if !Self.colors.contains(color) { value.color = "ivory" }
        if !["left", "center", "right"].contains(alignment) { value.alignment = "center" }
        return value
    }
    static func sanitized(_ layers: [Self]) -> [Self] {
        var seen = Set<String>()
        return layers.prefix(8).map { layer in
            var value = layer.sanitized()
            if !seen.insert(value.id).inserted { value.id = UUID().uuidString }
            return value
        }.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

enum PhotoTextPainter {
    struct Layout { var rect: CGRect; var attributes: [NSAttributedString.Key: Any] }
    /// UIKit top-left coordinates, normalized against the photo opening (not its mat).
    static func layout(_ raw: PhotoTextLayer, in area: CGRect) -> Layout {
        let layer = raw.sanitized()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = layer.alignment == "left" ? .left : layer.alignment == "right" ? .right : .center
        paragraph.lineBreakMode = .byWordWrapping
        let face = PhotoTextFont(rawValue: layer.fontID) ?? .sans
        var pointSize = min(area.width, area.height) * layer.size
        let maxWidth = area.width * 0.88
        var width = maxWidth
        let maxHeight = area.height * 0.90
        var attributes: [NSAttributedString.Key: Any] = [:]
        var height: CGFloat = 0
        for _ in 0..<12 {
            attributes = [.font: face.font(pointSize), .foregroundColor: PhotoTextLayer.ink(layer.color), .paragraphStyle: paragraph]
            let measured = (layer.text as NSString).boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
            height = measured.height
            width = min(maxWidth, max(1, measured.width + pointSize * 0.02))
            if height <= maxHeight { break }
            pointSize *= max(0.5, min(0.9, maxHeight / max(height, 1)))
        }
        height = min(maxHeight, height)
        let x = min(area.maxX - width, max(area.minX, area.minX + layer.x * area.width - width / 2))
        let y = min(area.maxY - height, max(area.minY, area.minY + layer.y * area.height - height / 2))
        if layer.shadow {
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.65)
            shadow.shadowBlurRadius = pointSize * 0.08
            shadow.shadowOffset = CGSize(width: 0, height: pointSize * 0.04)
            attributes[.shadow] = shadow
        }
        return Layout(rect: CGRect(x: x, y: y, width: width, height: height), attributes: attributes)
    }
    static func apply(_ base: CGImage, layers: [PhotoTextLayer], contentRect: CGRect? = nil) -> CGImage? {
        let layers = PhotoTextLayer.sanitized(layers)
        guard !layers.isEmpty else { return base }
        let bounds = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let area = (contentRect ?? bounds).intersection(bounds)
        guard !area.isNull, area.width > 1, area.height > 1 else { return base }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let overlay = UIGraphicsImageRenderer(size: bounds.size, format: format).image { renderer in
            renderer.cgContext.clip(to: area)
            for layer in layers {
                let placement = layout(layer, in: area)
                (layer.text as NSString).draw(with: placement.rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: placement.attributes, context: nil)
            }
        }
        guard let ink = overlay.cgImage else { return nil }
        return WatermarkPainter.composite(base: base, overlay: ink)
    }
}

struct PhotoTextSurface {
    var base: CGImage
    var area: CGRect
    var watermark: WatermarkDraw?
    func render(_ layers: [PhotoTextLayer]) -> CGImage? {
        guard let image = PhotoTextPainter.apply(base, layers: layers, contentRect: area) else { return nil }
        guard let mark = watermark else { return image }
        return WatermarkPainter.apply(image, preset: mark.preset, info: mark.context,
            identity: mark.identity, contentRect: area,
            offset: CGSize(width: mark.offsetX, height: mark.offsetY)) ?? image
    }
}
