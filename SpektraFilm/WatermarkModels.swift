import Foundation

/// One built-in watermark. `kind` selects a layout, not a recolor of the same layout.
struct WatermarkPreset: Identifiable, Hashable, Sendable {
    var id: String
    var nameZh: String
    var kind: String
    var opacity: Double
    var fontScale: Double
    var ink: String
}

/// Facts the painter may print. Empty strings are omitted. Nothing here is invented EXIF.
struct WatermarkContext: Equatable, Sendable {
    var filmName: String
    var frameName: String
    var frameCode: String
    var frameNumber: String
    var frameTotal: String
    var dateText: String

    static let blank = WatermarkContext(
        filmName: "", frameName: "", frameCode: "", frameNumber: "", frameTotal: "", dateText: ""
    )

    static func dateText(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

/// User-facing credit strings. Empty fields keep the built-in LITEFILM / LiteFilm defaults.
struct WatermarkIdentity: Equatable, Sendable {
    var displayName: String = ""
    var studioName: String = ""
    var copyrightLine: String = ""
    var monogram: String = ""
    var siteURL: String = ""

    static let blank = WatermarkIdentity()

    private static func cleaned(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Uppercase brand used by serif / tracked / vertical marks.
    var resolvedStudio: String {
        let studio = Self.cleaned(studioName)
        if !studio.isEmpty { return studio.uppercased() }
        let name = Self.cleaned(displayName)
        if !name.isEmpty { return name.uppercased() }
        return "LITEFILM"
    }

    /// Script / dual-line signature.
    var resolvedSignature: String {
        let name = Self.cleaned(displayName)
        if !name.isEmpty { return name }
        let studio = Self.cleaned(studioName)
        if !studio.isEmpty { return studio }
        return "LiteFilm"
    }

    /// One or two letters for ring / square / SF marks.
    var resolvedMonogram: String {
        let custom = Self.cleaned(monogram).filter { !$0.isWhitespace }
        if !custom.isEmpty { return String(custom.prefix(2)).uppercased() }
        let source = Self.cleaned(displayName).isEmpty ? Self.cleaned(studioName) : Self.cleaned(displayName)
        let letters = source.filter({ $0.isLetter })
        if letters.count >= 2 {
            let chars = Array(letters)
            return (String(chars[0]) + String(chars[1])).uppercased()
        }
        if let first = letters.first { return String(first).uppercased() }
        return "LF"
    }

    var resolvedInitial: String {
        let mark = resolvedMonogram
        return mark.isEmpty ? "L" : String(mark.prefix(1))
    }

    var resolvedSite: String {
        let site = Self.cleaned(siteURL)
        if !site.isEmpty { return site.uppercased() }
        return "SUPERAITEST.COM/LITEFILM"
    }

    func resolvedCopyright(year: String) -> String {
        let custom = Self.cleaned(copyrightLine)
        if !custom.isEmpty { return custom }
        return "© \(resolvedStudio) \(year)"
    }
}

struct WatermarkEditState: Codable, Equatable, Hashable, Sendable {
    var schemaVersion: Int = 2
    var enabled: Bool = false
    var activeID: String = "wm_01"
    /// 署名姓名。空则画家用 LiteFilm / LITEFILM。
    var displayName: String = ""
    /// 工作室或品牌。空则跟署名或默认 LITEFILM。
    var studioName: String = ""
    /// 整行版权。空则仍是 © {工作室} {年}。
    var copyrightLine: String = ""
    /// 花押 1–2 字。空则从姓名推，再退回 LF / L。
    var monogram: String = ""
    /// 短网址一行。空则 SUPERAITEST.COM/LITEFILM。
    var siteURL: String = ""
    /// 相对内容区宽高的归一化偏移。0 是该预设默认锚点。
    var offsetX: Double = 0
    var offsetY: Double = 0

    var identity: WatermarkIdentity {
        WatermarkIdentity(
            displayName: displayName,
            studioName: studioName,
            copyrightLine: copyrightLine,
            monogram: monogram,
            siteURL: siteURL
        )
    }

    mutating func sanitize(catalog: WatermarkCatalog) {
        if schemaVersion < 2 { schemaVersion = 2 }
        displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        studioName = studioName.trimmingCharacters(in: .whitespacesAndNewlines)
        copyrightLine = copyrightLine.trimmingCharacters(in: .whitespacesAndNewlines)
        siteURL = siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = monogram.filter { !$0.isWhitespace }
        monogram = String(letters.prefix(2))
        offsetX = min(0.48, max(-0.48, offsetX))
        offsetY = min(0.48, max(-0.48, offsetY))
        if catalog.preset(activeID) == nil {
            activeID = catalog.presets.first?.id ?? "wm_01"
            if catalog.preset(activeID) == nil { enabled = false }
        }
    }
}

struct WatermarkCatalog: Sendable {
    var presets: [WatermarkPreset]

    static let builtin = WatermarkCatalog(presets: WatermarkLibrary.presets)

    func preset(_ id: String) -> WatermarkPreset? { presets.first { $0.id == id } }

    /// 0 is 无水印. 1...count are presets in order. The list does not wrap.
    func slot(_ state: WatermarkEditState) -> Int {
        guard state.enabled, let index = presets.firstIndex(where: { $0.id == state.activeID }) else { return 0 }
        return index + 1
    }

    func step(_ state: WatermarkEditState, _ move: FrameMove) -> WatermarkEditState? {
        let forward: Bool
        switch move {
        case .nextWatermark: forward = true
        case .previousWatermark: forward = false
        default: return nil
        }
        guard !presets.isEmpty else { return nil }
        let destination = slot(state) + (forward ? 1 : -1)
        guard destination >= 0, destination <= presets.count else { return nil }
        var next = state
        if destination == 0 {
            next.enabled = false
        } else {
            next.enabled = true
            next.activeID = presets[destination - 1].id
        }
        return next == state ? nil : next
    }

    func navigationFailures() -> [String] {
        var failures: [String] = []
        guard presets.count >= 30 else { failures.append("wm-count"); return failures }
        let ids = presets.map(\.id)
        if Set(ids).count != ids.count { failures.append("wm-duplicate-id") }
        let kinds = presets.map(\.kind)
        if Set(kinds).count != kinds.count { failures.append("wm-duplicate-kind") }
        if ids.first != "wm_01" { failures.append("wm-first-id") }
        var state = WatermarkEditState()
        state.enabled = false
        if step(state, .previousWatermark) != nil { failures.append("wm-before-none") }
        var forward: [String] = []
        var guardCount = 0
        while let next = step(state, .nextWatermark), guardCount <= presets.count {
            state = next
            if state.enabled { forward.append(state.activeID) }
            guardCount += 1
        }
        if forward != ids { failures.append("wm-forward") }
        if state.enabled == false || state.activeID != ids.last || step(state, .nextWatermark) != nil {
            failures.append("wm-end")
        }
        let walkedBackFrom = state.activeID
        var reverse: [String] = []
        guardCount = 0
        while let previous = step(state, .previousWatermark), guardCount <= presets.count {
            state = previous
            if state.enabled { reverse.append(state.activeID) }
            guardCount += 1
        }
        let expectedBack = Array(ids.dropLast().reversed())
        if state.enabled || walkedBackFrom != ids.last || reverse != expectedBack {
            failures.append("wm-reverse")
        }
        return failures
    }
}

enum WatermarkLibrary {
    /// Opacity is the print, not a poster: credits sit near 0.30–0.42.
    /// `faintCenter` stays ≤ 0.22 and `faintTile` stays ≤ 0.12. Sizes live in the painter.
    static let presets: [WatermarkPreset] = [
        mark("wm_01", "右下签名", "signSerifBR", 0.36, 1.0, "ivory"),
        mark("wm_02", "手写署名", "signScriptBR", 0.42, 1.0, "ivory"),
        mark("wm_03", "© 年份", "signCopyright", 0.34, 1.0, "ivory"),
        mark("wm_04", "摄影双行", "signStudio", 0.40, 1.0, "ivory"),
        mark("wm_05", "底中字距", "signTracked", 0.32, 1.0, "ivory"),
        mark("wm_06", "左下胶片", "filmBL", 0.34, 1.0, "ivory"),
        mark("wm_07", "右下胶片", "filmBR", 0.34, 1.0, "ivory"),
        mark("wm_08", "右下日期", "dateBR", 0.32, 1.0, "ivory"),
        mark("wm_09", "细线署名", "hairlineBR", 0.38, 1.0, "ivory"),
        mark("wm_10", "胶片日期", "filmDate", 0.32, 1.0, "ivory"),
        mark("wm_11", "圆花押", "monogramRing", 0.40, 1.0, "ivory"),
        mark("wm_12", "字母花押", "monogramSF", 0.38, 1.0, "ivory"),
        mark("wm_13", "单字母", "initialS", 0.40, 1.0, "ivory"),
        mark("wm_14", "左下签名", "signSerifBL", 0.34, 1.0, "ivory"),
        mark("wm_15", "底中手写", "scriptBC", 0.40, 1.0, "ivory"),
        mark("wm_16", "姓名年份", "nameYear", 0.34, 1.0, "ivory"),
        mark("wm_17", "简址", "siteBR", 0.32, 1.0, "ivory"),
        mark("wm_18", "署名胶片", "nameFilm", 0.36, 1.0, "ivory"),
        mark("wm_19", "淡字校对", "faintCenter", 0.18, 1.0, "ivory"),
        mark("wm_20", "底线署名", "baselineBC", 0.34, 1.0, "ivory"),
        mark("wm_21", "两角小字", "cornerSplit", 0.32, 1.0, "ivory"),
        mark("wm_22", "签名日期", "scriptDate", 0.40, 1.0, "ivory"),
        mark("wm_23", "横边码", "edgeCodeH", 0.36, 1.0, "ivory"),
        mark("wm_24", "竖边码", "edgeCodeV", 0.36, 1.0, "ivory"),
        mark("wm_25", "接触印戳", "contactStamp", 0.40, 1.0, "ivory"),
        mark("wm_26", "日期小章", "dateStamp", 0.38, 1.0, "ivory"),
        mark("wm_27", "裁切标", "cropMarks", 0.36, 1.0, "ivory"),
        mark("wm_28", "侧边竖排", "sideRight", 0.32, 1.0, "ivory"),
        mark("wm_29", "淡斜校对", "faintTile", 0.11, 1.0, "ivory"),
        mark("wm_30", "画幅小字", "indexBR", 0.30, 1.0, "ivory"),
        mark("wm_31", "竖线署名", "ruleName", 0.36, 1.0, "ivory"),
        mark("wm_32", "字下细线", "underlineBC", 0.34, 1.0, "ivory"),
        mark("wm_33", "方花押", "monogramSquare", 0.38, 1.0, "ivory"),
        mark("wm_34", "墨水签名", "inkSign", 0.42, 1.0, "ink"),
        mark("wm_35", "左下双行", "studioBL", 0.38, 1.0, "ivory"),
        mark("wm_36", "印号小格", "printCell", 0.36, 1.0, "ivory"),
    ]

    private static func mark(
        _ id: String, _ name: String, _ kind: String, _ opacity: Double, _ scale: Double, _ ink: String
    ) -> WatermarkPreset {
        WatermarkPreset(id: id, nameZh: name, kind: kind, opacity: opacity, fontScale: scale, ink: ink)
    }
}
