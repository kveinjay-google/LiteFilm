import CoreGraphics
import Foundation

// Geometry matches vendor/SpektraFilm_36_Frames/native/FrameGeometry.swift.
// Insets are fractions of the original photo's shorter edge. The photo is
// always contained: extra canvas becomes mat, never a crop or stretch.

struct FrameInsets: Codable, Hashable, Sendable {
    var top: Double
    var right: Double
    var bottom: Double
    var left: Double
}

struct FramePalette: Codable, Hashable, Sendable {
    var outer: String
    var inner: String
    var accent: String
    var ink: String
}

struct FrameAnnotation: Codable, Hashable, Sendable {
    var mode: String
    var placement: String
    var text: String
}

struct FrameDetails: Codable, Hashable, Sendable {
    var sprocketCount: Int
    var railWidth: Double
    var outerLayer: Double
    var cornerSize: Double
    var deckleAmplitude: Double
    var registrationMarks: Bool
}

struct FramePreset: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var familyId: String
    var nameZh: String
    var nameEn: String
    var descriptionZh: String
    var defaultRatioId: String
    var allowedRatioIds: [String]
    var inset: FrameInsets
    var palette: FramePalette
    var structure: String
    var cornerRadius: Double
    var innerRule: Double
    var grain: Double
    var annotation: FrameAnnotation
    var details: FrameDetails
}

struct FrameFamily: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var nameZh: String
    var nameEn: String
}

struct FrameRatioOption: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var label: String
    var width: Double?
    var height: Double?
}

struct FrameCatalog: Sendable {
    var defaultFrameId: String
    var families: [FrameFamily]
    var ratioOptions: [FrameRatioOption]
    var frames: [FramePreset]

    static let empty = FrameCatalog(defaultFrameId: "gallery_01", families: [], ratioOptions: [], frames: [])

    static func load() throws -> FrameCatalog {
        guard let url = Bundle.main.url(forResource: "FrameCatalog", withExtension: "json") else {
            throw CatalogError.missingFrames
        }
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(File.self, from: data)
        return FrameCatalog(
            defaultFrameId: file.defaultFrameId,
            families: file.families,
            ratioOptions: file.ratioOptions,
            frames: file.frames
        )
    }

    func frame(_ id: String) -> FramePreset? { frames.first { $0.id == id } }
    func family(_ id: String) -> FrameFamily? { families.first { $0.id == id } }

    func frames(in familyID: String) -> [FramePreset] {
        frames.filter { $0.familyId == familyID }
    }

    func index(of id: String) -> Int? {
        frames.firstIndex { $0.id == id }
    }

    func canvasMode(ratioID: String, source: CGSize) -> FrameCanvasMode {
        switch ratioID {
        case "auto":
            return .autoExpand
        case "source":
            return .originalAspect
        default:
            guard let option = ratioOptions.first(where: { $0.id == ratioID }),
                  let width = option.width, let height = option.height, height > 0
            else { return .originalAspect }
            return .fixedAspect(width / height)
        }
    }

    /// Horizontal steps walk the catalog, then 无框. Nil means that end of the flat list.
    /// Series jumps stay on `nextFamily` / `previousFamily` for the overview. Watermarks are not frames.
    func step(_ state: FrameEditState, _ move: FrameMove) -> FrameEditState? {
        switch move {
        case .nextStyle, .previousStyle:
            return stepStyle(state, forward: move == .nextStyle)
        case .nextFamily, .previousFamily:
            return stepFamily(state, forward: move == .nextFamily)
        case .nextWatermark, .previousWatermark:
            return nil
        }
    }

    /// 0 is the first catalog frame. `frames.count` is 无框, after the last frame.
    func globalSlot(_ state: FrameEditState) -> Int {
        if !state.enabled || frames.isEmpty { return frames.count }
        return index(of: state.activeFrameId) ?? 0
    }

    /// Horizontal edges of the flat list. A series boundary is not an edge.
    func horizontalEdges(_ state: FrameEditState) -> (atStart: Bool, atEnd: Bool) {
        let slot = globalSlot(state)
        let last = frames.count
        return (slot <= 0 && last > 0, slot >= last)
    }

