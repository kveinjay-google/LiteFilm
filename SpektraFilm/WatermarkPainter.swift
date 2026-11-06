import CoreGraphics
import Foundation
import UIKit

/// Watermarks are drawn after the mat. They never enter the film engine.
/// Each preset is a small print credit: corner or baseline, short-side type
/// around 2.5–5% (a signature may reach ~7%), margin about 4% of the short side.
enum WatermarkPainter {
    static func apply(
        _ base: CGImage,
        preset: WatermarkPreset,
        info: WatermarkContext,
        identity: WatermarkIdentity = .blank,
        contentRect: CGRect? = nil,
        offset: CGSize = .zero
    ) -> CGImage? {
        let pixel = CGSize(width: base.width, height: base.height)
        guard pixel.width > 1, pixel.height > 1, pixel.width < 16000, pixel.height < 16000 else { return nil }
        let area: CGRect
        if let contentRect, contentRect.width > 8, contentRect.height > 8 {
            let bounds = CGRect(origin: .zero, size: pixel)
            area = contentRect.intersection(bounds)
            guard area.width > 8, area.height > 8 else { return base }
        } else {
            area = CGRect(origin: .zero, size: pixel)
        }
        guard let overlay = renderOverlay(
            preset: preset,
            info: info,
            identity: identity,
            size: pixel,
            area: area,
            offset: offset,
            backing: base
        ) else { return base }
        return composite(base: base, overlay: overlay)
    }

    private static func renderOverlay(
        preset: WatermarkPreset,
        info: WatermarkContext,
        identity: WatermarkIdentity,
        size: CGSize,
        area: CGRect,
        offset: CGSize,
        backing: CGImage
    ) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            Board(
                context: renderer.cgContext,
                size: size,
                area: area,
                offset: offset,
                preset: preset,
                info: info,
                identity: identity,
                backing: backing
            ).draw()
        }
        return image.cgImage
    }

    private static func composite(base: CGImage, overlay: CGImage) -> CGImage? {
        let width = base.width
        let height = base.height
        let bits = base.bitsPerComponent >= 16 ? 16 : 8
        let ctx = context(width: width, height: height, bits: bits, space: base.colorSpace)
            ?? context(width: width, height: height, bits: 8, space: CGColorSpace(name: CGColorSpace.displayP3))
        guard let ctx else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.interpolationQuality = .high
        ctx.draw(base, in: rect)
        ctx.draw(overlay, in: rect)
        return ctx.makeImage()
    }

    private static func context(width: Int, height: Int, bits: Int, space: CGColorSpace?) -> CGContext? {
        guard let colorSpace = space ?? CGColorSpace(name: CGColorSpace.displayP3) else { return nil }
        if bits >= 16 {
            let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
            return CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 16, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: info
            )
        }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        return CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: info
        )
    }
}

private final class Board {
    let ctx: CGContext
    let size: CGSize
    /// Photo opening when a frame is on; otherwise the full canvas.
    let area: CGRect
    /// Normalized drag offset relative to `area` width / height.
    let offset: CGSize
    let preset: WatermarkPreset
    let info: WatermarkContext
    let identity: WatermarkIdentity
    let backing: CGImage
    private var lumaCache: [Int: CGFloat] = [:]

    init(
        context: CGContext,
        size: CGSize,
        area: CGRect,
        offset: CGSize,
        preset: WatermarkPreset,
        info: WatermarkContext,
        identity: WatermarkIdentity,
        backing: CGImage
    ) {
        ctx = context
        self.size = size
        self.area = area
        self.offset = offset
        self.preset = preset
        self.info = info
        self.identity = identity
        self.backing = backing
    }

    private var studio: String { identity.resolvedStudio }
    private var signature: String { identity.resolvedSignature }
    private var monogramLetters: String { identity.resolvedMonogram }
    private var initialLetter: String { identity.resolvedInitial }
    private var siteLine: String { identity.resolvedSite }

    private var short: CGFloat { min(area.width, area.height) }
    private var margin: CGFloat { max(2, short * 0.042) }
    private var hair: CGFloat { max(0.6, short * 0.00125) }

    /// Proofing marks stay at their named opacity. Everything else may flip
    /// ivory/graphite so a credit still reads on a white mat or a dark frame.
    private var quiet: Bool {
        preset.kind == "faintCenter" || preset.kind == "faintTile" || preset.opacity < 0.23
    }

