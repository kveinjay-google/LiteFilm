import CoreGraphics
import CoreText
import CryptoKit
import Foundation
import UIKit

struct PaintRequest: @unchecked Sendable {
    var photo: CGImage
    var preset: FramePreset
    var mode: FrameCanvasMode
    var sourceWidth: Double
    var sourceHeight: Double
    var filmLabel: String
    /// 16 for export, 8 for preview and thumbnails.
    var bits: Int
    /// JPEG and HEIC have no alpha. Corners outside a rounded or deckled edge
    /// are filled with the paper color instead of turning black.
    var opaqueBackdrop: Bool
}

enum FramePainter {
    /// Same geometry `composite` uses for the photo opening.
    static func layout(for request: PaintRequest) -> FrameLayout? {
        let photo = request.photo
        let sourceW = request.sourceWidth > 1 ? request.sourceWidth : Double(photo.width)
        let sourceH = request.sourceHeight > 1 ? request.sourceHeight : Double(photo.height)
        let longEdge = Double(max(photo.width, photo.height))
        guard longEdge > 1 else { return nil }
        return try? FrameGeometry.layout(
            sourceWidth: sourceW,
            sourceHeight: sourceH,
            insets: request.preset.inset,
            mode: request.mode,
            longEdge: longEdge
        )
    }

    static func composite(_ request: PaintRequest) -> CGImage? {
        let photo = request.photo
        let sourceW = request.sourceWidth > 1 ? request.sourceWidth : Double(photo.width)
        let sourceH = request.sourceHeight > 1 ? request.sourceHeight : Double(photo.height)
        let longEdge = Double(max(photo.width, photo.height))
        guard longEdge > 1,
              let layout = try? FrameGeometry.layout(
                sourceWidth: sourceW,
                sourceHeight: sourceH,
                insets: request.preset.inset,
                mode: request.mode,
                longEdge: longEdge
              ),
              let ctx = context(width: Int(layout.canvasWidth), height: Int(layout.canvasHeight), bits: request.bits)
        else { return nil }

        let pen = Pen(context: ctx, height: layout.canvasHeight)
        let preset = request.preset
        let outerColor = UIColor(frameHex: preset.palette.outer)
        let innerColor = UIColor(frameHex: preset.palette.inner)
        let accent = UIColor(frameHex: preset.palette.accent)
        let ink = UIColor(frameHex: preset.palette.ink)
        let shortSide = layout.shortSide
        let radius = CGFloat(preset.cornerRadius) * shortSide
        let keyline = max(CGFloat(preset.innerRule) * shortSide * 4.2, shortSide * 0.0032)
        let margin = layout.minMargin
        let deckle: CGFloat
        if preset.structure == "deckle" {
            let raw = CGFloat(preset.details.deckleAmplitude) * shortSide * 7
            deckle = min(max(raw, shortSide * 0.012), max(margin * 0.36, 1))
        } else {
            deckle = 0
        }
        let shaped = radius > 0 || deckle > 0
        let canvas = CGRect(origin: .zero, size: CGSize(width: layout.canvasWidth, height: layout.canvasHeight))
        let outerPath = silhouette(canvas: canvas, amplitude: deckle, seed: frameSeed(preset.id), radius: radius)

        ctx.interpolationQuality = .high
        if request.opaqueBackdrop {
            pen.fill(UIBezierPath(rect: canvas), color: shaped ? outerColor.darkened(0.90) : outerColor)
        }
        pen.fill(outerPath, color: outerColor)
        if deckle > 0.4 {
            pen.stroke(outerPath, color: accent.mixed(with: .white, amount: 0.45), width: max(1.6, shortSide * 0.006))
        }

        let fitted = contain(photo, in: layout.photo)
        pen.draw(photo, in: fitted)

        ctx.saveGState()
        pen.clip(outer: outerPath, hole: layout.photo)
        drawStructure(
            preset: preset,
            pen: pen,
            layout: layout,
            outer: outerColor,
            inner: innerColor,
            accent: accent,
            ink: ink,
            radius: radius,
            keyline: keyline,
            margin: margin,
            shortSide: shortSide
        )
        if preset.grain > 0 && !isFlatLightMat(outerColor) {
            let shown = min(0.5, CGFloat(preset.grain) * 6.5)
            pen.grain(preset: preset, canvas: canvas, alpha: shown)
        }
        if preset.details.registrationMarks {
            registration(pen: pen, photo: layout.photo, accent: accent, shortSide: shortSide, margin: margin)
        }
        annotation(pen: pen, preset: preset, layout: layout, ink: ink, shortSide: shortSide, label: request.filmLabel)
        ctx.restoreGState()
        return ctx.makeImage()
    }