    /// Failures are empty when `gallery_01` reaches `archive_06` and only the two ends resist.
    func globalNavigationFailures() -> [String] {
        var failures: [String] = []
        guard frames.count >= 2, let first = frames.first?.id, let last = frames.last?.id else {
            return ["global-empty"]
        }
        var state = FrameEditState.makeDefault(catalog: self)
        state.enabled = true
        state.activeFrameId = first
        if let preset = frame(first) { state.activeFamilyId = preset.familyId }
        if horizontalEdges(state).atStart == false || horizontalEdges(state).atEnd { failures.append("global-start-edge") }
        var forward: [String] = []
        var guardCount = 0
        while state.enabled && guardCount <= frames.count {
            forward.append(state.activeFrameId)
            guard let next = step(state, .nextStyle) else { break }
            state = next
            guardCount += 1
        }
        if forward != frames.map(\.id) { failures.append("global-forward") }
        if state.enabled || !horizontalEdges(state).atEnd || horizontalEdges(state).atStart {
            failures.append("global-end-edge")
        }
        if step(state, .nextStyle) != nil { failures.append("global-past-end") }
        var reverse: [String] = []
        guardCount = 0
        while let previous = step(state, .previousStyle), guardCount <= frames.count {
            state = previous
            if state.enabled { reverse.append(state.activeFrameId) }
            guardCount += 1
        }
        if reverse != frames.map(\.id).reversed() || state.activeFrameId != first || state.enabled == false {
            failures.append("global-reverse")
        }
        if step(state, .previousStyle) != nil { failures.append("global-past-start") }
        if frames.count > 6 {
            var boundary = FrameEditState.makeDefault(catalog: self)
            let leaving = frames[5]
            boundary.enabled = true
            boundary.activeFrameId = leaving.id
            boundary.activeFamilyId = leaving.familyId
            let edges = horizontalEdges(boundary)
            if edges.atStart || edges.atEnd { failures.append("global-series-edge") }
            if step(boundary, .nextStyle)?.activeFrameId != frames[6].id { failures.append("global-cross-series") }
        }
        var parked = FrameEditState.makeDefault(catalog: self)
        parked.enabled = false
        parked.activeFrameId = first
        if step(parked, .previousStyle)?.activeFrameId != last { failures.append("global-none-previous") }
        return failures
    }

    private func stepStyle(_ state: FrameEditState, forward: Bool) -> FrameEditState? {
        guard !frames.isEmpty else { return nil }
        let destination = globalSlot(state) + (forward ? 1 : -1)
        guard destination >= 0, destination <= frames.count else { return nil }
        var next = state
        if destination == frames.count {
            next.enabled = false
            return next == state ? nil : next
        }
        let preset = frames[destination]
        next.enabled = true
        next.activeFrameId = preset.id
        next.activeFamilyId = preset.familyId
        next.lastFrameByFamily[preset.familyId] = preset.id
        return next == state ? nil : next
    }

    private func stepFamily(_ state: FrameEditState, forward: Bool) -> FrameEditState? {
        guard let index = families.firstIndex(where: { $0.id == state.activeFamilyId }) else { return nil }
        let destination = index + (forward ? 1 : -1)
        guard families.indices.contains(destination) else { return nil }
        let family = families[destination].id
        guard let style = lastStyle(in: family, state: state) else { return nil }
        var next = state
        next.enabled = true
        next.activeFamilyId = family
        next.activeFrameId = style
        next.lastFrameByFamily[family] = style
        return next == state ? nil : next
    }

    private func lastStyle(in family: String, state: FrameEditState) -> String? {
        if let remembered = state.lastFrameByFamily[family], frame(remembered) != nil {
            return remembered
        }
        return frames(in: family).first?.id
    }

    private struct File: Decodable {
        var defaultFrameId: String
        var families: [FrameFamily]
        var ratioOptions: [FrameRatioOption]
        var frames: [FramePreset]
    }
}

extension CatalogError {
    static var missingFrames: CatalogError { .missing }
}

enum FrameCanvasMode: Equatable, Sendable {
    case autoExpand
    case originalAspect
    case fixedAspect(Double)
}

struct FrameLayout: Sendable {
    var canvasWidth: CGFloat
    var canvasHeight: CGFloat
    var photo: CGRect
    var shortSide: CGFloat
    var top: CGFloat
    var right: CGFloat
    var bottom: CGFloat
    var left: CGFloat