    func draw() {
        switch preset.kind {
        case "signSerifBR":
            credit(studio, spot: .bottomRight, font: serif(0.032), trackingEm: 0.16)
        case "signScriptBR":
            credit(signature, spot: .bottomRight, font: script(0.064), trackingEm: 0)
        case "signCopyright":
            credit(identity.resolvedCopyright(year: yearText), spot: .bottomRight, font: serif(0.026), trackingEm: 0.06)
        case "signStudio":
            studioBlock(.bottomRight)
        case "signTracked":
            credit(studio, spot: .bottomCenter, font: serif(0.026), trackingEm: 0.50)
        case "filmBL":
            credit(info.filmName, spot: .bottomLeft, font: serif(0.026), trackingEm: 0.04)
        case "filmBR":
            credit(info.filmName, spot: .bottomRight, font: serif(0.026), trackingEm: 0.04)
        case "dateBR":
            credit(info.dateText, spot: .bottomRight, font: serif(0.024), trackingEm: 0.08)
        case "hairlineBR":
            ruleOver(studio, spot: .bottomRight, font: serif(0.030), trackingEm: 0.14, lineScale: 1)
        case "filmDate":
            credit(join([info.filmName, info.dateText]), spot: .bottomCenter, font: serif(0.024), trackingEm: 0.08)
        case "monogramRing":
            monogram(monogramLetters, shape: .circle, diameter: short * 0.072)
        case "monogramSF":
            credit(monogramLetters, spot: .bottomRight, font: serif(0.040), trackingEm: 0.08)
        case "initialS":
            credit(initialLetter, spot: .bottomRight, font: script(0.070), trackingEm: 0)
        case "signSerifBL":
            credit(studio, spot: .bottomLeft, font: serif(0.030), trackingEm: 0.10)
        case "scriptBC":
            credit(signature, spot: .bottomCenter, font: script(0.062), trackingEm: 0)
        case "nameYear":
            credit("\(studio), \(yearText)", spot: .bottomRight, font: serif(0.028), trackingEm: 0.06)
        case "siteBR":
            credit(siteLine, spot: .bottomRight, font: sans(0.020, weight: .regular), trackingEm: 0.22)
        case "nameFilm":
            nameOverFilm()
        case "faintCenter":
            credit(studio, spot: .center, font: serif(0.030), trackingEm: 0.34)
        case "baselineBC":
            ruleOver(studio, spot: .bottomCenter, font: serif(0.028), trackingEm: 0.18, lineScale: 1.7)
        case "cornerSplit":
            credit(info.filmName, spot: .bottomLeft, font: serif(0.024), trackingEm: 0.04)
            credit(info.dateText, spot: .bottomRight, font: serif(0.022), trackingEm: 0.06)
        case "scriptDate":
            scriptOverDate()
        case "edgeCodeH":
            credit(rebateLine, spot: .bottomLeft, font: mono(0.020), trackingEm: 0.12)
        case "edgeCodeV":
            vertical(edgeCompact, x: area.minX + margin, anchor: .left, font: mono(0.020))
        case "contactStamp":
            stamp("CONTACT", font: sans(0.016, weight: .regular), trackingEm: 0.28, spot: .bottomRight, angle: -5 * .pi / 180)
        case "dateStamp":
            guard !info.dateText.isEmpty else { break }
            stamp(info.dateText, font: serif(0.018), trackingEm: 0.04, spot: .bottomLeft, angle: -7 * .pi / 180)
        case "cropMarks":
            cropMarks()
        case "sideRight":
            vertical(studio, x: area.maxX - margin, anchor: .right, font: serif(0.020))
        case "faintTile":
            faintTile()
        case "indexBR":
            credit(indexText, spot: .bottomRight, font: sans(0.022, weight: .regular), trackingEm: 0.12)
        case "ruleName":
            ruleBeside(studio)
        case "underlineBC":
            underline(studio, spot: .bottomCenter, font: serif(0.028), trackingEm: 0.16)
        case "monogramSquare":
            monogram(initialLetter, shape: .square, diameter: short * 0.060)
        case "inkSign":
            underline(studio, spot: .bottomLeft, font: serif(0.030), trackingEm: 0.08)
        case "studioBL":
            studioBlock(.bottomLeft)
        case "printCell":
            printCell()
        default:
            break
        }
    }

