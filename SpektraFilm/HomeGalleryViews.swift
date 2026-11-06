import PhotosUI
import SwiftUI
import UIKit

/// Launch home: blank develop slot on top, recent gallery pieces below (museum wall).
struct HomeColorChartView: View {
    @ObservedObject var model: LabModel
    @Binding var pickerItem: PhotosPickerItem?
    var onOpenGallery: () -> Void

    private var recent: [GalleryItem] {
        model.gallery.recent(limit: 9)
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height + 40
            VStack(spacing: 0) {
                homeTopBar
                ScrollView {
                    VStack(alignment: .leading, spacing: landscape ? 18 : 22) {
                        developSlot(landscape: landscape)
                            .padding(.top, 8)
                        if !recent.isEmpty {
                            Text("最近")
                                .font(.system(size: 12, weight: .semibold, design: .serif))
                                .foregroundStyle(GalleryInk.mute)
                                .tracking(1.4)
                                .padding(.horizontal, 4)
                            recentGrid(landscape: landscape)
                        } else {
                            emptyHint
                        }
                    }
                    .padding(.horizontal, landscape ? 22 : 18)
                    .padding(.bottom, 28)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background {
                GalleryWallBackground()
                    .ignoresSafeArea()
            }
        }
    }

    private var homeTopBar: some View {
        HStack(spacing: 8) {
            Text("LiteFilm")
                .font(.system(size: 17, weight: .medium, design: .serif))
                .foregroundStyle(GalleryInk.ink)
            Spacer(minLength: 8)
            Button(action: onOpenGallery) {
                Text("全部")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GalleryInk.mute)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.04), in: Capsule())
                    .overlay(Capsule().stroke(GalleryInk.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开全部画廊")
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func developSlot(landscape: Bool) -> some View {
        PhotosPicker(selection: $pickerItem, matching: PhotoImport.pickerFilter, preferredItemEncoding: PhotoImport.preferredEncoding) {
            ZStack {
                // Empty mat hanging on the wall
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.black.opacity(0.10))
                    .offset(y: 5)
                    .blur(radius: 6)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.22, green: 0.18, blue: 0.14),
                                Color(red: 0.12, green: 0.10, blue: 0.08),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color(red: 0.97, green: 0.96, blue: 0.93))
                    .padding(10)

                VStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Ink.amber)
                    Text("新冲洗")
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .foregroundStyle(GalleryInk.ink)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: landscape ? 168 : 200)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
        .accessibilityLabel("新冲洗")
        .accessibilityHint("选择照片开始冲洗")
    }