    var minMargin: CGFloat { min(top, right, bottom, left) }
}

enum FrameGeometryError: Error {
    case invalid
}

enum FrameGeometry {
    static func layout(
        sourceWidth: Double,
        sourceHeight: Double,
        insets: FrameInsets,
        mode: FrameCanvasMode,
        longEdge: Double
    ) throws -> FrameLayout {
        guard sourceWidth.isFinite, sourceHeight.isFinite, sourceWidth > 0, sourceHeight > 0 else {
            throw FrameGeometryError.invalid
        }
        let border = [insets.top, insets.right, insets.bottom, insets.left]
        guard border.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw FrameGeometryError.invalid }
        guard longEdge.isFinite, longEdge > 0 else { throw FrameGeometryError.invalid }

        let sourceShort = min(sourceWidth, sourceHeight)
        let u = sourceWidth / sourceShort
        let v = sourceHeight / sourceShort
        let outerU = u + insets.left + insets.right
        let outerV = v + insets.top + insets.bottom
        let aspect: Double
        switch mode {
        case .autoExpand:
            aspect = outerU / outerV
        case .originalAspect:
            aspect = sourceWidth / sourceHeight
        case .fixedAspect(let requested):
            guard requested.isFinite, requested > 0 else { throw FrameGeometryError.invalid }
            aspect = requested
        }
        let canvasW = max(1, (aspect >= 1 ? longEdge : longEdge * aspect).rounded())
        let canvasH = max(1, (aspect >= 1 ? longEdge / aspect : longEdge).rounded())
        let scale = min(canvasW / outerU, canvasH / outerV)
        let extraW = max(0, canvasW - outerU * scale)
        let extraH = max(0, canvasH - outerV * scale)
        let photoX = insets.left * scale + extraW / 2
        let photoY = insets.top * scale + extraH / 2
        let photoW = u * scale
        let photoH = v * scale
        return FrameLayout(
            canvasWidth: CGFloat(canvasW),
            canvasHeight: CGFloat(canvasH),
            photo: CGRect(x: photoX, y: photoY, width: photoW, height: photoH),
            shortSide: CGFloat(scale),
            top: CGFloat(photoY),
            right: CGFloat(canvasW - photoX - photoW),
            bottom: CGFloat(canvasH - photoY - photoH),
            left: CGFloat(photoX)
        )
    }
}

struct FrameRatioState: Codable, Equatable, Hashable, Sendable {
    var mode: String
    var ratioId: String
}

struct FrameEditState: Codable, Equatable, Hashable, Sendable {
    var schemaVersion: Int = 1
    var enabled: Bool = true
    var activeFrameId: String = "gallery_01"
    var activeFamilyId: String = "gallery"
    var lastFrameByFamily: [String: String] = [
        "gallery": "gallery_01",
        "darkroom": "darkroom_01",
        "film": "film_01",
        "instant": "instant_01",
        "editorial": "editorial_01",
        "archive": "archive_01",
    ]
    var ratio: FrameRatioState = FrameRatioState(mode: "locked", ratioId: "source")
    var favoriteFrameIds: [String] = []

    static func makeDefault(catalog: FrameCatalog) -> FrameEditState {
        var state = FrameEditState()
        var last: [String: String] = [:]
        for family in catalog.families {
            if let first = catalog.frames(in: family.id).first {
                last[family.id] = first.id
            }
        }
        if !last.isEmpty { state.lastFrameByFamily = last }
        if let preset = catalog.frame(catalog.defaultFrameId) ?? catalog.frames.first {
            state.activeFrameId = preset.id
            state.activeFamilyId = preset.familyId
            state.lastFrameByFamily[preset.familyId] = preset.id
        }
        state.enabled = true
        state.ratio = FrameRatioState(mode: "locked", ratioId: "source")
        state.sanitize(catalog: catalog)
        return state
    }

