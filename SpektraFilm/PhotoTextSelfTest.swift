import UIKit
import CoreText

@MainActor
enum PhotoTextSelfTest {
    static func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !value() { throw EngineError.message("text: " + message) }
    }
    // CGImage bitmap rows already match the saved PNG's top-left orientation.
    // FramePainter.pixels8 adds a vertical flip, so it is unsuitable here.
    static func topLeftPixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { storage in
            let context = CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
    static func run() async throws {
        var layer = PhotoTextLayer(text: "春日光影\nLiteFilm")
        layer.x = .nan; layer.size = .infinity
        let clean = layer.sanitized()
        try require(clean.x == 0.5 && clean.size == 0.07, "nonfinite geometry")
        try require(try JSONDecoder().decode(PhotoTextLayer.self, from: JSONEncoder().encode(clean)) == clean, "archive roundtrip")
        let old = try JSONDecoder().decode(PersistedEdit.self, from: Data("{\"schemaVersion\":6}".utf8))
        try require(old.textLayers == nil, "legacy archive")
        for font in PhotoTextFont.allCases {
            try require(font.isAvailable, "missing bundled font \(font.rawValue)")
            let face = CTFontCreateWithName(font.postScript as CFString, 20, nil)
            let chars = Array("春日光影裁剪文字".utf16)
            var glyphs = [CGGlyph](repeating: 0, count: chars.count)
            try require(CTFontGetGlyphsForCharacters(face, chars, &glyphs, chars.count), "Chinese glyph coverage")
        }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = true
        func base(_ edge: CGFloat) -> CGImage {
            UIGraphicsImageRenderer(size: CGSize(width: edge, height: edge), format: fmt).image { _ in
                UIColor.black.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: edge, height: edge))
            }.cgImage!
        }
        let card = base(400)
        let text = PhotoTextLayer(text: "春日光影 LiteFilm", x: 0.5, y: 0.25)
        let drawn = PhotoTextPainter.apply(card, layers: [text])!
        try require(SelfTest.meanLuma(drawn) > SelfTest.meanLuma(card) + 0.5, "text absent")
        let large = PhotoTextPainter.apply(base(800), layers: [text])!
        try require(abs(SelfTest.meanLuma(large) - SelfTest.meanLuma(drawn)) < 1.5, "resolution dependent layout")
        let pixels = topLeftPixels(drawn)
        var upper = 0, lower = 0
        for y in 0..<400 { for x in 0..<400 {
            let value = Int(pixels[(y * 400 + x) * 4])
            if y < 200 { upper += value } else { lower += value }
        }}
        try require(upper > 1000 && lower == 0, "text vertically inverted")
        let opening = CGRect(x: 80, y: 60, width: 240, height: 280)
        var edgeText = text; edgeText.x = 0; edgeText.y = 0; edgeText.size = 0.2
        let clipped = topLeftPixels(PhotoTextPainter.apply(card, layers: [edgeText], contentRect: opening)!)
        var inside = 0, outside = 0
        for y in 0..<400 { for x in 0..<400 {
            let value = Int(clipped[(y * 400 + x) * 4])
            if opening.contains(CGPoint(x: x, y: y)) { inside += value } else { outside += value }
        }}
        try require(inside > 1000 && outside == 0, "text escapes photo opening")
        var oversized = text; oversized.text = String(repeating: "长文字", count: 1000)
        oversized.x = -50; oversized.y = 50
        let bounded = oversized.sanitized()
        try require(bounded.text.count == 200 && bounded.x == 0 && bounded.y == 1, "input limits")
        let stack = PhotoTextLayer.sanitized(Array(repeating: text, count: 100))
        try require(stack.count == 8 && Set(stack.map(\.id)).count == 8, "layer limits/identity")
        let suite = "litefilm.text.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = LabModel(defaults: defaults)
        model.gallery = ImportGalleryStore(rootURL: root)
        await model.bootstrap(); await model.waitUntilSettled()
        model.setTextLayers([text]); await model.waitUntilSettled()
        let saved = try JSONDecoder().decode(PersistedEdit.self, from: defaults.data(forKey: "spektrafilm.edit.v1")!)
        try require(saved.textLayers == [text], "persist text")
        model.undo(); await model.waitUntilSettled()
        try require(model.textLayers.isEmpty, "undo text")
        model.setTextLayers([text]); await model.waitUntilSettled()
        model.saveCurrentLookToGallery()
        let variant = model.gallery.items.first!
        try require(variant.recipe?.textLayers == [text], "gallery save text")
        model.setTextLayers([]); await model.waitUntilSettled()
        await model.openImport(id: variant.id); await model.waitUntilSettled()
        try require(model.textLayers == [text], "gallery restore text")
        model.export(.png, includeFrame: false, includeWatermark: false)
        await model.waitUntilSettled()
        try require(model.shareURL != nil && model.errorText == nil, "export text")
        guard let url = model.shareURL, let exported = UIImage(contentsOfFile: url.path)?.cgImage,
              let expected = model.proofStill(includeFrame: false, includeWatermark: false),
              let blank = model.proofStill(includeFrame: false, includeWatermark: false, textOverride: []) else {
            throw EngineError.message("text export missing pixels")
        }
        try require(abs(SelfTest.meanLuma(exported) - SelfTest.meanLuma(expected)) < 5, "export/preview text mismatch")
        try require(SelfTest.meanLuma(expected) > SelfTest.meanLuma(blank) + 0.05, "model export path omitted text")
        await model.showSample(); await model.waitUntilSettled()
        try require(model.textLayers.isEmpty, "new photo inherited text")
        logLine("LITEFILM_TEXT_SELFTEST_OK")
    }
}
