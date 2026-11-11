import SwiftUI
import UIKit

struct PrintViewport: View {
    @ObservedObject var model: LabModel
    var onOpenFrames: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var badgeBright = true
    @State private var badgePulse = 0
    @State private var markBright = true
    @State private var markPulse = 0
    @State private var watermarkDragging = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Ink.void)
            FrameStage(
                image: model.preview,
                zoom: zoom,
                pan: pan,
                reduceMotion: reduceMotion,
                transition: model.previewTransition,
                swap: model.previewSwap,
                watermarkEnabled: model.watermark.enabled,
                watermarkOffset: CGSize(width: model.watermark.offsetX, height: model.watermark.offsetY),
                contentRectProvider: { imageSize in
                    if let rect = model.currentPreviewContentRect(), rect.width > 1, rect.height > 1 {
                        return rect
                    }
                    return CGRect(origin: .zero, size: imageSize)
                },
                canMove: { model.canMove($0) },
                onZoom: { zoom = $0 },
                onPan: { pan = $0 },
                onCommit: { move in
                    switch move {
                    case .nextWatermark, .previousWatermark:
                        markPulse += 1
                        markBright = true
                    default:
                        badgePulse += 1
                        badgeBright = true
                    }
                    let before = model.previewSwap.token
                    model.commitMove(move)
                    return model.previewSwap.token != before
                },
                onWatermarkDragBegan: {
                    watermarkDragging = true
                    model.beginWatermarkDrag()
                    markBright = true
                    markPulse += 1
                },
                onWatermarkDragChanged: { x, y in
                    model.updateWatermarkDrag(offsetX: x, offsetY: y)
                },
                onWatermarkDragEnded: {
                    watermarkDragging = false
                    model.endWatermarkDrag()
                },
                onSaveLook: {
                    model.saveCurrentLookToGallery()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.preview == nil && model.errorText == nil {
                VStack(spacing: 12) {
                    ProgressView().tint(Ink.amber)
                    Text(model.status)
                        .font(.footnote)
                        .foregroundStyle(Ink.mute)
                }
                .allowsHitTesting(false)
            }

            if model.busy, model.preview != nil {
                VStack {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(Ink.ivory)
                        Text(model.status)
                            .font(.caption)
                            .foregroundStyle(Ink.ivory)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.top, 12)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "下一款相框") { model.commitMove(.nextStyle) }
        .accessibilityAction(named: "上一款相框") { model.commitMove(.previousStyle) }
        .accessibilityAction(named: "下一个水印") { model.commitMove(.nextWatermark) }
        .accessibilityAction(named: "上一个水印") { model.commitMove(.previousWatermark) }
    }

    private var watermarkBadge: some View {
        Text(model.watermarkBadge)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Ink.ivory)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Ink.hairline, lineWidth: 1))
            .opacity(markBright ? 1 : 0.42)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: markBright)
            .allowsHitTesting(false)
            .accessibilityLabel("水印 \(model.watermarkBadge)")
    }

    private var badge: some View {
        FrameScrubber(model: model, onOpenFrames: onOpenFrames, bright: badgeBright)
            .opacity(badgeBright ? 1 : 0.72)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: badgeBright)
    }
}

/// Horizontal flick strip under the preview — catalog order + 无框, with selection haptics.
private struct FrameScrubEntry: Identifiable, Hashable {
    static let noneID = "__frame_none__"
    let id: String
    let title: String
    let isNone: Bool
}

private struct FrameScrubber: View {
    @ObservedObject var model: LabModel
    var onOpenFrames: () -> Void
    var bright: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: String?
    @State private var tick = 0
    @State private var adjusting = false

    private let cellWidth: CGFloat = 96
    private let rowHeight: CGFloat = 28
    private let stripHeight: CGFloat = 34

    private var entries: [FrameScrubEntry] {
        var list: [FrameScrubEntry] = []
        for preset in model.frameCatalog.frames {
            list.append(
                FrameScrubEntry(
                    id: preset.id,
                    title: preset.nameZh,
                    isNone: false
                )
            )
        }
        list.append(
            FrameScrubEntry(
                id: FrameScrubEntry.noneID,
                title: "无框",
                isNone: true
            )
        )
        return list
    }