    mutating func sanitize(catalog: FrameCatalog) {
        if catalog.frame(activeFrameId) == nil {
            activeFrameId = catalog.defaultFrameId
        }
        if catalog.frame(activeFrameId) == nil {
            activeFrameId = catalog.frames.first?.id ?? "gallery_01"
        }
        if let preset = catalog.frame(activeFrameId) {
            activeFamilyId = preset.familyId
        } else if catalog.family(activeFamilyId) == nil {
            activeFamilyId = catalog.families.first?.id ?? "gallery"
        }
        var last = lastFrameByFamily
        for family in catalog.families {
            if let remembered = last[family.id], catalog.frame(remembered) != nil { continue }
            last[family.id] = catalog.frames(in: family.id).first?.id ?? activeFrameId
        }
        lastFrameByFamily = last
        if ratio.mode != "locked" && ratio.mode != "followFrame" {
            ratio.mode = "locked"
        }
        if !catalog.ratioOptions.contains(where: { $0.id == ratio.ratioId }) {
            ratio.ratioId = "source"
        }
        let known = Set(catalog.frames.map(\.id))
        favoriteFrameIds = favoriteFrameIds.filter { known.contains($0) }
    }
}

enum FrameMove: String, Equatable, Sendable {
    case previousStyle
    case nextStyle
    case previousFamily
    case nextFamily
    case previousWatermark
    case nextWatermark
}

struct PersistedEdit: Codable {
    var schemaVersion: Int?
    var filmID: String?
    var paperID: String?
    var exposureEV: Double?
    var frame: FrameEditState?
    var watermark: WatermarkEditState?
    var exportIncludeFrame: Bool?
    var exportIncludeWatermark: Bool?
    /// Missing on older archives. The reader treats that as cross-dissolve.
    var previewTransition: String?
    /// Sandbox gallery id for the last imported working photo. Nil / missing = color chart.
    var sourceImportID: String?
    var adjustments: PhotoAdjustments?
}

/// One preference for both horizontal frame changes and vertical watermark changes.
enum PreviewTransition: String, CaseIterable, Hashable, Sendable {
    case instant
    case dissolve
    case pageTurn
    case slideFade
    case settle

    static let settingsOrder: [PreviewTransition] = [
        .instant, .dissolve, .pageTurn, .slideFade, .settle
    ]

    static func resolve(_ raw: String?) -> PreviewTransition {
        guard let raw, let value = PreviewTransition(rawValue: raw) else { return .dissolve }
        return value
    }

    /// Reduce Motion plays as an instant cut. The stored choice is left alone.
    func played(reduceMotion: Bool) -> PreviewTransition {
        reduceMotion ? .instant : self
    }

    var title: String {
        switch self {
        case .instant: return "直接变化"
        case .dissolve: return "渐隐渐显"
        case .pageTurn: return "翻页"
        case .slideFade: return "轻推"
        case .settle: return "轻放"
        }
    }

    var detail: String {
        switch self {
        case .instant:
            return "松手后马上换上，中间没有动画。"
        case .dissolve:
            return "画面留在原地，当前一张淡出，下一张淡入。"
        case .pageTurn:
            return "左右换相框时沿书脊翻转，上下换水印时轻推淡入。"
        case .slideFade:
            return "两张交叠，只顺着滑动方向挪开很短一截。"
        case .settle:
            return "淡入的同时，从略小的尺寸回到原来的大小。"
        }
    }

    static func preferenceFailures() -> [String] {
        var failures: [String] = []
        if resolve(nil) != .dissolve { failures.append("nil-default") }
        if resolve("") != .dissolve { failures.append("empty-default") }
        if resolve("nope") != .dissolve { failures.append("unknown-default") }
        if resolve("instant") != .instant { failures.append("instant") }
        if resolve("pageTurn") != .pageTurn { failures.append("page") }
        if dissolve.played(reduceMotion: true) != .instant { failures.append("reduce") }
        if pageTurn.played(reduceMotion: false) != .pageTurn { failures.append("keep-page") }
        if instant.played(reduceMotion: false) != .instant { failures.append("keep-instant") }
        let still = PreviewMotion.dragAlpha(distance: 0, animated: true)
        let moved = PreviewMotion.dragAlpha(distance: 180, animated: true)
        let frozen = PreviewMotion.dragAlpha(distance: 180, animated: false)
        if still != 1 || frozen != 1 || !(moved < 0.9 && moved >= 0.7) {
            failures.append("drag-alpha")
        }
        if PreviewMotion.dragTranslation != .zero {
            failures.append("drag-moves")
        }
        return failures
    }
}