    static func downsample(_ image: CGImage, longEdge: Int) -> CGImage {
        let width = image.width
        let height = image.height
        let edge = max(width, height)
        guard edge > longEdge, longEdge > 8 else { return image }
        let scale = CGFloat(longEdge) / CGFloat(edge)
        let targetW = max(1, Int((CGFloat(width) * scale).rounded()))
        let targetH = max(1, Int((CGFloat(height) * scale).rounded()))
        guard let ctx = context(width: targetW, height: targetH, bits: 8) else { return image }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        return ctx.makeImage() ?? image
    }

    /// Tight 8-bit buffer, top-left origin, for tests.
    static func pixels8(_ image: CGImage) -> (width: Int, height: Int, bytes: [UInt8])? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: info
        ) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (width, height, bytes)
    }

    static func syntheticPhoto(width: Int, height: Int) -> CGImage? {
        guard let ctx = context(width: width, height: height, bits: 8) else { return nil }
        guard let data = ctx.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let row = ctx.bytesPerRow
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * row + x * 4
                let t = Double(x) / Double(max(width - 1, 1))
                pixels[offset] = UInt8((1 - t) * 255)
                pixels[offset + 1] = 40
                pixels[offset + 2] = UInt8(t * 255)
                pixels[offset + 3] = 255
            }
        }
        return ctx.makeImage()
    }

    private static func context(width: Int, height: Int, bits: Int) -> CGContext? {
        guard width > 0, height > 0, width < 16000, height < 16000,
              let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)
        else { return nil }
        if bits >= 16 {
            let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
            return CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 16,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: info
            )
        }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: info
        )
    }

    private static func drawStructure(
        preset: FramePreset,
        pen: Pen,
        layout: FrameLayout,
        outer: UIColor,
        inner: UIColor,
        accent: UIColor,
        ink: UIColor,
        radius: CGFloat,
        keyline: CGFloat,
        margin: CGFloat,
        shortSide: CGFloat
    ) {
        let photo = layout.photo
        let kind = preset.structure
        switch kind {
        case "double_mat":
            let fraction = min(0.78, max(0.22, CGFloat(preset.details.outerLayer)))
            let left = layout.left * fraction
            let top = layout.top * fraction
            let width = layout.canvasWidth - left - layout.right * fraction
            let height = layout.canvasHeight - top - layout.bottom * fraction
            let opening = CGRect(x: left, y: top, width: width, height: height)
            let crack = max(shortSide * 0.007, 1.5)
            // Soft ink offset reads as a stain on light / near-gray paper.
            if !isFlatLightMat(outer) {
                pen.fill(rect(opening.offsetBy(dx: crack * 0.65, dy: crack * 0.8), rx: 0), color: ink.withAlphaComponent(0.38))
            }
            pen.fill(rect(opening, rx: 0), color: inner)
            pen.stroke(rect(opening, rx: 0), color: ink.withAlphaComponent(0.9), width: crack)
            pen.stroke(rect(photo.insetBy(dx: -keyline, dy: -keyline), rx: 0), color: accent, width: max(keyline * 0.55, shortSide * 0.0022))
        case "rebate", "sprocket":
            let requested = CGFloat(preset.details.railWidth) * shortSide * 2.5
            let rail = min(max(requested, shortSide * 0.014), margin * 0.84)
            pen.fill(rect(photo.insetBy(dx: -rail, dy: -rail), rx: 0), color: inner)
            if kind == "sprocket" {
                let count = max(3, preset.details.sprocketCount)
                let pitch = photo.height / CGFloat(count)
                let holeW = rail * 0.72
                let holeH = min(pitch * 0.58, rail * 0.86)
                let digit = min(holeH * 0.62, shortSide * 0.02)
                for index in 0..<count {
                    let centerY = photo.minY + pitch * (CGFloat(index) + 0.5)
                    for centerX in [photo.minX - rail * 0.5, photo.maxX + rail * 0.5] {
                        let hole = CGRect(x: centerX - holeW / 2, y: centerY - holeH / 2, width: holeW, height: holeH)
                        pen.fill(rect(hole, rx: min(holeW, holeH) * 0.18), color: outer)
                        pen.stroke(rect(hole, rx: min(holeW, holeH) * 0.18), color: accent, width: max(0.8, holeW * 0.06))
                        if digit >= 4.5 {
                            pen.text(
                                String(format: "%02d", index + 1),
                                at: CGPoint(x: centerX, y: centerY + digit * 0.32),
                                size: digit,
                                color: inner,
                                anchor: "middle"
                            )
                        }
                    }
                }
            }
            pen.stroke(rect(photo.insetBy(dx: -keyline * 0.65, dy: -keyline * 0.65), rx: 0), color: accent, width: max(keyline * 0.7, shortSide * 0.003))
        case "slide_mount":
            let inset = min(margin * 0.22, shortSide * 0.02)
            let mount = canvasInset(layout, by: inset)
            pen.fill(rect(mount, rx: max(shortSide * 0.016, radius)), color: inner)
            let bevel = min(margin * 0.46, shortSide * 0.03)
            pen.fill(rect(photo.insetBy(dx: -bevel, dy: -bevel), rx: shortSide * 0.006), color: accent)
            pen.fill(rect(photo.insetBy(dx: -bevel * 0.42, dy: -bevel * 0.42), rx: shortSide * 0.003), color: inner.darkened(0.72))
            pen.stroke(rect(photo.insetBy(dx: -keyline, dy: -keyline), rx: 0), color: ink, width: keyline)
            let cut = min(margin * 0.7, shortSide * 0.045)
            let width = layout.canvasWidth
            let height = layout.canvasHeight
            let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (0, 0, 1, 1), (width, 0, -1, 1), (width, height, -1, -1), (0, height, 1, -1),
            ]
            for (px, py, sx, sy) in corners {
                pen.fill(polygon([
                    CGPoint(x: px, y: py),
                    CGPoint(x: px + sx * cut, y: py),
                    CGPoint(x: px, y: py + sy * cut),
                ]), color: outer)
            }
        case "instant":
            pen.stroke(rect(photo.insetBy(dx: -keyline * 0.8, dy: -keyline * 0.8), rx: 0), color: ink, width: max(keyline * 0.85, shortSide * 0.0035))
            let extra = max(0, layout.bottom - layout.top)
            let barH = min(layout.bottom * 0.46, max(extra * 0.42, shortSide * 0.02))
            let barY = layout.canvasHeight - barH - max(1.5, layout.bottom * 0.1)
            if barY > photo.maxY + 2 {
                let bar = CGRect(x: layout.left * 0.35, y: barY, width: layout.canvasWidth - layout.left * 0.7, height: barH)
                pen.fill(rect(bar, rx: min(barH * 0.2, shortSide * 0.006)), color: accent)
            }
        case "corner_mount":
            let size = min(max(CGFloat(preset.details.cornerSize) * shortSide, shortSide * 0.05), margin * 0.92)
            let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (photo.minX, photo.minY, -1, -1),
                (photo.maxX, photo.minY, 1, -1),
                (photo.maxX, photo.maxY, 1, 1),
                (photo.minX, photo.maxY, -1, 1),
            ]
            for (px, py, sx, sy) in corners {
                let pocket = polygon([
                    CGPoint(x: px, y: py),
                    CGPoint(x: px + sx * size, y: py),
                    CGPoint(x: px, y: py + sy * size),
                ])
                pen.fill(pocket, color: ink.withAlphaComponent(0.9))
                let tab = polygon([
                    CGPoint(x: px + sx * size * 0.16, y: py + sy * size * 0.16),
                    CGPoint(x: px + sx * size * 0.92, y: py + sy * size * 0.16),
                    CGPoint(x: px + sx * size * 0.16, y: py + sy * size * 0.92),
                ])
                pen.fill(tab, color: accent)
                pen.stroke(tab, color: ink, width: max(1, shortSide * 0.002))
            }
        case "asymmetric":
            // Accent color strip on light paper reads as a dirty band; keep only the opening keyline.
            if !isFlatLightMat(outer) {
                let side = widestSide(layout)
                let band = min(max(side.value * 0.42, shortSide * 0.012), side.value * 0.62)
                switch side.name {
                case "left":
                    let x = max(1, photo.minX - side.value * 0.78)
                    pen.fill(rect(CGRect(x: x, y: photo.minY, width: band, height: photo.height), rx: 0), color: accent)
                case "right":
                    let x = photo.maxX + side.value * 0.28
                    pen.fill(rect(CGRect(x: x, y: photo.minY, width: band, height: photo.height), rx: 0), color: accent)
                case "top":
                    let y = max(1, photo.minY - side.value * 0.72)
                    pen.fill(rect(CGRect(x: photo.minX, y: y, width: photo.width, height: band), rx: 0), color: accent)
                default:
                    let y = photo.maxY + side.value * 0.4
                    pen.fill(rect(CGRect(x: photo.minX, y: y, width: photo.width, height: band), rx: 0), color: accent)
                }
            }
            pen.stroke(rect(photo.insetBy(dx: -shortSide * 0.004, dy: -shortSide * 0.004), rx: 0), color: ink.withAlphaComponent(0.55), width: max(1, shortSide * 0.002))
        case "linen":
            let flat = isFlatLightMat(outer)
            if !flat {
                pen.linen(
                    canvas: CGRect(x: 0, y: 0, width: layout.canvasWidth, height: layout.canvasHeight),
                    color: ink,
                    spacing: max(3.5, shortSide * 0.011),
                    alpha: min(0.55, 0.28 + CGFloat(preset.grain) * 3.5)
                )
            }
            let depth = min(margin * 0.55, shortSide * 0.04)
            if !flat {
                pen.fill(rect(photo.insetBy(dx: -depth - shortSide * 0.006, dy: -depth - shortSide * 0.006), rx: 0), color: ink.withAlphaComponent(0.35))
            }
            pen.fill(rect(photo.insetBy(dx: -depth, dy: -depth), rx: 0), color: inner)
            pen.stroke(rect(photo.insetBy(dx: -keyline, dy: -keyline), rx: 0), color: ink, width: max(keyline, shortSide * 0.003))
        case "letterbox":
            let bar = letterboxInk(outer: outer, inner: inner, ink: ink)
            pen.fill(rect(CGRect(x: 0, y: 0, width: layout.canvasWidth, height: photo.minY), rx: 0), color: bar)
            pen.fill(rect(CGRect(x: 0, y: photo.maxY, width: layout.canvasWidth, height: max(0, layout.canvasHeight - photo.maxY)), rx: 0), color: bar)
            let separator = max(shortSide * 0.007, 1.6)
            pen.line(
                CGPoint(x: 0, y: photo.minY - separator * 0.5),
                CGPoint(x: layout.canvasWidth, y: photo.minY - separator * 0.5),
                color: accent,
                width: separator
            )
            pen.line(
                CGPoint(x: 0, y: photo.maxY + separator * 0.5),
                CGPoint(x: layout.canvasWidth, y: photo.maxY + separator * 0.5),
                color: accent,
                width: separator
            )
        case "inner_rule":
            let gap = max(keyline * 2.4, shortSide * 0.012)
            pen.stroke(rect(photo.insetBy(dx: -gap, dy: -gap), rx: radius), color: ink.withAlphaComponent(0.85), width: max(keyline * 0.45, 1))
            pen.stroke(rect(photo.insetBy(dx: -keyline, dy: -keyline), rx: 0), color: accent, width: keyline)
        case "deckle":
            let pad = min(margin * 0.28, shortSide * 0.018)
            pen.stroke(rect(photo.insetBy(dx: -pad, dy: -pad), rx: 0), color: accent, width: max(keyline * 0.5, shortSide * 0.0025))
        default:
            break
        }
        if preset.innerRule > 0 && kind == "simple" {
            pen.stroke(rect(photo.insetBy(dx: -keyline, dy: -keyline), rx: 0), color: accent, width: keyline)
        }
    }


    /// Light / near-white / near-gray mat paper that must stay a flat solid fill.
    /// High luminance + low chroma. Dark rails and film rebate keep their texture.
    private static func isFlatLightMat(_ color: UIColor) -> Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        let chroma = max(red, green, blue) - min(red, green, blue)
        return luminance >= 0.70 && chroma <= 0.12
    }

    private static func letterboxInk(outer: UIColor, inner: UIColor, ink: UIColor) -> UIColor {
        let outerL = outer.relativeLuminance()
        let innerL = inner.relativeLuminance()
        let inkL = ink.relativeLuminance()
        let candidate = innerL < inkL ? inner : ink
        let candidateL = min(innerL, inkL)
        if abs(candidateL - outerL) > 0.22 { return candidate }
        return outerL > 0.55 ? ink.darkened(0.45) : ink
    }

    private static func registration(pen: Pen, photo: CGRect, accent: UIColor, shortSide: CGFloat, margin: CGFloat) {
        let length = min(0.042 * shortSide, margin * 0.62)
        let offset = min(0.016 * shortSide, margin * 0.22)
        let width = max(1.1, 0.0024 * shortSide)
        let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (photo.minX, photo.minY, -1, -1),
            (photo.maxX, photo.minY, 1, -1),
            (photo.maxX, photo.maxY, 1, 1),
            (photo.minX, photo.maxY, -1, 1),
        ]
        for (px, py, sx, sy) in corners {
            pen.line(
                CGPoint(x: px + sx * offset, y: py + sy * offset),
                CGPoint(x: px + sx * (offset + length), y: py + sy * offset),
                color: accent,
                width: width
            )
            pen.line(
                CGPoint(x: px + sx * offset, y: py + sy * offset),
                CGPoint(x: px + sx * offset, y: py + sy * (offset + length)),
                color: accent,
                width: width
            )
        }
    }

    private static func annotation(pen: Pen, preset: FramePreset, layout: FrameLayout, ink: UIColor, shortSide: CGFloat, label: String) {
        let text: String
        switch preset.annotation.mode {
        case "frame_code":
            text = preset.annotation.text
        case "selected_film":
            text = label
        default:
            text = ""
        }
        guard !text.isEmpty, layout.bottom > 4 else { return }
        let size = min(max(shortSide * 0.026, 8), layout.bottom * 0.42)
        guard size >= 4 else { return }
        let anchor: String
        let x: CGFloat
        switch preset.annotation.placement {
        case "bottom_center":
            x = layout.photo.midX
            anchor = "middle"
        case "bottom_right":
            x = layout.photo.maxX
            anchor = "end"
        default:
            x = layout.photo.minX
            anchor = "start"
        }
        let baseline = layout.photo.maxY + layout.bottom * 0.58 + size * 0.32
        pen.text(text, at: CGPoint(x: x, y: baseline), size: size, color: ink, anchor: anchor)
    }

    private static func widestSide(_ layout: FrameLayout) -> (name: String, value: CGFloat) {
        var best = (name: "top", value: layout.top)
        let rest = [("right", layout.right), ("bottom", layout.bottom), ("left", layout.left)]
        for item in rest where item.1 > best.value {
            best = (name: item.0, value: item.1)
        }
        return best
    }

    private static func canvasInset(_ layout: FrameLayout, by inset: CGFloat) -> CGRect {
        CGRect(
            x: inset,
            y: inset,
            width: max(0, layout.canvasWidth - inset * 2),
            height: max(0, layout.canvasHeight - inset * 2)
        )
    }

    private static func rect(_ rect: CGRect, rx: CGFloat) -> UIBezierPath {
        let safe = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: max(0, rect.width),
            height: max(0, rect.height)
        )
        let radius = min(max(0, rx), safe.width / 2, safe.height / 2)
        if radius > 0.2 {
            return UIBezierPath(roundedRect: safe, cornerRadius: radius)
        }
        return UIBezierPath(rect: safe)
    }

    private static func polygon(_ points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.close()
        return path
    }

    private static func silhouette(canvas: CGRect, amplitude: CGFloat, seed: UInt64, radius: CGFloat) -> UIBezierPath {
        if amplitude > 0.4 {
            return decklePath(canvas: canvas, amplitude: amplitude, seed: seed)
        }
        return rect(canvas, rx: radius)
    }

    private static func decklePath(canvas: CGRect, amplitude: CGFloat, seed: UInt64) -> UIBezierPath {
        var rng = SeededRNG(seed: seed)
        let count = 34
        var points: [CGPoint] = []
        let width = canvas.width
        let height = canvas.height
        func tooth(_ index: Int) -> CGFloat {
            let deep = index % 2 == 0
            let unit = deep ? (0.72 + 0.28 * rng.unit()) : (0.08 + 0.22 * rng.unit())
            return amplitude * unit
        }
        for index in 0...count {
            points.append(CGPoint(x: width * CGFloat(index) / CGFloat(count), y: tooth(index)))
        }
        for index in 1...count {
            points.append(CGPoint(x: width - tooth(index), y: height * CGFloat(index) / CGFloat(count)))
        }
        for index in 1...count {
            points.append(CGPoint(x: width * (1 - CGFloat(index) / CGFloat(count)), y: height - tooth(index)))
        }
        for index in 1..<count {
            points.append(CGPoint(x: tooth(index), y: height * (1 - CGFloat(index) / CGFloat(count))))
        }
        return polygon(points)
    }

    private static func contain(_ image: CGImage, in rect: CGRect) -> CGRect {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        guard imageWidth > 0, imageHeight > 0, rect.width > 0, rect.height > 0 else { return rect }
        let scale = min(rect.width / imageWidth, rect.height / imageHeight)
        let width = imageWidth * scale
        let height = imageHeight * scale
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    private static func frameSeed(_ id: String) -> UInt64 {
        let digest = SHA256.hash(data: Data(id.utf8))
        var value: UInt64 = 0
        for byte in digest.prefix(4) {
            value = (value << 8) | UInt64(byte)
        }
        return value == 0 ? 1 : value
    }
}