    private func recentGrid(landscape: Bool) -> some View {
        let columnsCount = landscape ? 4 : 3
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: columnsCount)
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(recent) { item in
                Button {
                    Task { await model.openImport(id: item.id) }
                } label: {
                    FramedWallArt(
                        image: model.gallery.loadThumb(for: item),
                        plaque: recentPlaque(item),
                        matInset: 7,
                        framePad: 5,
                        shadowRadius: 8,
                        corner: 2,
                        lockPortraitAspect: true
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("打开") {
                        Task { await model.openImport(id: item.id) }
                    }
                    Button("删除", role: .destructive) {
                        Task { await model.deleteImport(id: item.id) }
                    }
                }
                .accessibilityLabel(item.title)
            }
        }
    }

    private var emptyHint: some View {
        Text("点上方空白框，选一张照片开始冲洗")
            .font(.system(size: 13, weight: .medium, design: .serif))
            .foregroundStyle(GalleryInk.mute)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func recentPlaque(_ item: GalleryItem) -> String {
        if item.isVariant {
            return item.title.split(separator: "·").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "方案"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return formatter.string(from: item.createdAt)
    }
}

// MARK: - Gallery hang modes

enum GalleryHangMode: String, CaseIterable, Identifiable {
    case salon
    case single
    case row

    var id: String { rawValue }

    var title: String {
        switch self {
        case .salon: return "沙龙"
        case .single: return "单幅"
        case .row: return "联展"
        }
    }

    var systemImage: String {
        switch self {
        case .salon: return "square.grid.3x3"
        case .single: return "rectangle.portrait"
        case .row: return "rectangle.split.2x1"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .salon: return "沙龙多宫格墙面"
        case .single: return "单幅观赏"
        case .row: return "两联三联墙面"
        }
    }
}

private enum WallPiece: Identifiable, Hashable {
    case sample
    case imported(GalleryItem)

    var id: String {
        switch self {
        case .sample: return GalleryItem.sampleID
        case .imported(let item): return item.id
        }
    }

    var isSample: Bool {
        if case .sample = self { return true }
        return false
    }

    var importItem: GalleryItem? {
        if case .imported(let item) = self { return item }
        return nil
    }
}

/// Sandbox gallery of imported photos, with the built-in chart pinned first.
/// Museum-wall hang: framed works on dark plaster, with salon / single / diptych-triptych modes.
struct ImportGalleryView: View {
    @ObservedObject var model: LabModel
    @Binding var pickerItem: PhotosPickerItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("spektrafilm.gallery.hangMode") private var hangModeRaw: String = GalleryHangMode.salon.rawValue
    @State private var editing = false
    @State private var pendingDelete: GalleryItem?
    @State private var focusIndex: Int = 0

    private var hangMode: GalleryHangMode {
        GalleryHangMode(rawValue: hangModeRaw) ?? .salon
    }

    private var pieces: [WallPiece] {
        [.sample] + model.gallery.items.map { .imported($0) }
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height + 24
            VStack(spacing: 0) {
                topBar(landscape: landscape)
                modeBar
                wallContent(size: geo.size, landscape: landscape)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background {
                GalleryWallBackground()
                    .ignoresSafeArea()
            }
        }
        .confirmationDialog(
            "删除这张导入？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let item = pendingDelete {
                    Task { await model.deleteImport(id: item.id) }
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("只会从LiteFilm画廊里移除，不会改你的系统相册。")
        }
        .onChange(of: pieces.count) { _, _ in
            if focusIndex >= pieces.count {
                focusIndex = max(0, pieces.count - 1)
            }
        }
        .onChange(of: hangModeRaw) { _, _ in
            clampFocus()
        }
    }

    // MARK: Chrome

    private func topBar(landscape: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                model.openHome()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GalleryInk.ink)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.04), in: Circle())
                    .overlay(Circle().stroke(GalleryInk.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回首页")

            VStack(alignment: .leading, spacing: 2) {
                Text("画廊")
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .foregroundStyle(GalleryInk.ink)
                Text(landscape ? "横屏 · 白色展墙" : "白色墙面上的作品")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(GalleryInk.mute)
            }

            Spacer(minLength: 6)

            Button(editing ? "完成" : "整理") {
                withModeAnimation { editing.toggle() }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(editing ? Ink.amber : GalleryInk.mute)
            .frame(minWidth: 44, minHeight: 36)

            PhotosPicker(selection: $pickerItem, matching: PhotoImport.pickerFilter, preferredItemEncoding: PhotoImport.preferredEncoding) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GalleryInk.ink)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.04), in: Circle())
                    .overlay(Circle().stroke(GalleryInk.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("导入照片")
            .disabled(model.busy)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var modeBar: some View {
        HStack(spacing: 6) {
            ForEach(GalleryHangMode.allCases) { mode in
                Button {
                    setHangMode(mode)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                        Text(mode.title)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(hangMode == mode ? Color(red: 0.12, green: 0.09, blue: 0.06) : GalleryInk.mute)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(hangMode == mode ? Ink.amber : Color.black.opacity(0.04))
                    )
                    .overlay(
                        Capsule().stroke(hangMode == mode ? Color.clear : GalleryInk.stroke, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.accessibilityLabel)
                .accessibilityAddTraits(hangMode == mode ? .isSelected : [])
            }
            Spacer(minLength: 0)
            Text("\(max(0, pieces.count - 1)) 幅导入")
                .font(.caption2)
                .foregroundStyle(GalleryInk.mute)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func wallContent(size: CGSize, landscape: Bool) -> some View {
        switch hangMode {
        case .salon:
            salonWall(size: size, landscape: landscape)
        case .single:
            singleWall(size: size, landscape: landscape)
        case .row:
            rowWall(size: size, landscape: landscape)
        }
    }

    // MARK: Salon (multi grid)

    private func salonWall(size: CGSize, landscape: Bool) -> some View {
        let columnsCount = landscape ? 4 : 3
        let spacing: CGFloat = landscape ? 18 : 14
        let hPad: CGFloat = landscape ? 22 : 16
        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnsCount)

        return ScrollView {
            VStack(spacing: 0) {
                hangingRail
                    .padding(.horizontal, hPad)
                    .padding(.bottom, 14)
                LazyVGrid(columns: columns, spacing: spacing + 6) {
                    ForEach(Array(pieces.enumerated()), id: \.element.id) { index, piece in
                        wallCell(piece, index: index, matInset: 7, framePad: 5, shadow: 8)
                    }
                }
                .padding(.horizontal, hPad)
                .padding(.bottom, 28)

                if model.gallery.items.isEmpty {
                    emptyHint
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: Row (diptych / triptych)

    private func rowWall(size: CGSize, landscape: Bool) -> some View {
        let columnsCount = landscape ? 3 : 2
        let spacing: CGFloat = landscape ? 28 : 22
        let hPad: CGFloat = landscape ? 28 : 20
        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnsCount)

        return ScrollView {
            VStack(spacing: 0) {
                hangingRail
                    .padding(.horizontal, hPad)
                    .padding(.bottom, 18)
                LazyVGrid(columns: columns, spacing: spacing + 10) {
                    ForEach(Array(pieces.enumerated()), id: \.element.id) { index, piece in
                        wallCell(piece, index: index, matInset: 10, framePad: 7, shadow: 12)
                    }
                }
                .padding(.horizontal, hPad)
                .padding(.bottom, 32)

                if model.gallery.items.isEmpty {
                    emptyHint
                }
            }
            .padding(.top, 6)
        }
    }

    // MARK: Single (one large work)

    private func singleWall(size: CGSize, landscape: Bool) -> some View {
        let safePieces = pieces
        let index = min(max(0, focusIndex), max(0, safePieces.count - 1))
        let piece = safePieces.isEmpty ? WallPiece.sample : safePieces[index]
        let maxArtWidth = landscape ? min(size.width * 0.62, size.height * 1.15) : min(size.width - 48, size.height * 0.62)
        let maxArtHeight = landscape ? size.height - 120 : size.height * 0.58

        return VStack(spacing: 0) {
            hangingRail
                .padding(.horizontal, landscape ? 36 : 24)
                .padding(.top, 4)
                .padding(.bottom, 12)

            Spacer(minLength: 4)

            ZStack(alignment: .topTrailing) {
                Button {
                    openPiece(piece)
                } label: {
                    FramedWallArt(
                        image: image(for: piece),
                        plaque: plaque(for: piece),
                        matInset: landscape ? 14 : 12,
                        framePad: landscape ? 10 : 8,
                        shadowRadius: 18,
                        corner: 3,
                        lockPortraitAspect: false,
                        contentAspect: imageAspect(for: piece)
                    )
                    .frame(maxWidth: maxArtWidth, maxHeight: maxArtHeight)
                }
                .buttonStyle(.plain)
                .disabled(editing && piece.isSample)
                .accessibilityLabel(piece.isSample ? "打开内置色卡" : "打开导入照片")
                .contextMenu {
                    if let item = piece.importItem {
                        Button("打开编辑") {
                            Task { await model.openImport(id: item.id) }
                        }
                        Button("删除", role: .destructive) {
                            pendingDelete = item
                        }
                    } else {
                        Button("打开色卡编辑") {
                            Task { await model.openSampleInEditor() }
                        }
                    }
                }

                if editing, let item = piece.importItem {
                    Button {
                        pendingDelete = item
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Ink.ember)
                            .font(.system(size: 26))
                            .padding(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        guard !editing else { return }
                        let dx = value.translation.width
                        if dx < -50 {
                            stepFocus(+1)
                        } else if dx > 50 {
                            stepFocus(-1)
                        }
                    }
            )

            Spacer(minLength: 8)

            singleNav(index: index, total: safePieces.count)
                .padding(.bottom, landscape ? 12 : 18)
        }
        .padding(.horizontal, landscape ? 20 : 12)
    }

    private func singleNav(index: Int, total: Int) -> some View {
        HStack(spacing: 18) {
            Button {
                stepFocus(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(index <= 0 ? GalleryInk.mute.opacity(0.35) : GalleryInk.ink)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.04), in: Circle())
                    .overlay(Circle().stroke(GalleryInk.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(index <= 0)
            .accessibilityLabel("上一幅")

            VStack(spacing: 4) {
                Text(plaque(for: pieces[safe: index] ?? .sample))
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(GalleryInk.ink)
                Text("\(index + 1) / \(max(total, 1))")
                    .font(.caption2)
                    .foregroundStyle(GalleryInk.mute)
                Text("左右滑动切换作品")
                    .font(.system(size: 10))
                    .foregroundStyle(GalleryInk.mute.opacity(0.8))
            }
            .frame(minWidth: 120)

            Button {
                stepFocus(+1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(index >= total - 1 ? GalleryInk.mute.opacity(0.35) : GalleryInk.ink)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.04), in: Circle())
                    .overlay(Circle().stroke(GalleryInk.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(index >= total - 1)
            .accessibilityLabel("下一幅")
        }
    }

    // MARK: Cells

    private func wallCell(
        _ piece: WallPiece,
        index: Int,
        matInset: CGFloat,
        framePad: CGFloat,
        shadow: CGFloat
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                if editing {
                    if let item = piece.importItem {
                        pendingDelete = item
                    }
                } else {
                    openPiece(piece)
                    focusIndex = index
                }
            } label: {
                FramedWallArt(
                    image: image(for: piece),
                    plaque: plaque(for: piece),
                    matInset: matInset,
                    framePad: framePad,
                    shadowRadius: shadow,
                    corner: 2,
                    lockPortraitAspect: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(piece.isSample ? "打开内置色卡" : "打开导入照片")
            .contextMenu {
                if let item = piece.importItem {
                    Button("打开编辑") {
                        Task { await model.openImport(id: item.id) }
                    }
                    Button("删除", role: .destructive) {
                        pendingDelete = item
                    }
                } else {
                    Button("打开色卡编辑") {
                        Task { await model.openSampleInEditor() }
                    }
                }
            }

            if editing, piece.importItem != nil {
                Image(systemName: "minus.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Ink.ember)
                    .font(.system(size: 22))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }

    private var hangingRail: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.42, green: 0.34, blue: 0.24),
                            Ink.amber.opacity(0.85),
                            Color(red: 0.42, green: 0.34, blue: 0.24),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 3)
                .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
            HStack {
                railHook
                Spacer()
                railHook
                Spacer()
                railHook
            }
            .padding(.horizontal, 28)
            .offset(y: -1)
        }
        .accessibilityHidden(true)
    }

    private var railHook: some View {
        Capsule()
            .fill(Color(red: 0.55, green: 0.45, blue: 0.32).opacity(0.7))
            .frame(width: 8, height: 10)
    }

    private var emptyHint: some View {
        Text("还没有导入过照片。点右上角加号，或回首页点色卡。")
            .font(.caption)
            .foregroundStyle(GalleryInk.mute)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 8)
    }

    // MARK: Actions / helpers

    private func setHangMode(_ mode: GalleryHangMode) {
        guard mode.rawValue != hangModeRaw else { return }
        withModeAnimation {
            hangModeRaw = mode.rawValue
        }
    }

    private func withModeAnimation(_ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(.easeInOut(duration: 0.28)) {
                updates()
            }
        }
    }

    private func stepFocus(_ delta: Int) {
        let next = focusIndex + delta
        guard next >= 0, next < pieces.count else { return }
        withModeAnimation {
            focusIndex = next
        }
    }

    private func clampFocus() {
        if focusIndex >= pieces.count {
            focusIndex = max(0, pieces.count - 1)
        }
    }

    private func openPiece(_ piece: WallPiece) {
        guard !editing else { return }
        switch piece {
        case .sample:
            Task { await model.openSampleInEditor() }
        case .imported(let item):
            Task { await model.openImport(id: item.id) }
        }
    }

    private func image(for piece: WallPiece) -> UIImage? {
        switch piece {
        case .sample:
            return model.preview ?? bundleSampleImage()
        case .imported(let item):
            return model.gallery.loadThumb(for: item)
        }
    }

    private func plaque(for piece: WallPiece) -> String {
        switch piece {
        case .sample:
            return "内置色卡"
        case .imported(let item):
            if item.isVariant {
                let head = item.title.split(separator: "·").first.map(String.init)?.trimmingCharacters(in: .whitespaces)
                return head?.isEmpty == false ? (head ?? "方案") : "方案"
            }
            return shortDate(item.createdAt)
        }
    }

    private func imageAspect(for piece: WallPiece) -> CGFloat {
        guard let image = image(for: piece), image.size.height > 1 else { return 0.8 }
        return image.size.width / image.size.height
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private func bundleSampleImage() -> UIImage? {
        guard let url = Bundle.main.url(forResource: "SampleBars", withExtension: "png"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Wall visuals

/// Light museum wall chrome (not app Ink.void). Default gallery is white plaster.
private enum GalleryInk {
    static let ink = Color(red: 0.18, green: 0.15, blue: 0.12)
    static let mute = Color(red: 0.48, green: 0.44, blue: 0.38)
    static let stroke = Color.black.opacity(0.10)
}

private struct GalleryWallBackground: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Museum white plaster
                LinearGradient(
                    colors: [
                        Color(red: 0.97, green: 0.96, blue: 0.94),
                        Color(red: 0.94, green: 0.93, blue: 0.90),
                        Color(red: 0.91, green: 0.90, blue: 0.87),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Ceiling track wash (soft warm light from above)
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.97, blue: 0.90).opacity(0.55),
                        Color.clear,
                    ],
                    startPoint: .top,
                    endPoint: .center
                )

                // Left track spot
                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.96, blue: 0.88).opacity(0.38),
                        Color.clear,
                    ],
                    center: UnitPoint(x: 0.22, y: 0.08),
                    startRadius: 10,
                    endRadius: min(w, h) * 0.55
                )

                // Right track spot
                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.97, blue: 0.90).opacity(0.32),
                        Color.clear,
                    ],
                    center: UnitPoint(x: 0.78, y: 0.10),
                    startRadius: 8,
                    endRadius: min(w, h) * 0.50
                )

                // Center pool on the hang
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.35),
                        Color.clear,
                    ],
                    center: UnitPoint(x: 0.5, y: 0.42),
                    startRadius: 20,
                    endRadius: min(w, h) * 0.62
                )

                // Soft edge vignette (gallery room corners)
                RadialGradient(
                    colors: [
                        Color.clear,
                        Color(red: 0.72, green: 0.70, blue: 0.66).opacity(0.22),
                    ],
                    center: .center,
                    startRadius: min(w, h) * 0.35,
                    endRadius: max(w, h) * 0.78
                )

                // Floor baseboard wash
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color(red: 0.78, green: 0.74, blue: 0.68).opacity(0.35),
                            Color(red: 0.62, green: 0.58, blue: 0.52).opacity(0.45),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: min(140, h * 0.18))
                }
            }
        }
    }
}