/// How a finger on the print is allowed to look. Position stays put.
enum PreviewMotion {
    static var dragTranslation: CGSize { .zero }

    static func dragAlpha(distance: CGFloat, animated: Bool) -> CGFloat {
        guard animated else { return 1 }
        let start: CGFloat = 8
        guard distance > start else { return 1 }
        let t = min(1, (distance - start) / 240)
        return 1 - 0.26 * t
    }
}

/// Bumped when a frame or watermark gesture actually changes the mat.
struct PreviewSwap: Equatable, Sendable {
    var token: Int = 0
    var move: FrameMove?
}

enum FrameAxis {
    case horizontal
    case vertical
}

/// Direction lock for one finger. `reset()` clears the axis, the ambiguous flag,
/// the back-edge ignore, and the one-shot commit so the next gesture can begin immediately.
struct FrameGestureDecider {
    private(set) var axis: FrameAxis?
    private(set) var ambiguous = false
    private(set) var ignored = false
    private(set) var committed = false
    private var decided = false

    /// Commit once the finger has travelled this far on the locked axis.
    /// Starting point in STATE_AND_GESTURES was 40pt; 32pt is the on-device relaxation.
    static let commitDistance: CGFloat = 32
    /// A flick still needs this much real travel, so a tap cannot change frames.
    static let flickMinimum: CGFloat = 18
    /// How far the predicted end must lead the finger before a short swipe counts.
    static let flickLead: CGFloat = 130

    mutating func reset() {
        axis = nil
        ambiguous = false
        ignored = false
        decided = false
        committed = false
    }

    mutating func begin(startX: CGFloat, frameGesture: Bool) {
        reset()
        ignored = frameGesture && startX < 28
    }

    mutating func update(translation: CGSize, atStart: Bool, atEnd: Bool) -> CGSize {
        if ignored { return .zero }
        let dx = abs(translation.width)
        let dy = abs(translation.height)
        if !decided {
            let travel = max(dx, dy)
            if travel < 11 { return .zero }
            if dx >= dy * 1.3 {
                axis = .horizontal
                decided = true
            } else if dy >= dx * 1.3 {
                axis = .vertical
                decided = true
            } else {
                ambiguous = true
                decided = true
            }
        }
        if ambiguous {
            return CGSize(width: translation.width * 0.12, height: translation.height * 0.12)
        }
        switch axis {
        case .horizontal:
            let bound = translation.width < 0 ? atEnd : atStart
            return CGSize(width: resist(translation.width, bound: bound), height: 0)
        case .vertical:
            let bound = translation.height < 0 ? atEnd : atStart
            return CGSize(width: 0, height: resist(translation.height, bound: bound))
        case nil:
            return .zero
        }
    }

    /// `predicted` is where the finger would land if it kept its speed briefly.
    /// Forward is negative translation: left goes to the next frame, up to the next watermark.
    /// The first call consumes the gesture. A second call returns nil until `reset()`.
    mutating func end(translation: CGSize, predicted: CGSize, atStart: Bool, atEnd: Bool) -> FrameMove? {
        if committed { return nil }
        committed = true
        if ignored || ambiguous || axis == nil { return nil }
        let travel: CGFloat
        let delta: CGFloat
        switch axis {
        case .horizontal:
            travel = translation.width
            delta = predicted.width - translation.width
        case .vertical:
            travel = translation.height
            delta = predicted.height - translation.height
        case nil:
            return nil
        }
        let flick = abs(delta) > Self.flickLead && abs(travel) >= Self.flickMinimum
        guard abs(travel) >= Self.commitDistance || flick else { return nil }
        let forward = travel < 0
        if forward && atEnd { return nil }
        if !forward && atStart { return nil }
        switch axis {
        case .horizontal:
            return forward ? .nextStyle : .previousStyle
        case .vertical:
            return forward ? .nextWatermark : .previousWatermark
        case nil:
            return nil
        }
    }

    private func resist(_ travel: CGFloat, bound: Bool) -> CGFloat {
        guard bound else { return travel }
        let sign: CGFloat = travel < 0 ? -1 : 1
        let magnitude = abs(travel)
        return sign * min(magnitude * 0.22 / (1 + magnitude / 90), 28)
    }