    private var yearText: String {
        let digits = info.dateText.filter(\.isNumber)
        if digits.count >= 4 { return String(digits.prefix(4)) }
        return String(Calendar(identifier: .gregorian).component(.year, from: Date()))
    }

    private var indexText: String {
        guard !info.frameNumber.isEmpty else { return "" }
        if info.frameTotal.isEmpty { return info.frameNumber }
        return "\(info.frameNumber)  /  \(info.frameTotal)"
    }

    private var rebateLine: String {
        let code = info.frameCode.replacingOccurrences(of: "_", with: " ")
        return join([info.frameNumber, info.filmName.uppercased(), code.uppercased()], separator: "    ")
    }

    /// Real film name. Drops leading words only when the line would run the full side.
    private var edgeCompact: String {
        var parts: [String] = []
        if !info.frameNumber.isEmpty { parts.append(info.frameNumber) }
        let film = edgeFilm(info.filmName, limit: 18)
        if !film.isEmpty { parts.append(film.uppercased()) }
        return parts.joined(separator: "  ")
    }

    private func edgeFilm(_ raw: String, limit: Int) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= limit { return trimmed }
        var words = trimmed.split(separator: " ").map(String.init)
        while words.count > 1 && words.joined(separator: " ").count > limit {
            words.removeFirst()
        }
        let text = words.joined(separator: " ")
        if text.count <= limit { return text }
        return String(text.prefix(limit))
    }

    private func nameOverFilm() {
        guard let name = prepared(studio, font: serif(0.030), trackingEm: 0.12) else { return }
        var rows = [name]
        if let film = prepared(info.filmName, font: sans(0.016, weight: .regular), trackingEm: 0.12) {
            rows.append(film)
        }
        drawRuns(rows, at: place(.bottomRight), anchor: .right, valign: .bottom, gap: name.font.pointSize * 0.06)
    }

    private func scriptOverDate() {
        guard let name = prepared(signature, font: script(0.058), trackingEm: 0) else { return }
        var rows = [name]
        if let date = prepared(info.dateText, font: sans(0.015, weight: .regular), trackingEm: 0.14) {
            rows.append(date)
        }
        drawRuns(rows, at: place(.bottomRight), anchor: .right, valign: .bottom, gap: name.font.pointSize * 0.02)
    }

    private func studioBlock(_ spot: Spot) {
        guard let name = prepared(signature, font: script(0.058), trackingEm: 0) else { return }
        let nameWidth = measure(name.text, font: name.font, tracking: name.tracking)
        var rows = [name]
        if let sub = trackedLine("PHOTOGRAPHY", fraction: 0.015, target: nameWidth) {
            rows.append(sub)
        }
        drawRuns(rows, at: place(spot), anchor: anchor(for: spot), valign: .bottom, gap: name.font.pointSize * 0.04)
    }

    private func credit(_ text: String, spot: Spot, font: UIFont, trackingEm: CGFloat) {
        guard let row = prepared(text, font: font, trackingEm: trackingEm) else { return }
        drawRuns([row], at: place(spot), anchor: anchor(for: spot), valign: valign(for: spot))
    }

    private func ruleOver(_ text: String, spot: Spot, font: UIFont, trackingEm: CGFloat, lineScale: CGFloat) {
        guard let row = prepared(text, font: font, trackingEm: trackingEm) else { return }
        guard let rect = drawRuns([row], at: place(spot), anchor: anchor(for: spot), valign: valign(for: spot)) else { return }
        let gap = max(1.5, short * 0.010)
        let y = rect.minY - gap
        var half = rect.width * max(lineScale, 1) / 2 + short * 0.006
        if lineScale > 1 {
            half = min(half, max(rect.width / 2 + short * 0.02, short * 0.15))
        }
        let mid = rect.midX
        stroke(CGPoint(x: mid - half, y: y), CGPoint(x: mid + half, y: y), sample: place(spot))
    }

    private func underline(_ text: String, spot: Spot, font: UIFont, trackingEm: CGFloat) {
        guard let row = prepared(text, font: font, trackingEm: trackingEm) else { return }
        let point = place(spot)
        let drop = max(1.5, short * 0.008)
        let textPoint = CGPoint(x: point.x, y: point.y - drop)
        guard let rect = drawRuns(
            [row], at: textPoint, anchor: anchor(for: spot), valign: .bottom
        ) else { return }
        stroke(CGPoint(x: rect.minX, y: point.y), CGPoint(x: rect.maxX, y: point.y), sample: point)
    }

    private func ruleBeside(_ text: String) {
        guard let row = prepared(text, font: serif(0.030), trackingEm: 0.12) else { return }
        guard let rect = drawRuns([row], at: place(.bottomRight), anchor: .right, valign: .bottom) else { return }
        let gap = max(2, short * 0.012)
        let lift = short * 0.003
        let x = rect.minX - gap
        stroke(
            CGPoint(x: x, y: rect.minY - lift),
            CGPoint(x: x, y: rect.maxY + lift),
            sample: place(.bottomRight)
        )
    }

    private func monogram(_ letters: String, shape: Box, diameter: CGFloat) {
        let center = clamp(CGPoint(
            x: area.maxX - margin - diameter / 2 + offset.width * area.width,
            y: area.maxY - margin - diameter / 2 + offset.height * area.height
        ))
        let ink = tone(at: center)
        let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        ctx.saveGState()
        ink.color.setStroke()
        let path: UIBezierPath
        switch shape {
        case .circle:
            path = UIBezierPath(ovalIn: rect)
        case .square:
            path = UIBezierPath(rect: rect.insetBy(dx: hair, dy: hair))
        }
        path.lineWidth = hair
        path.stroke()
        ctx.restoreGState()
        let fraction = (diameter * (letters.count > 1 ? 0.34 : 0.42)) / short
        guard let row = prepared(letters, font: serif(fraction), trackingEm: letters.count > 1 ? 0.06 : 0) else { return }
        drawRuns([row], at: center, anchor: .center, valign: .center)
    }

    private func stamp(_ text: String, font: UIFont, trackingEm: CGFloat, spot: Spot, angle: CGFloat) {
        guard let row = prepared(text, font: font, trackingEm: trackingEm) else { return }
        let textSize = measured(row)
        let padX = max(4, short * 0.014)
        let padY = max(2, short * 0.008)
        let box = CGSize(width: textSize.width + padX * 2, height: textSize.height + padY * 2)
        let corner = place(spot)
        let center: CGPoint
        switch spot {
        case .bottomRight:
            center = CGPoint(x: corner.x - box.width / 2, y: corner.y - box.height / 2)
        case .bottomLeft:
            center = CGPoint(x: corner.x + box.width / 2, y: corner.y - box.height / 2)
        default:
            center = corner
        }
        let ink = tone(at: center)
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: angle)
        let rect = CGRect(x: -box.width / 2, y: -box.height / 2, width: box.width, height: box.height)
        ink.color.setStroke()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: max(1, short * 0.003))
        path.lineWidth = hair
        path.stroke()
        applyShadow(dark: ink.dark)
        let origin = CGPoint(x: -textSize.width / 2, y: -textSize.height / 2)
        (row.text as NSString).draw(at: origin, withAttributes: attributes(font: row.font, tracking: row.tracking, color: ink.color))
        ctx.restoreGState()
    }

    private func printCell() {
        guard !info.frameNumber.isEmpty else { return }
        let side = short * 0.046
        let center = clamp(CGPoint(
            x: area.maxX - margin - side / 2 + offset.width * area.width,
            y: area.maxY - margin - side / 2 + offset.height * area.height
        ))
        let ink = tone(at: center)
        let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        ctx.saveGState()
        ink.color.setStroke()
        let path = UIBezierPath(rect: rect)
        path.lineWidth = hair
        path.stroke()
        ctx.restoreGState()
        guard let row = prepared(info.frameNumber, font: mono(0.016), trackingEm: 0) else { return }
        drawRuns([row], at: center, anchor: .center, valign: .center)
    }

    private func cropMarks() {
        let length = short * 0.026
        let inset = short * 0.040
        let shift = CGSize(width: offset.width * area.width, height: offset.height * area.height)
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (clamp(CGPoint(x: area.minX + inset + shift.width, y: area.minY + inset + shift.height)), 1, 1),
            (clamp(CGPoint(x: area.maxX - inset + shift.width, y: area.minY + inset + shift.height)), -1, 1),
            (clamp(CGPoint(x: area.minX + inset + shift.width, y: area.maxY - inset + shift.height)), 1, -1),
            (clamp(CGPoint(x: area.maxX - inset + shift.width, y: area.maxY - inset + shift.height)), -1, -1),
        ]
        for (point, hx, vy) in corners {
            let inward = CGPoint(x: point.x + hx * length, y: point.y)
            let down = CGPoint(x: point.x, y: point.y + vy * length)
            stroke(point, inward, sample: point)
            stroke(point, down, sample: point)
        }
    }

    private func vertical(_ title: String, x: CGFloat, anchor: Anchor, font: UIFont) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let glyphs = Array(trimmed)
        var face = font
        var advance = face.pointSize * 1.02
        let limit = max(face.pointSize, area.height - margin * 2)
        if advance * CGFloat(glyphs.count) > limit {
            let scale = limit / (advance * CGFloat(glyphs.count))
            face = face.withSize(max(4, face.pointSize * scale))
            advance = face.pointSize * 1.02
        }
        let block = advance * CGFloat(glyphs.count)
        let shiftedX = clamp(CGPoint(x: x + offset.width * area.width, y: area.midY)).x
        var y = max(area.minY + margin, area.maxY - margin - block + offset.height * area.height)
        y = min(max(y, area.minY + margin), max(area.minY + margin, area.maxY - margin - block))
        let ink = tone(at: CGPoint(x: shiftedX, y: area.maxY - margin - short * 0.05))
        ctx.saveGState()
        applyShadow(dark: ink.dark)
        for glyph in glyphs {
            let letter = String(glyph)
            if letter != " " {
                let width = measure(letter, font: face, tracking: 0)
                let originX: CGFloat
                switch anchor {
                case .left: originX = shiftedX
                case .right: originX = shiftedX - width
                case .center: originX = shiftedX - width / 2
                }
                (letter as NSString).draw(
                    at: CGPoint(x: originX, y: y),
                    withAttributes: attributes(font: face, tracking: 0, color: ink.color)
                )
            }
            y += advance
        }
        ctx.restoreGState()
    }

    private func faintTile() {
        let font = sans(0.020, weight: .regular)
        guard let row = prepared(studio, font: font, trackingEm: 0.18) else { return }
        let step = max(28, short * 0.40)
        let center = clamp(CGPoint(
            x: area.midX + offset.width * area.width,
            y: area.midY + offset.height * area.height
        ))
        let ink = tone(at: center)
        ctx.saveGState()
        ctx.clip(to: area.insetBy(dx: margin * 0.25, dy: margin * 0.25))
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: -24 * .pi / 180)
        let attrs = attributes(font: row.font, tracking: row.tracking, color: ink.color)
        let measured = (row.text as NSString).size(withAttributes: attrs)
        var drawn = 0
        var rowIndex = 0
        var y = -area.height
        while y < area.height && drawn < 16 {
            var x = -area.width + (rowIndex % 2 == 0 ? 0 : step * 0.55)
            while x < area.width && drawn < 16 {
                let origin = CGPoint(x: x - measured.width / 2, y: y - measured.height / 2)
                (row.text as NSString).draw(at: origin, withAttributes: attrs)
                x += step * 2.2
                drawn += 1
            }
            y += step
            rowIndex += 1
        }
        ctx.restoreGState()
    }

    @discardableResult
    private func drawRuns(
        _ runs: [Run],
        at point: CGPoint,
        anchor: Anchor,
        valign: VAlign,
        gap: CGFloat = 0
    ) -> CGRect? {
        let rows = runs.filter { !$0.text.isEmpty }
        guard !rows.isEmpty else { return nil }
        let sizes = rows.map(measured)
        let total = sizes.reduce(0) { $0 + $1.height } + gap * CGFloat(max(0, rows.count - 1))
        let top: CGFloat
        switch valign {
        case .top: top = point.y
        case .center: top = point.y - total / 2
        case .bottom: top = point.y - total
        }
        let ink = tone(at: point)
        ctx.saveGState()
        applyShadow(dark: ink.dark)
        var y = top
        var minX = point.x
        var maxX = point.x
        for (row, rowSize) in zip(rows, sizes) {
            let x: CGFloat
            switch anchor {
            case .left: x = point.x
            case .center: x = point.x - rowSize.width / 2
            case .right: x = point.x - rowSize.width
            }
            minX = min(minX, x)
            maxX = max(maxX, x + rowSize.width)
            (row.text as NSString).draw(
                at: CGPoint(x: x, y: y),
                withAttributes: attributes(font: row.font, tracking: row.tracking, color: ink.color)
            )
            y += rowSize.height + gap
        }
        ctx.restoreGState()
        return CGRect(x: minX, y: top, width: max(0, maxX - minX), height: total)
    }

    private func stroke(_ start: CGPoint, _ end: CGPoint, sample: CGPoint) {
        let ink = tone(at: sample)
        ctx.saveGState()
        ink.color.setStroke()
        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: end)
        path.lineWidth = hair
        path.lineCapStyle = .butt
        path.stroke()
        ctx.restoreGState()
    }

    private func prepared(_ text: String, font: UIFont, trackingEm: CGFloat) -> Run? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fitted = fit(font, text: trimmed, tracking: font.pointSize * trackingEm)
        return Run(text: trimmed, font: fitted.font, tracking: fitted.tracking)
    }

    private func trackedLine(_ text: String, fraction: CGFloat, target: CGFloat) -> Run? {
        var font = sans(fraction, weight: .regular)
        var natural = measure(text, font: font, tracking: 0)
        var guardCount = 0
        while natural > target * 0.94 && font.pointSize > 5 && guardCount < 6 {
            font = font.withSize(font.pointSize * 0.9)
            natural = measure(text, font: font, tracking: 0)
            guardCount += 1
        }
        let gaps = CGFloat(max(text.count - 1, 1))
        var kern = (target - natural) / gaps
        kern = min(max(kern, font.pointSize * 0.08), font.pointSize * 0.46)
        return prepared(text, font: font, trackingEm: kern / max(font.pointSize, 1))
    }

    private func fit(_ font: UIFont, text: String, tracking: CGFloat) -> (font: UIFont, tracking: CGFloat) {
        let limit = max(12, area.width - margin * 2)
        var current = font
        var track = tracking
        for _ in 0..<8 {
            let width = measure(text, font: current, tracking: track)
            if width <= limit || current.pointSize <= 5 { break }
            let scale = max(0.72, min(0.92, limit / max(width, 1)))
            current = current.withSize(max(5, current.pointSize * scale))
            track *= scale
        }
        return (current, track)
    }

    private func measured(_ run: Run) -> CGSize {
        (run.text as NSString).size(withAttributes: attributes(font: run.font, tracking: run.tracking, color: .white))
    }

    private func measure(_ text: String, font: UIFont, tracking: CGFloat) -> CGFloat {
        (text as NSString).size(withAttributes: attributes(font: font, tracking: tracking, color: .white)).width
    }

    private func attributes(font: UIFont, tracking: CGFloat, color: UIColor) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: color, .kern: tracking]
    }

    private func applyShadow(dark: Bool) {
        guard !quiet, !dark else { return }
        ctx.setShadow(
            offset: CGSize(width: 0, height: max(0.25, short * 0.001)),
            blur: max(0.4, short * 0.0028),
            color: UIColor.black.withAlphaComponent(0.32).cgColor
        )
    }

    private struct Ink {
        var color: UIColor
        var dark: Bool
    }

    private func tone(at point: CGPoint) -> Ink {
        let alpha = CGFloat(min(1, max(0.04, preset.opacity)))
        let dark: Bool
        if quiet {
            dark = preset.ink == "ink"
        } else if preset.ink == "ink" {
            dark = luma(at: point) >= 0.40
        } else {
            dark = luma(at: point) >= 0.72
        }
        let color = dark
            ? UIColor(red: 0.17, green: 0.14, blue: 0.11, alpha: alpha)
            : UIColor(red: 0.99, green: 0.97, blue: 0.93, alpha: alpha)
        return Ink(color: color, dark: dark)
    }

    private func luma(at point: CGPoint) -> CGFloat {
        let key = (Int(point.x) / 8) * 20_000 + Int(point.y) / 8
        if let cached = lumaCache[key] { return cached }
        let span = max(6, short * 0.08)
        let rect = CGRect(x: point.x - span * 0.5, y: point.y - span * 0.35, width: span, height: span * 0.7)
        let value = Luma.average(backing, rect: rect)
        lumaCache[key] = value
        return value
    }

    private func serif(_ fraction: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let size = scaled(fraction)
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    private func sans(_ fraction: CGFloat, weight: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: scaled(fraction), weight: weight)
    }

    private func mono(_ fraction: CGFloat) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: scaled(fraction), weight: .regular)
    }

    private func script(_ fraction: CGFloat) -> UIFont {
        let size = scaled(fraction)
        for name in ["SnellRoundhand", "SavoyeLetPlain"] {
            if let font = UIFont(name: name, size: size) { return font }
        }
        let base = UIFont.systemFont(ofSize: size, weight: .regular)
        if let serif = base.fontDescriptor.withDesign(.serif),
           let italic = serif.withSymbolicTraits(.traitItalic) {
            return UIFont(descriptor: italic, size: size)
        }
        return base
    }

    private func scaled(_ fraction: CGFloat) -> CGFloat {
        let raw = short * fraction * CGFloat(max(0.4, preset.fontScale))
        return min(max(raw, 4), short * 0.085)
    }

    private func place(_ spot: Spot) -> CGPoint {
        let raw: CGPoint
        switch spot {
        case .topLeft: raw = CGPoint(x: area.minX + margin, y: area.minY + margin)
        case .topRight: raw = CGPoint(x: area.maxX - margin, y: area.minY + margin)
        case .bottomLeft: raw = CGPoint(x: area.minX + margin, y: area.maxY - margin)
        case .bottomRight: raw = CGPoint(x: area.maxX - margin, y: area.maxY - margin)
        case .bottomCenter: raw = CGPoint(x: area.midX, y: area.maxY - margin)
        case .center: raw = CGPoint(x: area.midX, y: area.midY)
        }
        let shifted = CGPoint(
            x: raw.x + offset.width * area.width,
            y: raw.y + offset.height * area.height
        )
        return clamp(shifted)
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        let pad = margin
        let minX = area.minX + pad
        let maxX = max(minX, area.maxX - pad)
        let minY = area.minY + pad
        let maxY = max(minY, area.maxY - pad)
        return CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, minY), maxY)
        )
    }

    private func anchor(for spot: Spot) -> Anchor {
        switch spot {
        case .topLeft, .bottomLeft: return .left
        case .topRight, .bottomRight: return .right
        case .bottomCenter, .center: return .center
        }
    }

    private func valign(for spot: Spot) -> VAlign {
        switch spot {
        case .topLeft, .topRight: return .top
        case .bottomLeft, .bottomRight, .bottomCenter: return .bottom
        case .center: return .center
        }
    }

    private func join(_ parts: [String], separator: String = "  ·  ") -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }

    private struct Run {
        var text: String
        var font: UIFont
        var tracking: CGFloat
    }

    private enum Spot { case topLeft, topRight, bottomLeft, bottomRight, bottomCenter, center }
    private enum Anchor { case left, center, right }
    private enum VAlign { case top, center, bottom }
    private enum Box { case circle, square }
}