private struct FramedWallArt: View {
    let image: UIImage?
    let plaque: String
    var matInset: CGFloat = 8
    var framePad: CGFloat = 6
    var shadowRadius: CGFloat = 10
    var corner: CGFloat = 2
    /// Salon / row cells keep a shared portrait frame so the wall reads as a hang.
    var lockPortraitAspect: Bool = true
    var contentAspect: CGFloat = 0.82

    private let wood = Color(red: 0.16, green: 0.13, blue: 0.10)
    private let woodEdge = Color(red: 0.32, green: 0.26, blue: 0.20)
    private let mat = Color(red: 0.96, green: 0.94, blue: 0.90)

    private var frameAspect: CGFloat {
        if lockPortraitAspect { return 0.82 }
        return min(1.45, max(0.62, contentAspect))
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Soft wall shadow under the hang
                RoundedRectangle(cornerRadius: corner + 2, style: .continuous)
                    .fill(Color.black.opacity(0.18))
                    .offset(y: max(4, shadowRadius * 0.42))
                    .blur(radius: shadowRadius * 0.55)

                RoundedRectangle(cornerRadius: corner + 1, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [woodEdge.opacity(0.95), wood, woodEdge.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: corner + 1, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                    )

                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(mat)
                    .padding(framePad)
                    .overlay {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .stroke(Color.black.opacity(0.10), lineWidth: 0.6)
                            .padding(framePad)
                    }

                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Color(red: 0.90, green: 0.88, blue: 0.84)
                            Image(systemName: "photo")
                                .foregroundStyle(GalleryInk.mute)
                        }
                    }
                }
                .padding(framePad + matInset)
                .clipShape(Rectangle())

                // Glass catchlight — thin specular along top edge of the art glass
                RoundedRectangle(cornerRadius: corner + 1, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color.white.opacity(0.08),
                                Color.clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.1
                    )
                    .padding(0.5)
                    .allowsHitTesting(false)

                // Soft warm spot pooled on the glass
                RoundedRectangle(cornerRadius: corner + 1, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.98, blue: 0.92).opacity(0.16),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.35, y: 0.18),
                            startRadius: 2,
                            endRadius: 90
                        )
                    )
                    .allowsHitTesting(false)
            }
            .aspectRatio(frameAspect, contentMode: .fit)

            Text(plaque)
                .font(.system(size: 10, weight: .medium, design: .serif))
                .foregroundStyle(GalleryInk.mute)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.white.opacity(0.72))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .stroke(GalleryInk.stroke, lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 2, y: 1)
                )
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