    static func selfCheck() -> [String] {
        var failures: [String] = []
        func check(_ name: String, _ condition: Bool) {
            if !condition { failures.append(name) }
        }

        var straight = FrameGestureDecider()
        straight.begin(startX: 80, frameGesture: true)
        _ = straight.update(translation: CGSize(width: -50, height: -4), atStart: false, atEnd: false)
        check("left-next", straight.end(
            translation: CGSize(width: -50, height: -4),
            predicted: CGSize(width: -50, height: -4),
            atStart: false,
            atEnd: false
        ) == .nextStyle)

        var back = FrameGestureDecider()
        back.begin(startX: 80, frameGesture: true)
        _ = back.update(translation: CGSize(width: 52, height: 6), atStart: false, atEnd: false)
        check("right-previous", back.end(
            translation: CGSize(width: 52, height: 6),
            predicted: CGSize(width: 52, height: 6),
            atStart: false,
            atEnd: false
        ) == .previousStyle)

        var up = FrameGestureDecider()
        up.begin(startX: 80, frameGesture: true)
        _ = up.update(translation: CGSize(width: 3, height: -48), atStart: false, atEnd: false)
        check("up-next-watermark", up.end(
            translation: CGSize(width: 3, height: -48),
            predicted: CGSize(width: 3, height: -48),
            atStart: false,
            atEnd: false
        ) == .nextWatermark)

        var down = FrameGestureDecider()
        down.begin(startX: 80, frameGesture: true)
        _ = down.update(translation: CGSize(width: -2, height: 46), atStart: false, atEnd: false)
        check("down-previous-watermark", down.end(
            translation: CGSize(width: -2, height: 46),
            predicted: CGSize(width: -2, height: 46),
            atStart: false,
            atEnd: false
        ) == .previousWatermark)

        var diagonal = FrameGestureDecider()
        diagonal.begin(startX: 80, frameGesture: true)
        _ = diagonal.update(translation: CGSize(width: 36, height: 34), atStart: false, atEnd: false)
        check("diagonal-nil", diagonal.ambiguous && diagonal.end(
            translation: CGSize(width: 36, height: 34),
            predicted: CGSize(width: 80, height: 70),
            atStart: false,
            atEnd: false
        ) == nil)

        var tiny = FrameGestureDecider()
        tiny.begin(startX: 80, frameGesture: true)
        _ = tiny.update(translation: CGSize(width: -16, height: 1), atStart: false, atEnd: false)
        check("below-threshold", tiny.end(
            translation: CGSize(width: -16, height: 1),
            predicted: CGSize(width: -16, height: 1),
            atStart: false,
            atEnd: false
        ) == nil)

        var flick = FrameGestureDecider()
        flick.begin(startX: 80, frameGesture: true)
        _ = flick.update(translation: CGSize(width: -20, height: 1), atStart: false, atEnd: false)
        check("flick-min-travel", flick.end(
            translation: CGSize(width: -20, height: 1),
            predicted: CGSize(width: -220, height: 1),
            atStart: false,
            atEnd: false
        ) == .nextStyle)

        var tooShort = FrameGestureDecider()
        tooShort.begin(startX: 80, frameGesture: true)
        _ = tooShort.update(translation: CGSize(width: -12, height: 0), atStart: false, atEnd: false)
        check("flick-needs-18", tooShort.end(
            translation: CGSize(width: -12, height: 0),
            predicted: CGSize(width: -400, height: 0),
            atStart: false,
            atEnd: false
        ) == nil)

        var edge = FrameGestureDecider()
        edge.begin(startX: 8, frameGesture: true)
        _ = edge.update(translation: CGSize(width: -80, height: 0), atStart: false, atEnd: false)
        check("back-edge", edge.ignored && edge.end(
            translation: CGSize(width: -80, height: 0),
            predicted: CGSize(width: -80, height: 0),
            atStart: false,
            atEnd: false
        ) == nil)

        var bound = FrameGestureDecider()
        bound.begin(startX: 80, frameGesture: true)
        _ = bound.update(translation: CGSize(width: -70, height: 0), atStart: false, atEnd: true)
        check("boundary", bound.end(
            translation: CGSize(width: -70, height: 0),
            predicted: CGSize(width: -70, height: 0),
            atStart: false,
            atEnd: true
        ) == nil)

        var nearRatio = FrameGestureDecider()
        nearRatio.begin(startX: 100, frameGesture: true)
        _ = nearRatio.update(translation: CGSize(width: 40, height: 20), atStart: false, atEnd: false)
        check("axis-1.3", nearRatio.axis == .horizontal && !nearRatio.ambiguous)

        var atCommit = FrameGestureDecider()
        atCommit.begin(startX: 80, frameGesture: true)
        _ = atCommit.update(translation: CGSize(width: -32, height: 2), atStart: false, atEnd: false)
        check("commit-32", atCommit.end(
            translation: CGSize(width: -32, height: 2),
            predicted: CGSize(width: -32, height: 2),
            atStart: false,
            atEnd: false
        ) == .nextStyle)

        var underCommit = FrameGestureDecider()
        underCommit.begin(startX: 80, frameGesture: true)
        _ = underCommit.update(translation: CGSize(width: -26, height: 1), atStart: false, atEnd: false)
        check("under-32", underCommit.end(
            translation: CGSize(width: -26, height: 1),
            predicted: CGSize(width: -26, height: 1),
            atStart: false,
            atEnd: false
        ) == nil)

        var twice = FrameGestureDecider()
        twice.begin(startX: 80, frameGesture: true)
        _ = twice.update(translation: CGSize(width: -48, height: 0), atStart: false, atEnd: false)
        let first = twice.end(
            translation: CGSize(width: -48, height: 0),
            predicted: CGSize(width: -48, height: 0),
            atStart: false,
            atEnd: false
        )
        let second = twice.end(
            translation: CGSize(width: -48, height: 0),
            predicted: CGSize(width: -48, height: 0),
            atStart: false,
            atEnd: false
        )
        check("one-commit", first == .nextStyle && second == nil && twice.committed)

        return failures
    }