private enum Luma {
    /// Same top-left orientation as `FramePainter.pixels8`. A full-frame
    /// downsample avoids a second transform that was reading the wrong ground.
    static func average(_ image: CGImage, rect: CGRect) -> CGFloat {
        let width = image.width
        let height = image.height
        guard width > 1, height > 1 else { return 0.5 }
        let samples = 48
        var bytes = [UInt8](repeating: 0, count: samples * samples * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return 0.5 }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(
            data: &bytes, width: samples, height: samples, bitsPerComponent: 8,
            bytesPerRow: samples * 4, space: space, bitmapInfo: info
        ) else { return 0.5 }
        ctx.translateBy(x: 0, y: CGFloat(samples))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: samples, height: samples))
        let sx = CGFloat(samples) / CGFloat(width)
        let sy = CGFloat(samples) / CGFloat(height)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let patch = rect.intersection(bounds)
        guard patch.width >= 1, patch.height >= 1 else { return 0.5 }
        let x0 = max(0, min(samples - 1, Int((patch.minX * sx).rounded(.down))))
        let x1 = max(x0, min(samples - 1, Int((patch.maxX * sx).rounded(.up))))
        let y0 = max(0, min(samples - 1, Int((patch.minY * sy).rounded(.down))))
        let y1 = max(y0, min(samples - 1, Int((patch.maxY * sy).rounded(.up))))
        var sum = 0.0
        var count = 0
        var y = y0
        while y <= y1 {
            var x = x0
            while x <= x1 {
                let index = (y * samples + x) * 4
                let alpha = Int(bytes[index + 3])
                if alpha > 8 {
                    let red = Double(bytes[index])
                    let green = Double(bytes[index + 1])
                    let blue = Double(bytes[index + 2])
                    sum += (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255.0
                    count += 1
                }
                x += 1
            }
            y += 1
        }
        guard count > 0 else { return 0.5 }
        return CGFloat(sum / Double(count))
    }
}