    private var selectedID: String {
        if model.frame.enabled {
            return model.frame.activeFrameId
        }
        return FrameScrubEntry.noneID
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpenFrames) {
                Image(systemName: "rectangle.inset.filled")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.ivory)
                    .frame(width: 30, height: 30)
                    .background(Color.black.opacity(0.45), in: Circle())
                    .overlay(Circle().stroke(Ink.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开相框列表")
            .accessibilityHint("查看 36 款相框和比例")

            GeometryReader { geo in
                ZStack {
                    scrubScroll(width: geo.size.width)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Ink.amber.opacity(0.14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Ink.amber.opacity(0.88), lineWidth: 1.2)
                        }
                        .frame(width: cellWidth - 4, height: rowHeight)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: stripHeight)
            .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Ink.hairline, lineWidth: 1)
            }
            .sensoryFeedback(.selection, trigger: tick)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Ink.hairline, lineWidth: 1)
        )
        .padding(.horizontal, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("相框 \(model.frameBadge)")
        .accessibilityHint("左右滑动切换相框，点左侧按钮打开列表")
    }

    private func scrubScroll(width: CGFloat) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(entries) { entry in
                    cell(entry)
                        .frame(width: cellWidth, height: rowHeight)
                        .id(entry.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: $position, anchor: .center)
        .contentMargins(.horizontal, max(0, (width - cellWidth) / 2), for: .scrollContent)
        .frame(height: stripHeight)
        .mask {
            LinearGradient(
                colors: [.clear, .black, .black, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .task(id: entries.count) {
            guard !entries.isEmpty else { return }
            let target = entries.contains(where: { $0.id == selectedID }) ? selectedID : entries[0].id
            if position != target {
                position = target
            }
        }
        .onChange(of: selectedID) { _, id in
            guard entries.contains(where: { $0.id == id }), position != id else { return }
            adjusting = true
            if reduceMotion {
                position = id
            } else {
                withAnimation(.snappy(duration: 0.32)) {
                    position = id
                }
            }
        }
        .onChange(of: position) { old, id in
            guard let id else { return }
            if adjusting {
                if id == selectedID { adjusting = false }
                return
            }
            guard let old, old != id, entries.contains(where: { $0.id == id }) else { return }
            tick &+= 1
            applySelection(id)
        }
        .accessibilityAdjustableAction { direction in
            nudge(direction)
        }
    }

    private func cell(_ entry: FrameScrubEntry) -> some View {
        let selected = entry.id == (position ?? selectedID)
        return Text(entry.title)
            .font(.system(size: 12, weight: selected ? .semibold : .medium, design: .default))
            .foregroundStyle(selected ? Ink.ivory : Ink.mute)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .opacity(bright ? 1 : 0.85)
    }

    private func applySelection(_ id: String) {
        if id == FrameScrubEntry.noneID {
            if model.frame.enabled {
                model.chooseNoFrame()
            }
            return
        }
        if !model.frame.enabled || model.frame.activeFrameId != id {
            model.chooseFrame(id)
        }
    }

    private func nudge(_ direction: AccessibilityAdjustmentDirection) {
        guard let current = entries.firstIndex(where: { $0.id == (position ?? selectedID) }) else { return }
        let next = direction == .increment ? current + 1 : current - 1
        guard entries.indices.contains(next) else { return }
        let id = entries[next].id
        if reduceMotion {
            position = id
        } else {
            withAnimation(.snappy(duration: 0.2)) {
                position = id
            }
        }
    }
}

struct FrameGallerySheet: View {
    @ObservedObject var model: LabModel
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ratioBlock
                    Button {
                        model.chooseNoFrame()
                        dismiss()
                    } label: {
                        HStack {
                            Text("无框")
                                .font(.system(.body, design: .default))
                            Spacer()
                            if !model.frame.enabled {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Ink.amber)
                            }
                        }
                        .foregroundStyle(Ink.ivory)
                        .padding(14)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("无框")

                    ForEach(model.frameCatalog.families) { family in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(family.nameZh)
                                .font(.caption.weight(.semibold))
                                .tracking(1.2)
                                .foregroundStyle(Ink.mute)
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(model.frameCatalog.frames(in: family.id)) { preset in
                                    cell(preset)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Ink.void)
            .navigationTitle("相框")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(Ink.mute)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var ratioBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("比例")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Ink.mute)
            HStack(spacing: 8) {
                modeButton("锁定比例", selected: model.frame.ratio.mode == "locked") {
                    model.lockRatio(model.frame.ratio.ratioId)
                }
                modeButton("随相框", selected: model.frame.ratio.mode == "followFrame") {
                    model.followFrameRatio()
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.frameCatalog.ratioOptions) { option in
                        let allowed = ratioAllowed(option.id)
                        let selected = model.frame.ratio.mode == "locked" && model.frame.ratio.ratioId == option.id
                        Button {
                            model.lockRatio(option.id)
                        } label: {
                            Text(option.label)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .frame(minHeight: 36)
                                .foregroundStyle(selected ? Color(red: 0.12, green: 0.09, blue: 0.06) : Ink.ivory)
                                .background(selected ? Ink.amber : Color.white.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!allowed)
                        .opacity(allowed ? 1 : 0.35)
                    }
                }
            }
            Text(ratioCaption)
                .font(.caption2)
                .foregroundStyle(Ink.mute)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ratioCaption: String {
        if model.frame.ratio.mode == "followFrame" {
            let name = model.frameCatalog.ratioOptions.first { $0.id == model.resolvedRatioID }?.label ?? model.resolvedRatioID
            return "换框时改用该款推荐比例。当前是\(name)。照片始终完整显示。"
        }
        return "锁定后换框不改画布比例。原图比例即输出与照片同宽高比；按相框扩边则沿边距向外展开。"
    }

    private func ratioAllowed(_ id: String) -> Bool {
        guard model.frame.enabled, let preset = model.frameCatalog.frame(model.frame.activeFrameId) else { return true }
        return preset.allowedRatioIds.contains(id)
    }

    private func modeButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 36)
                .foregroundStyle(selected ? Color(red: 0.12, green: 0.09, blue: 0.06) : Ink.ivory)
                .background(selected ? Ink.amber : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func cell(_ preset: FramePreset) -> some View {
        let selected = model.frame.enabled && model.frame.activeFrameId == preset.id
        let number = (model.frameCatalog.index(of: preset.id) ?? 0) + 1
        return Button {
            model.chooseFrame(preset.id)
            dismiss()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(uiColor: UIColor(frameHex: preset.palette.outer)))
                    if let image = model.thumbs[preset.id] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(4)
                    }
                }
                .frame(height: 108)
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Ink.amber, lineWidth: 2)
                    }
                }
                Text(preset.nameZh)
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(Ink.ivory)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(String(format: "%02d", number))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Ink.mute)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.nameZh)，\(preset.descriptionZh)")
    }
}