    /// Fresh deciders stand in for the recognizer after each ended / cancelled / failed reset.
    static func sequenceCheck() -> (failures: [String], commits: Int, resets: Int) {
        var failures: [String] = []
        var commits = 0
        var resets = 0

        func swipe(_ width: CGFloat, atEnd: Bool = false) -> FrameMove? {
            var decider = FrameGestureDecider()
            decider.begin(startX: 120, frameGesture: true)
            let translation = CGSize(width: width, height: 2)
            _ = decider.update(translation: translation, atStart: false, atEnd: atEnd)
            return decider.end(translation: translation, predicted: translation, atStart: false, atEnd: atEnd)
        }

        let script: [(CGFloat, FrameMove)] = [
            (-48, .nextStyle),
            (52, .previousStyle),
            (-40, .nextStyle),
            (-36, .nextStyle),
            (44, .previousStyle),
            (-60, .nextStyle),
        ]
        for (travel, want) in script {
            let move = swipe(travel)
            if move == want {
                commits += 1
            } else {
                failures.append("seq-\(travel)")
            }
        }

        if swipe(-70, atEnd: true) != nil {
            failures.append("seq-boundary")
        }
        resets += 1
        if swipe(-46) == .nextStyle {
            commits += 1
        } else {
            failures.append("seq-after-boundary")
        }

        var cancelled = FrameGestureDecider()
        cancelled.begin(startX: 90, frameGesture: true)
        _ = cancelled.update(translation: CGSize(width: -24, height: 0), atStart: false, atEnd: false)
        cancelled.reset()
        resets += 1
        if cancelled.axis != nil || cancelled.committed || cancelled.decided {
            failures.append("seq-cancel-flags")
        }
        cancelled.begin(startX: 90, frameGesture: true)
        _ = cancelled.update(translation: CGSize(width: 42, height: 1), atStart: false, atEnd: false)
        if cancelled.end(
            translation: CGSize(width: 42, height: 1),
            predicted: CGSize(width: 42, height: 1),
            atStart: false,
            atEnd: false
        ) == .previousStyle {
            commits += 1
        } else {
            failures.append("seq-after-cancel")
        }

        return (failures, commits, resets)
    }
}