private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(1 << 53)
    }
}

private final class GrainCache: NSObject {
    static let shared = NSCache<NSString, CGImageBox>()
}

private final class CGImageBox: NSObject {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

private final class Pen {
    let ctx: CGContext
    let height: CGFloat

    init(context: CGContext, height: CGFloat) {
        ctx = context
        self.height = height
    }

    func fill(_ path: UIBezierPath, color: UIColor) {
        ctx.saveGState()
        ctx.setFillColor(color.cgColor)
        ctx.addPath(flipped(path).cgPath)
        ctx.fillPath()
        ctx.restoreGState()
    }

    func stroke(_ path: UIBezierPath, color: UIColor, width: CGFloat) {
        guard width > 0, !path.isEmpty else { return }
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.addPath(flipped(path).cgPath)
        ctx.strokePath()
        ctx.restoreGState()
    }

    func line(_ start: CGPoint, _ end: CGPoint, color: UIColor, width: CGFloat) {
        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: end)
        stroke(path, color: color, width: width)
    }

    func clip(outer: UIBezierPath, hole: CGRect) {
        ctx.beginPath()
        ctx.addPath(flipped(outer).cgPath)
        ctx.addPath(flipped(UIBezierPath(rect: hole)).cgPath)
        ctx.clip(using: .evenOdd)
    }