/// The preview image lives in UIKit. A drag never translates it.
/// Opacity hints at the direction; the chosen transition plays when `image` changes.
private struct FrameStage: UIViewRepresentable {
    var image: UIImage?
    var zoom: CGFloat
    var pan: CGSize
    var reduceMotion: Bool
    var transition: PreviewTransition
    var swap: PreviewSwap
    var watermarkEnabled: Bool
    var watermarkOffset: CGSize
    var contentRectProvider: (CGSize) -> CGRect
    var canMove: (FrameMove) -> Bool
    var onZoom: (CGFloat) -> Void
    var onPan: (CGSize) -> Void
    var onCommit: (FrameMove) -> Bool
    var onWatermarkDragBegan: () -> Void
    var onWatermarkDragChanged: (Double, Double) -> Void
    var onWatermarkDragEnded: () -> Void
    var onSaveLook: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> StageView {
        let view = StageView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.panned(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinched(_:)))
        pinch.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped))
        tap.numberOfTapsRequired = 2
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.watermarkLongPressed(_:))
        )
        longPress.minimumPressDuration = 0.38
        longPress.allowableMovement = 24
        longPress.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(longPress)
        context.coordinator.panRecognizer = pan
        context.coordinator.pinchRecognizer = pinch
        context.coordinator.longPressRecognizer = longPress
        context.coordinator.stage = view
        return view
    }

    func updateUIView(_ view: StageView, context: Context) {
        let coordinator = context.coordinator
        coordinator.reduceMotion = reduceMotion
        coordinator.transition = transition
        coordinator.watermarkEnabled = watermarkEnabled
        coordinator.watermarkOffset = watermarkOffset
        coordinator.contentRectProvider = contentRectProvider
        coordinator.canMove = canMove
        coordinator.onZoom = onZoom
        coordinator.onPan = onPan
        coordinator.onCommit = onCommit
        coordinator.onWatermarkDragBegan = onWatermarkDragBegan
        coordinator.onWatermarkDragChanged = onWatermarkDragChanged
        coordinator.onWatermarkDragEnded = onWatermarkDragEnded
        coordinator.onSaveLook = onSaveLook
        coordinator.stage = view
        if swap.token != coordinator.seenSwap {
            coordinator.seenSwap = swap.token
            if let move = swap.move {
                coordinator.armedMove = move
                if !coordinator.awaitingSwap {
                    coordinator.awaitingSwap = true
                    coordinator.armTimeout()
                }
            }
        }
        if !sameImage(coordinator.shown, image) {
            let previous = coordinator.shown
            coordinator.shown = image
            let move = coordinator.armedMove
            let animate = coordinator.awaitingSwap && !coordinator.tracking && previous != nil
            if animate {
                coordinator.swapImage(on: view, to: image, move: move)
            } else if coordinator.tracking {
                view.imageView.image = image
                coordinator.awaitingSwap = false
            } else {
                view.imageView.layer.removeAllAnimations()
                view.imageView.image = image
                coordinator.awaitingSwap = false
                coordinator.alpha = 1
                coordinator.settling = false
                coordinator.apply(on: view, animated: false)
            }
        }
        if !coordinator.tracking && !coordinator.settling && !coordinator.awaitingSwap {
            coordinator.zoom = zoom
            coordinator.pan = pan
            coordinator.apply(on: view, animated: false)
        }
    }

    final class StageView: UIView {
        let imageView = UIImageView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            imageView.contentMode = .scaleAspectFit
            imageView.isUserInteractionEnabled = false
            imageView.layer.shadowColor = UIColor.black.cgColor
            imageView.layer.shadowOpacity = 0
            imageView.layer.shadowRadius = 18
            imageView.layer.shadowOffset = CGSize(width: 0, height: 8)
            addSubview(imageView)
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            let inset = bounds
            imageView.bounds = CGRect(origin: .zero, size: inset.size)
            imageView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var zoom: CGFloat = 1
        var pan: CGSize = .zero
        var reduceMotion = false
        var transition: PreviewTransition = .dissolve
        var watermarkEnabled = false
        var watermarkOffset: CGSize = .zero
        var contentRectProvider: (CGSize) -> CGRect = { CGRect(origin: .zero, size: $0) }
        var canMove: (FrameMove) -> Bool = { _ in false }
        var onZoom: (CGFloat) -> Void = { _ in }
        var onPan: (CGSize) -> Void = { _ in }
        var onCommit: (FrameMove) -> Bool = { _ in false }
        var onWatermarkDragBegan: () -> Void = {}
        var onWatermarkDragChanged: (Double, Double) -> Void = { _, _ in }
        var onWatermarkDragEnded: () -> Void = {}
        var onSaveLook: () -> Void = {}
        weak var stage: StageView?
        weak var panRecognizer: UIPanGestureRecognizer?
        weak var pinchRecognizer: UIPinchGestureRecognizer?
        weak var longPressRecognizer: UILongPressGestureRecognizer?
        var shown: UIImage?
        var tracking = false
        var settling = false
        var awaitingSwap = false
        var seenSwap = 0
        var armedMove: FrameMove?

        private var decider = FrameGestureDecider()
        private var mode = Mode.frame
        private var panBase: CGSize = .zero
        private var watermarkDragBase: CGSize = .zero
        private var watermarkDragStart: CGPoint = .zero
        private var watermarkDragging = false
        private let watermarkHaptic = UIImpactFeedbackGenerator(style: .soft)
        private var pinchBase: CGFloat = 1
        var alpha: CGFloat = 1
        private var suppressCommit = false
        /// A pinch during this gesture blocks the frame change even after the pinch ends.
        private var frameBlocked = false
        private var gestureCommitted = false
        fileprivate var settleToken = UUID()
        private var swapToken = UUID()
        private let haptic = UIImpactFeedbackGenerator(style: .light)

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === panRecognizer, zoom <= 1.04 else { return true }
            let x = gestureRecognizer.location(in: gestureRecognizer.view).x
            return x >= 28
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            if gestureRecognizer === longPressRecognizer || other === longPressRecognizer {
                return false
            }
            return gestureRecognizer === panRecognizer && other === pinchRecognizer
                || gestureRecognizer === pinchRecognizer && other === panRecognizer
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            // Let a recognized long-press take over before the pan commits a frame/watermark move.
            gestureRecognizer === longPressRecognizer && other === panRecognizer
        }

        @objc func doubleTapped() {
            zoom = 1
            pan = .zero
            alpha = 1
            onZoom(1)
            onPan(.zero)
            if let stage { apply(on: stage, animated: !reduceMotion) }
        }

        @objc func watermarkLongPressed(_ press: UILongPressGestureRecognizer) {
            guard zoom <= 1.04, let stage else {
                if press.state == .began || press.state == .changed {
                    press.state = .cancelled
                }
                return
            }
            switch press.state {
            case .began:
                let point = imagePoint(from: press.location(in: stage), in: stage)
                if watermarkEnabled, let imagePoint = point, nearWatermark(imagePoint, in: stage) {
                    cancelPresentation()
                    suppressCommit = true
                    frameBlocked = true
                    watermarkDragging = true
                    watermarkDragBase = watermarkOffset
                    watermarkDragStart = imagePoint
                    watermarkHaptic.impactOccurred()
                    stage.imageView.alpha = 0.92
                    onWatermarkDragBegan()
                    logLine("SPEKTRAFILM_WATERMARK_DRAG phase=begin")
                } else {
                    // Long-press the print (outside watermark) saves an independent look.
                    haptic.impactOccurred(intensity: 0.85)
                    onSaveLook()
                    press.state = .cancelled
                    logLine("SPEKTRAFILM_LOOK_LONGPRESS")
                }
            case .changed:
                guard watermarkDragging else { return }
                guard let imagePoint = imagePoint(from: press.location(in: stage), in: stage) else { return }
                let content = contentRect(in: stage)
                let width = max(content.width, 1)
                let height = max(content.height, 1)
                let dx = (imagePoint.x - watermarkDragStart.x) / width
                let dy = (imagePoint.y - watermarkDragStart.y) / height
                let nextX = Double(watermarkDragBase.width + dx)
                let nextY = Double(watermarkDragBase.height + dy)
                onWatermarkDragChanged(nextX, nextY)
            case .ended, .cancelled, .failed:
                guard watermarkDragging else { return }
                watermarkDragging = false
                stage.imageView.alpha = 1
                suppressCommit = false
                frameBlocked = false
                tracking = false
                onWatermarkDragEnded()
                logLine("SPEKTRAFILM_WATERMARK_DRAG phase=end")
            default:
                break
            }
        }

        private func contentRect(in stage: StageView) -> CGRect {
            guard let image = stage.imageView.image else {
                return stage.imageView.bounds
            }
            return contentRectProvider(image.size)
        }

        private func fittedImageRect(in stage: StageView) -> CGRect? {
            guard let image = stage.imageView.image else { return nil }
            let bounds = stage.imageView.bounds
            let scale = min(bounds.width / max(image.size.width, 1), bounds.height / max(image.size.height, 1))
            let width = image.size.width * scale
            let height = image.size.height * scale
            return CGRect(
                x: bounds.midX - width / 2,
                y: bounds.midY - height / 2,
                width: width,
                height: height
            )
        }

        private func imagePoint(from viewPoint: CGPoint, in stage: StageView) -> CGPoint? {
            guard let fitted = fittedImageRect(in: stage), let image = stage.imageView.image else { return nil }
            let local = stage.convert(viewPoint, to: stage.imageView)
            guard fitted.insetBy(dx: -8, dy: -8).contains(local) else { return nil }
            let x = (local.x - fitted.minX) / max(fitted.width, 1) * image.size.width
            let y = (local.y - fitted.minY) / max(fitted.height, 1) * image.size.height
            return CGPoint(x: x, y: y)
        }

        /// Generous hit zone around the credit so a long-press near the signature counts.
        private func nearWatermark(_ point: CGPoint, in stage: StageView) -> Bool {
            let content = contentRect(in: stage)
            guard content.width > 1, content.height > 1 else { return false }
            let short = min(content.width, content.height)
            let radius = max(36, short * 0.22)
            let ox = watermarkOffset.width * content.width
            let oy = watermarkOffset.height * content.height
            let pad = short * 0.02
            let safe = content.insetBy(dx: pad, dy: pad)
            if safe.contains(point) {
                // Credits live on the baseline, corners, or faint center — not the top mat.
                if point.y >= content.midY - short * 0.08 { return true }
                if abs(point.y - content.midY) < short * 0.20 { return true }
            }
            let anchors = [
                CGPoint(x: content.maxX - short * 0.08, y: content.maxY - short * 0.08),
                CGPoint(x: content.minX + short * 0.08, y: content.maxY - short * 0.08),
                CGPoint(x: content.midX, y: content.maxY - short * 0.08),
                CGPoint(x: content.midX, y: content.midY),
                CGPoint(x: content.maxX - short * 0.08, y: content.midY),
                CGPoint(x: content.minX + short * 0.08, y: content.midY),
            ]
            for anchor in anchors {
                let target = CGPoint(x: anchor.x + ox, y: anchor.y + oy)
                let dx = point.x - target.x
                let dy = point.y - target.y
                if dx * dx + dy * dy <= radius * radius { return true }
            }
            return false
        }

        @objc func pinched(_ pinch: UIPinchGestureRecognizer) {
            switch pinch.state {
            case .began:
                tracking = true
                suppressCommit = true
                frameBlocked = true
                pinchBase = zoom
                cancelPresentation()
            case .changed:
                zoom = min(4, max(1, pinchBase * pinch.scale))
                if let stage { apply(on: stage, animated: false) }
            case .ended, .cancelled, .failed:
                var next = min(4, max(1, pinchBase * pinch.scale))
                if next < 1.04 {
                    next = 1
                    pan = .zero
                    onPan(.zero)
                }
                zoom = next
                onZoom(next)
                suppressCommit = false
                if !panIsLive {
                    tracking = false
                    settling = false
                    settleToken = UUID()
                    if let stage { apply(on: stage, animated: false) }
                }
            default:
                break
            }
        }

        @objc func panned(_ pan: UIPanGestureRecognizer) {
            guard let stage else { return }
            let translation = size(of: pan.translation(in: stage))
            switch pan.state {
            case .began:
                beginPan(pan)
            case .changed:
                guard !suppressCommit || mode == .photo else { return }
                if mode == .photo {
                    self.pan = clamped(panBase + translation, in: stage)
                    apply(on: stage, animated: false)
                } else {
                    let resisted = offset(for: translation)
                    let played = transition.played(reduceMotion: reduceMotion)
                    if played == .instant {
                        if alpha != 1 {
                            alpha = 1
                            apply(on: stage, animated: false)
                        }
                    } else {
                        let distance = max(abs(resisted.width), abs(resisted.height))
                        alpha = PreviewMotion.dragAlpha(distance: distance, animated: true)
                        apply(on: stage, animated: false)
                    }
                }
            case .ended:
                finishPan(pan, translation: translation, cancelled: false)
            case .cancelled, .failed:
                finishPan(pan, translation: translation, cancelled: true)
            default:
                break
            }
        }

        private var panIsLive: Bool {
            let state = panRecognizer?.state
            return state == .began || state == .changed
        }

        private var pinchIsLive: Bool {
            let state = pinchRecognizer?.state
            return state == .began || state == .changed
        }

        private func beginPan(_ pan: UIPanGestureRecognizer) {
            tracking = true
            gestureCommitted = false
            cancelPresentation()
            panBase = self.pan
            mode = zoom > 1.04 ? .photo : .frame
            if watermarkDragging {
                suppressCommit = true
                frameBlocked = true
            } else if !pinchIsLive {
                suppressCommit = false
                frameBlocked = false
            }
            decider.reset()
            decider.begin(startX: pan.location(in: pan.view).x, frameGesture: mode == .frame)
            logLine("SPEKTRAFILM_FRAME_GESTURE phase=begin mode=\(mode == .photo ? "photo" : "frame") translation=0")
        }

        /// Drops an in-flight fade or page turn and puts the latest still back, unmoved.
        private func cancelPresentation() {
            settleToken = UUID()
            swapToken = UUID()
            awaitingSwap = false
            settling = false
            alpha = 1
            stage?.imageView.layer.removeAllAnimations()
            guard let stage else { return }
            stage.imageView.image = shown
            apply(on: stage, animated: false)
        }

        private func finishPan(_ pan: UIPanGestureRecognizer, translation: CGSize, cancelled: Bool) {
            let pinchLive = pinchIsLive
            defer {
                gestureCommitted = false
                decider.reset()
                if !pinchLive {
                    suppressCommit = false
                    tracking = false
                }
            }
            if cancelled {
                if mode == .photo {
                    self.pan = panBase
                    onPan(panBase)
                }
                alpha = 1
                awaitingSwap = false
                logLine("SPEKTRAFILM_FRAME_GESTURE phase=cancel reset=1 translation=0")
                springToRest()
                return
            }
            if mode == .photo || suppressCommit || frameBlocked {
                if mode == .photo {
                    let final = clamped(panBase + translation, in: stage)
                    self.pan = final
                    onPan(final)
                }
                alpha = 1
                awaitingSwap = false
                let reason = mode == .photo ? "zoom" : "pinch"
                logLine("SPEKTRAFILM_FRAME_GESTURE phase=end move=none reset=1 reason=\(reason) translation=0")
                if let stage { apply(on: stage, animated: false) }
                return
            }
            guard !gestureCommitted else {
                logLine("SPEKTRAFILM_FRAME_GESTURE phase=end move=none reset=1 reason=already translation=0")
                return
            }
            gestureCommitted = true
            let velocity = size(of: pan.velocity(in: stage))
            let predicted = CGSize(
                width: translation.width + velocity.width * 0.22,
                height: translation.height + velocity.height * 0.22
            )
            _ = offset(for: translation)
            let (atStart, atEnd) = bounds(for: decider.axis)
            guard let move = decider.end(translation: translation, predicted: predicted, atStart: atStart, atEnd: atEnd) else {
                alpha = 1
                awaitingSwap = false
                logLine("SPEKTRAFILM_FRAME_GESTURE phase=end move=none reset=1 translation=0")
                springToRest()
                return
            }
            haptic.impactOccurred()
            let played = transition.played(reduceMotion: reduceMotion)
            logLine("SPEKTRAFILM_FRAME_GESTURE phase=commit move=\(move.rawValue) transition=\(played.rawValue) translation=0")
            armedMove = move
            awaitingSwap = true
            armTimeout()
            let applied = onCommit(move)
            if !applied {
                awaitingSwap = false
                armedMove = nil
                alpha = 1
                logLine("SPEKTRAFILM_FRAME_GESTURE phase=end move=none reset=1 reason=unchanged translation=0")
                springToRest()
                return
            }
            if played == .instant {
                alpha = 1
                if let stage { apply(on: stage, animated: false) }
            }
        }

        private func springToRest() {
            guard let stage else { return }
            if reduceMotion {
                apply(on: stage, animated: false)
                settling = false
                return
            }
            settling = true
            let token = UUID()
            settleToken = token
            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0.55,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.apply(on: stage, animated: false)
            } completion: { [weak self] _ in
                guard let self, self.settleToken == token, !self.tracking, !self.awaitingSwap else { return }
                self.settling = false
            }
        }

        func armTimeout() {
            let token = UUID()
            swapToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self, self.swapToken == token, self.awaitingSwap, !self.tracking else { return }
                self.awaitingSwap = false
                self.alpha = 1
                self.settling = false
                if let stage = self.stage { self.apply(on: stage, animated: false) }
                logLine("SPEKTRAFILM_PREVIEW_TRANSITION style=dropped move=timeout translation=0")
            }
        }

        func swapImage(on view: StageView, to image: UIImage?, move: FrameMove?) {
            guard let image else { return }
            awaitingSwap = false
            armedMove = nil
            let style = transition.played(reduceMotion: reduceMotion)
            logLine("SPEKTRAFILM_PREVIEW_TRANSITION style=\(style.rawValue) move=\(move?.rawValue ?? "none") translation=0")
            switch style {
            case .instant:
                showInstant(on: view, image: image)
            case .dissolve:
                dissolve(on: view, image: image)
            case .pageTurn:
                turnPage(on: view, image: image, move: move)
            case .slideFade:
                slideFade(on: view, image: image, move: move)
            case .settle:
                settle(on: view, image: image)
            }
        }

        private func showInstant(on view: StageView, image: UIImage) {
            view.imageView.layer.removeAllAnimations()
            settling = false
            alpha = 1
            view.imageView.image = image
            apply(on: view, animated: false)
        }

        private func dissolve(on view: StageView, image: UIImage) {
            blend(on: view, image: image, option: .transitionCrossDissolve, duration: 0.34)
        }

        private func turnPage(on view: StageView, image: UIImage, move: FrameMove?) {
            // UIKit's curl synthesizes an opaque backface/shadow across the aspect-fit
            // image's empty bounds. Vertical swipes use a clean directional transition.
            if move == .nextWatermark || move == .previousWatermark {
                slideFade(on: view, image: image, move: move)
                return
            }
            guard view.window != nil,
                  view.imageView.bounds.width > 2,
                  view.imageView.bounds.height > 2,
                  let move
            else {
                logLine("SPEKTRAFILM_PREVIEW_TRANSITION style=dissolve fallback=page translation=0")
                dissolve(on: view, image: image)
                return
            }
            let option = pageOption(move)
            blend(on: view, image: image, option: option, duration: 0.56)
        }

        private func blend(on view: StageView, image: UIImage, option: UIView.AnimationOptions, duration: TimeInterval) {
            settling = true
            let token = UUID()
            settleToken = token
            view.imageView.layer.removeAllAnimations()
            UIView.transition(
                with: view.imageView,
                duration: duration,
                options: [option, .allowUserInteraction, .curveEaseInOut]
            ) {
                view.imageView.image = image
                self.alpha = 1
                view.imageView.alpha = 1
            } completion: { [weak self] _ in
                self?.finishSwap(token)
            }
        }

        private func slideFade(on view: StageView, image: UIImage, move: FrameMove?) {
            let nudge = slideVector(for: move)
            guard nudge != .zero else {
                dissolve(on: view, image: image)
                return
            }
            settling = true
            let token = UUID()
            settleToken = token
            let base = restingTransform()
            view.imageView.layer.removeAllAnimations()
            UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseIn, .allowUserInteraction]) {
                view.imageView.transform = base.concatenating(CGAffineTransform(translationX: nudge.width, y: nudge.height))
                view.imageView.alpha = 0
            } completion: { [weak self] _ in
                guard let self, self.settleToken == token else { return }
                view.imageView.image = image
                view.imageView.transform = base.concatenating(
                    CGAffineTransform(translationX: -nudge.width * 0.6, y: -nudge.height * 0.6)
                )
                view.imageView.alpha = 0
                UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                    view.imageView.transform = base
                    view.imageView.alpha = 1
                } completion: { [weak self] _ in
                    guard let self, self.settleToken == token else { return }
                    self.alpha = 1
                    self.finishSwap(token)
                }
            }
        }

        private func settle(on view: StageView, image: UIImage) {
            settling = true
            let token = UUID()
            settleToken = token
            let base = restingTransform()
            view.imageView.layer.removeAllAnimations()
            let outgoing = UIImageView(image: view.imageView.image)
            outgoing.contentMode = view.imageView.contentMode
            outgoing.bounds = view.imageView.bounds
            outgoing.center = view.imageView.center
            outgoing.transform = view.imageView.transform
            outgoing.alpha = view.imageView.alpha
            view.addSubview(outgoing)
            view.imageView.image = image
            view.imageView.alpha = 0
            view.imageView.transform = base.scaledBy(x: 0.965, y: 0.965)
            UIView.animate(withDuration: 0.42, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                outgoing.alpha = 0
                view.imageView.alpha = 1
                view.imageView.transform = base
            } completion: { [weak self] _ in
                outgoing.removeFromSuperview()
                guard let self, self.settleToken == token else { return }
                self.alpha = 1
                self.finishSwap(token)
            }
        }

        private func finishSwap(_ token: UUID) {
            guard settleToken == token else { return }
            settling = false
            awaitingSwap = false
            alpha = 1
            guard let stage, !tracking else { return }
            apply(on: stage, animated: false)
        }

        private func pageOption(_ move: FrameMove) -> UIView.AnimationOptions {
            switch move {
            case .nextWatermark, .previousWatermark:
                return .transitionCrossDissolve
            case .previousStyle, .previousFamily:
                return .transitionFlipFromLeft
            case .nextStyle, .nextFamily:
                return .transitionFlipFromRight
            }
        }

        /// A short nudge for the slide-fade commit. The drag itself never uses this.
        private func slideVector(for move: FrameMove?) -> CGSize {
            switch move {
            case .nextStyle, .nextFamily:
                return CGSize(width: -22, height: 0)
            case .previousStyle, .previousFamily:
                return CGSize(width: 22, height: 0)
            case .nextWatermark:
                return CGSize(width: 0, height: -22)
            case .previousWatermark:
                return CGSize(width: 0, height: 22)
            case nil:
                return .zero
            }
        }

        private func restingTransform() -> CGAffineTransform {
            // Translation is in screen points, after scale, so a zoomed photo pans 1:1.
            CGAffineTransform(scaleX: zoom, y: zoom)
                .concatenating(CGAffineTransform(translationX: pan.width, y: pan.height))
        }

        func apply(on view: StageView, animated: Bool) {
            let transform = restingTransform()
            let updates = {
                view.imageView.transform = transform
                view.imageView.alpha = self.alpha
            }
            if animated {
                springToRest()
            } else if UIView.inheritedAnimationDuration > 0 {
                updates()
            } else {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                updates()
                CATransaction.commit()
            }
        }

        private func offset(for translation: CGSize) -> CGSize {
            let hinted: FrameAxis = decider.axis ?? (abs(translation.width) >= abs(translation.height) ? .horizontal : .vertical)
            let (atStart, atEnd) = bounds(for: hinted)
            return decider.update(translation: translation, atStart: atStart, atEnd: atEnd)
        }

        private func bounds(for axis: FrameAxis?) -> (Bool, Bool) {
            switch axis {
            case .horizontal:
                return (!canMove(.previousStyle), !canMove(.nextStyle))
            case .vertical:
                return (!canMove(.previousWatermark), !canMove(.nextWatermark))
            case nil:
                return (false, false)
            }
        }

        private func clamped(_ value: CGSize, in view: UIView?) -> CGSize {
            let bounds = view?.bounds.size ?? CGSize(width: 320, height: 480)
            let limitX = max(48, bounds.width * max(0, zoom - 1) * 0.55)
            let limitY = max(48, bounds.height * max(0, zoom - 1) * 0.55)
            return CGSize(
                width: min(limitX, max(-limitX, value.width)),
                height: min(limitY, max(-limitY, value.height))
            )
        }

        private enum Mode { case frame, photo }
    }
}

private func sameImage(_ lhs: UIImage?, _ rhs: UIImage?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
        return true
    case let (left?, right?):
        return left === right
    default:
        return false
    }
}

private func + (lhs: CGSize, rhs: CGSize) -> CGSize {
    CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
}

private func size(of point: CGPoint) -> CGSize {
    CGSize(width: point.x, height: point.y)
}