    func draw(_ image: CGImage, in topDown: CGRect) {
        let flippedRect = CGRect(
            x: topDown.minX,
            y: height - topDown.maxY,
            width: topDown.width,
            height: topDown.height
        )
        ctx.draw(image, in: flippedRect)
    }

    func text(_ string: String, at baseline: CGPoint, size: CGFloat, color: UIColor, anchor: String) {
        let font = CTFontCreateWithName("Menlo-Regular" as CFString, size, nil)
        let attributed = NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        var x = baseline.x
        if anchor == "middle" { x -= width / 2 }
        if anchor == "end" { x -= width }
        ctx.textPosition = CGPoint(x: x, y: height - baseline.y)
        CTLineDraw(line, ctx)
    }

    func grain(preset: FramePreset, canvas: CGRect, alpha: CGFloat) {
        let tile = grainTile(id: preset.id, color: UIColor(frameHex: preset.palette.ink))
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.draw(tile, in: CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height), byTiling: true)
        ctx.restoreGState()
    }

    func linen(canvas: CGRect, color: UIColor, spacing: CGFloat, alpha: CGFloat) {
        let step = max(3, spacing)
        ctx.saveGState()
        ctx.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
        ctx.setLineWidth(max(0.8, step * 0.16))
        ctx.beginPath()
        var x: CGFloat = 0
        while x <= canvas.width {
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: canvas.height))
            x += step
        }
        ctx.strokePath()
        ctx.setStrokeColor(color.withAlphaComponent(alpha * 0.65).cgColor)
        ctx.beginPath()
        var y: CGFloat = step * 0.5
        while y <= canvas.height {
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: canvas.width, y: y))
            y += step
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func flipped(_ path: UIBezierPath) -> UIBezierPath {
        let copy = path.copy() as! UIBezierPath
        copy.apply(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height))
        return copy
    }

    private func grainTile(id: String, color: UIColor) -> CGImage {
        if let cached = GrainCache.shared.object(forKey: id as NSString) {
            return cached.image
        }
        let tile = 48
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ctx = CGContext(
            data: nil,
            width: tile,
            height: tile,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: info
        )
        let image: CGImage
        if let ctx {
            var rng = SeededRNG(seed: FramePainterSeed.value(id))
            ctx.setFillColor(color.cgColor)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(0.7)
            ctx.setLineCap(.round)
            for _ in 0..<28 {
                let length = 1.2 + CGFloat(rng.unit()) * 3.4
                let x = CGFloat(rng.unit()) * 48
                let y = CGFloat(rng.unit()) * 48
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + length, y: y + CGFloat(rng.unit()) * 1.4 - 0.4))
                ctx.strokePath()
            }
            for _ in 0..<10 {
                let circle = CGRect(
                    x: CGFloat(rng.unit()) * 48,
                    y: CGFloat(rng.unit()) * 48,
                    width: 0.6 + CGFloat(rng.unit()) * 1.4,
                    height: 0.6 + CGFloat(rng.unit()) * 1.4
                )
                ctx.fillEllipse(in: circle)
            }
            image = ctx.makeImage() ?? blank()
        } else {
            image = blank()
        }
        GrainCache.shared.setObject(CGImageBox(image), forKey: id as NSString)
        return image
    }

    private func blank() -> CGImage {
        let ctx = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }
}

private enum FramePainterSeed {
    static func value(_ id: String) -> UInt64 {
        let digest = SHA256.hash(data: Data(id.utf8))
        var value: UInt64 = 0
        for byte in digest.prefix(4) {
            value = (value << 8) | UInt64(byte)
        }
        return value == 0 ? 1 : value
    }
}

extension UIColor {
    convenience init(frameHex hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        let value = UInt32(text, radix: 16) ?? 0xFFFFFF
        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        self.init(cgColor: CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
    }

    func darkened(_ factor: CGFloat) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UIColor(red: red * factor, green: green * factor, blue: blue * factor, alpha: alpha)
    }

    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        var otherRed: CGFloat = 0
        var otherGreen: CGFloat = 0
        var otherBlue: CGFloat = 0
        var otherAlpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        other.getRed(&otherRed, green: &otherGreen, blue: &otherBlue, alpha: &otherAlpha)
        let t = min(1, max(0, amount))
        return UIColor(
            red: red + (otherRed - red) * t,
            green: green + (otherGreen - green) * t,
            blue: blue + (otherBlue - blue) * t,
            alpha: alpha + (otherAlpha - alpha) * t
        )
    }

    func relativeLuminance() -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}
