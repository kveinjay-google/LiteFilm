import ImageIO
import PhotosUI
import SwiftUI
import UIKit

/// The home and collection observe the store itself: item changes do not publish on LabModel.
struct HomeColorChartView: View {
    @ObservedObject var model: LabModel
    @ObservedObject private var gallery: ImportGalleryStore
    @Binding var pickerItem: PhotosPickerItem?
    var onOpenGallery: () -> Void
    var onOpenSettings: () -> Void
    @State private var selectedID: String?

    init(model: LabModel, pickerItem: Binding<PhotosPickerItem?>,
         onOpenGallery: @escaping () -> Void, onOpenSettings: @escaping () -> Void = {}) {
        self.model = model
        self.gallery = model.gallery
        self._pickerItem = pickerItem
        self.onOpenGallery = onOpenGallery
        self.onOpenSettings = onOpenSettings
    }

    private var recent: [GalleryItem] { gallery.recent(limit: 12) }
    private var selected: GalleryItem? { recent.first { $0.id == selectedID } ?? recent.first }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            VStack(spacing: 0) {
                CollectionHeader(title: "LiteFilm", brand: true) {
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape").collectionIcon()
                    }
                    .accessibilityLabel("设置")
                } trailing: {
                    importPicker(iconOnly: true)
                }
                CollectionStatus(model: model)
                ScrollView {
                    VStack(spacing: 18) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("最近作品")
                                .font(.headline)
                                .foregroundStyle(Ink.ivory)
                            Spacer()
                            Button(action: onOpenGallery) {
                                HStack(spacing: 5) {
                                    Text("全部作品")
                                    Image(systemName: "arrow.up.right")
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Ink.mute)
                                .frame(minHeight: 44)
                            }
                            .disabled(model.busy)
                        }
                        .padding(.horizontal, 20)
                        if let item = selected {
                            hero(item, height: landscape ? 230 : min(geo.size.height * 0.50, 480))
                            recentStrip
                        } else {
                            emptyHome(height: landscape ? 210 : max(250, geo.size.height * 0.48))
                        }
                    }
                    .padding(.bottom, 20)
                }
                importPicker(iconOnly: false)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
            }
            .background(Ink.void.ignoresSafeArea())
        }
        .buttonStyle(.plain)
        .onChange(of: gallery.items) { _, items in
            if let selectedID, !items.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
        }
    }

    private func hero(_ item: GalleryItem, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Button { open(item) } label: {
                CollectionPhoto(
                    url: item.isVariant ? gallery.thumbURL(for: item) : gallery.originalURL(for: item),
                    fallback: item.isVariant ? nil : gallery.thumbURL(for: item), fit: true
                )
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .disabled(model.busy)
            .accessibilityLabel("继续编辑，\(item.title)")
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(item.isVariant ? "已保存方案" : item.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(Ink.mute)
                }
                Spacer(minLength: 8)
                Button { open(item) } label: {
                    Label("继续编辑", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 44)
                }
                .disabled(model.busy)
            }
            .foregroundStyle(Ink.ivory)
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    private var recentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(recent) { item in
                    Button { selectedID = item.id } label: {
                        CollectionPhoto(url: gallery.thumbURL(for: item), fallback: item.isVariant ? nil : gallery.originalURL(for: item))
                            .frame(width: 104, height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(selected?.id == item.id ? Ink.amber : Color.clear, lineWidth: 2)
                            }
                            .padding(2)
                    }
                    .accessibilityLabel("预览，\(item.title)")
                    .accessibilityAddTraits(selected?.id == item.id ? .isSelected : [])
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func emptyHome(height: CGFloat) -> some View {
        VStack(spacing: 22) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 58, weight: .ultraLight))
                .foregroundStyle(Ink.amber)
            VStack(spacing: 10) {
                Text("让日常，留下胶片色彩")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Ink.ivory)
                Text("导入一张照片，开始你的第一件作品。")
                    .font(.subheadline)
                    .foregroundStyle(Ink.mute)
            }
            .multilineTextAlignment(.center)
            Button { Task { await model.openSampleInEditor() } } label: {
                Label("先试试内置色卡", systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Ink.ivory)
                    .frame(minHeight: 44)
            }
            .disabled(model.busy)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(minHeight: height)
    }

    private func importPicker(iconOnly: Bool) -> some View {
        PhotosPicker(selection: $pickerItem, matching: PhotoImport.pickerFilter,
                     preferredItemEncoding: PhotoImport.preferredEncoding) {
            if iconOnly {
                Image(systemName: "plus").collectionIcon()
            } else {
                Label("导入照片", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(Ink.void)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Ink.amber, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .disabled(model.busy)
        .opacity(model.busy ? 0.5 : 1)
        .accessibilityLabel("导入照片")
    }

    private func open(_ item: GalleryItem) {
        guard !model.busy else { return }
        Task { await model.openImport(id: item.id) }
    }
}

// The original presentation choices remain available from the collection's overflow menu.
enum GalleryHangMode: String, CaseIterable, Identifiable {
    case grid, salon, single, row
    var id: String { rawValue }
    var title: String {
        switch self {
        case .grid: return "网格"
        case .salon: return "沙龙"
        case .single: return "单幅"
        case .row: return "联展"
        }
    }
    var systemImage: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .salon: return "square.grid.3x3"
        case .single: return "rectangle.portrait"
        case .row: return "rectangle.split.2x1"
        }
    }
    var accessibilityLabel: String { "\(title)布局" }
}

private struct GalleryBatchSelection: Identifiable {
    let id = UUID()
    let items: [GalleryItem]
}

struct ImportGalleryView: View {
    @ObservedObject var model: LabModel
    @ObservedObject private var gallery: ImportGalleryStore
    @Binding var pickerItem: PhotosPickerItem?
    @AppStorage("litefilm.gallery.obsidianLayout") private var hangModeRaw = GalleryHangMode.grid.rawValue
    @AppStorage("litefilm.gallery.presentation") private var presentationRaw = GalleryPresentation.album.rawValue
    @AppStorage("litefilm.gallery.direction") private var directionRaw = GalleryDirection.vertical.rawValue
    @AppStorage("litefilm.gallery.showArtworkInfo") private var showArtworkInfo = false
    @State private var focusedGalleryID: String?
    @State private var galleryChromeVisible = true
    @State private var editing = false
    @State private var selectedIDs: Set<String> = []
    @State private var pendingDelete: [GalleryItem] = []
    @State private var batchSelection: GalleryBatchSelection?
    @State private var recentOnly = false
    @State private var focusIndex = 0

    init(model: LabModel, pickerItem: Binding<PhotosPickerItem?>) {
        self.model = model
        self.gallery = model.gallery
        self._pickerItem = pickerItem
    }

    private var presentation: GalleryPresentation { GalleryPresentation(rawValue: presentationRaw) ?? .album }
    private var hangMode: GalleryHangMode { GalleryHangMode(rawValue: hangModeRaw) ?? .grid }
    private var items: [GalleryItem] { recentOnly ? gallery.recent(limit: 12) : gallery.items }
    private var direction: GalleryDirection { GalleryDirection(rawValue: directionRaw) ?? .vertical }
    private var immersive: Bool { presentation == .gallery && !editing && !items.isEmpty }
    private var focusedArtwork: GalleryItem? { items.first { $0.id == focusedGalleryID } ?? items.first }

    var body: some View {
        Group {
            if immersive {
                immersiveGallery
            } else {
                GeometryReader { geo in
                    let landscape = geo.size.width > geo.size.height
                    VStack(spacing: 0) {
                        CollectionHeader(title: "全部作品") {
                            Button { model.openHome() } label: {
                                Image(systemName: "chevron.left").collectionIcon()
                            }
                            .disabled(model.busy)
                            .accessibilityLabel("返回首页")
                        } trailing: {
                            Button(editing ? "完成" : "选择") {
                                editing.toggle()
                                selectedIDs.removeAll()
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(editing ? Ink.amber : Ink.ivory)
                            .frame(minWidth: 44, minHeight: 44)
                            .disabled(gallery.items.isEmpty || model.busy)
                        }
                        if landscape {
                            HStack(spacing: 0) {
                                presentationPicker
                                collectionToolbar
                            }
                        } else {
                            presentationPicker
                            collectionToolbar
                        }
                        CollectionStatus(model: model)
                        if items.isEmpty {
                            emptyGallery
                        } else if presentation == .gallery {
                            GalleryWallView(items: items, gallery: gallery, direction: direction, focusedID: $focusedGalleryID,
                                            editing: editing, selectedIDs: selectedIDs, busy: model.busy,
                                            activate: activate, open: { item in
                                                Task { await model.openImport(id: item.id) }
                                            }, delete: { pendingDelete = [$0] })
                        } else if hangMode == .single {
                            singleContent(height: max(120, geo.size.height - 250))
                        } else {
                            gridContent(landscape: landscape)
                        }
                        bottomBar
                    }
                    .background(Ink.void.ignoresSafeArea())
                }
            }
        }
        .statusBarHidden(immersive)
        .persistentSystemOverlays(immersive ? .hidden : .automatic)
        .buttonStyle(.plain)
        .sheet(item: $batchSelection) { selection in
            BatchProcessingSheet(model: model, items: selection.items)
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(
            get: { !pendingDelete.isEmpty },
            set: { if !$0 { pendingDelete = [] } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                let deleting = pendingDelete
                pendingDelete = []
                Task {
                    for item in deleting { await model.deleteImport(id: item.id) }
                    selectedIDs.subtract(deleting.map(\.id))
                }
            }
            .disabled(model.busy)
            Button("取消", role: .cancel) { pendingDelete = [] }
        } message: {
            Text("只从 LiteFilm 移除所选作品，不会改动系统相册。其他独立保存的方案会保留。")
        }
        .onChange(of: gallery.items) { _, values in
            selectedIDs.formIntersection(Set(values.map(\.id)))
            focusIndex = min(focusIndex, max(0, items.count - 1))
            if values.isEmpty { editing = false }
            if let focusedGalleryID, !items.contains(where: { $0.id == focusedGalleryID }) {
                self.focusedGalleryID = items.first?.id
            }
        }
        .onChange(of: recentOnly) { _, _ in
            focusIndex = 0
            selectedIDs.removeAll()
            focusedGalleryID = items.first?.id
        }
    }

    private var immersiveGallery: some View {
        ZStack {
            GalleryWallView(items: items, gallery: gallery, direction: direction, focusedID: $focusedGalleryID,
                editing: false, selectedIDs: [], busy: model.busy,
                activate: { _ in
                    withAnimation(.easeOut(duration: 0.18)) { galleryChromeVisible.toggle() }
                }, open: { item in Task { await model.openImport(id: item.id) } },
                delete: { pendingDelete = [$0] }, onBrowse: {
                    if galleryChromeVisible { withAnimation(.easeOut(duration: 0.18)) { galleryChromeVisible = false } }
                })
                .ignoresSafeArea()
            if galleryChromeVisible {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Button { presentationRaw = GalleryPresentation.album.rawValue } label: {
                            galleryChromeIcon("chevron.left")
                        }.accessibilityLabel("返回相册")
                        Spacer()
                        Button {
                            directionRaw = (direction == .vertical ? GalleryDirection.horizontal : .vertical).rawValue
                        } label: { galleryChromeIcon(direction.symbol) }
                            .accessibilityLabel(direction == .vertical ? "切换为左右浏览" : "切换为上下浏览")
                            .accessibilityValue(direction.title)
                            .accessibilityIdentifier("gallery.direction")
                        Menu {
                            Picker("浏览方向", selection: $directionRaw) {
                                ForEach(GalleryDirection.allCases) { mode in
                                    Label(mode.title, systemImage: mode.symbol).tag(mode.rawValue)
                                }
                            }
                            Toggle("显示作品信息", isOn: $showArtworkInfo)
                            Button(recentOnly ? "查看全部作品" : "只看最近作品", systemImage: "line.3.horizontal.decrease") {
                                recentOnly.toggle()
                            }
                            Button("选择作品", systemImage: "checkmark.circle") { editing = true; selectedIDs.removeAll() }
                            PhotosPicker(selection: $pickerItem, matching: PhotoImport.pickerFilter,
                                         preferredItemEncoding: PhotoImport.preferredEncoding) {
                                Label("导入照片", systemImage: "plus")
                            }
                        } label: { galleryChromeIcon("ellipsis") }
                            .accessibilityLabel("画廊选项")
                    }
                    .disabled(model.busy)
                    Spacer()
                    if let item = focusedArtwork {
                        HStack(alignment: .bottom, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                if showArtworkInfo {
                                    Text(item.title).font(.subheadline.weight(.medium)).lineLimit(2)
                                    Text(item.createdAt, format: .dateTime.year().month().day()).font(.caption)
                                }
                                Text("\((items.firstIndex(where: { $0.id == item.id }) ?? 0) + 1) / \(items.count)")
                                    .font(.caption.monospacedDigit())
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(GalleryWallPalette.paper.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
                            Spacer()
                            Button { Task { await model.openImport(id: item.id) } } label: {
                                galleryChromeIcon("slider.horizontal.3")
                            }.disabled(model.busy).accessibilityLabel("编辑当前作品")
                        }
                    }
                }
                .foregroundStyle(GalleryWallPalette.ink)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .transition(.opacity)
            }
            if model.busy || model.errorText != nil {
                VStack { CollectionStatus(model: model).background(Ink.void); Spacer() }
            }
        }
        .background(GalleryWallPalette.wall.ignoresSafeArea())
        .accessibilityAction(named: "显示画廊操作") { galleryChromeVisible = true }
        .accessibilityAction(named: "返回相册") { presentationRaw = GalleryPresentation.album.rawValue }
    }

    private func galleryChromeIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 18, weight: .medium))
            .foregroundStyle(GalleryWallPalette.ink)
            .frame(width: 44, height: 44)
            .background(GalleryWallPalette.paper.opacity(0.92), in: Circle())
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    private var deleteTitle: String {
        if pendingDelete.count == 1 {
            return pendingDelete.first?.isVariant == true ? "删除这个保存方案？" : "删除这张导入照片？"
        }
        return "删除选中的 \(pendingDelete.count) 件作品？"
    }

    private var presentationPicker: some View {
        HStack(spacing: 4) {
            ForEach(GalleryPresentation.allCases) { mode in
                Button { presentationRaw = mode.rawValue } label: {
                    Label(mode.title, systemImage: mode.systemImage)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(presentation == mode ? Ink.void : Ink.mute)
                        .background(presentation == mode ? Ink.ivory : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityAddTraits(presentation == mode ? .isSelected : [])
                .accessibilityIdentifier("gallery.presentation.\(mode.rawValue)")
            }
        }
        .padding(4)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var collectionToolbar: some View {
        HStack(spacing: 24) {
            filterTab("全部", recent: false)
            filterTab("最近", recent: true)
            Spacer(minLength: 8)
            PhotosPicker(selection: $pickerItem, matching: PhotoImport.pickerFilter,
                         preferredItemEncoding: PhotoImport.preferredEncoding) {
                Image(systemName: "plus").collectionIcon()
            }
            .disabled(model.busy)
            .accessibilityLabel("导入照片")
        }
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.hairline).frame(height: 1).padding(.horizontal, 20) }
    }

    private func filterTab(_ title: String, recent: Bool) -> some View {
        Button { recentOnly = recent } label: {
            Text(title)
                .font(.headline)
                .foregroundStyle(recentOnly == recent ? Ink.ivory : Ink.mute)
                .frame(minWidth: 44, minHeight: 48)
                .overlay(alignment: .bottom) {
                    if recentOnly == recent {
                        Capsule().fill(Ink.amber).frame(height: 3).padding(.bottom, 1)
                    }
                }
        }
        .accessibilityAddTraits(recentOnly == recent ? .isSelected : [])
        .accessibilityHint(recent ? "显示最近十二件作品" : "显示全部作品")
    }

    private func gridContent(landscape: Bool) -> some View {
        let count: Int
        switch hangMode {
        case .salon: count = landscape ? 4 : 3
        case .row: count = landscape ? 3 : 2
        default: count = landscape ? 4 : 2
        }
        let spacing: CGFloat = hangMode == .row ? 22 : 12
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(recentOnly ? "最近 \(items.count) 件" : "\(items.count) 件作品")
                    .font(.subheadline)
                    .foregroundStyle(Ink.mute)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: count), spacing: 20) {
                    ForEach(items) { item in
                        itemCell(item, imageAspect: hangMode == .row ? 1 : 0.84)
                    }
                }
                sampleButton.padding(.top, 8)
            }
            .padding(20)
        }
    }

    private func itemCell(_ item: GalleryItem, imageAspect: CGFloat) -> some View {
        Button { activate(item) } label: {
            VStack(alignment: .leading, spacing: 8) {
                CollectionPhoto(url: gallery.thumbURL(for: item), fallback: item.isVariant ? nil : gallery.originalURL(for: item))
                    .aspectRatio(imageAspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(alignment: .topTrailing) {
                        if editing {
                            Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(selectedIDs.contains(item.id) ? Ink.void : Ink.ivory, Ink.amber)
                                .padding(10)
                                .background(.black.opacity(0.3), in: Circle())
                                .padding(4)
                        }
                    }
                    .overlay {
                        if selectedIDs.contains(item.id) {
                            RoundedRectangle(cornerRadius: 4).stroke(Ink.amber, lineWidth: 2)
                        }
                    }
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Ink.ivory)
                    .lineLimit(2)
                if item.isVariant {
                    Text("保存方案").font(.caption).foregroundStyle(Ink.mute)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(model.busy)
        .accessibilityLabel("\(item.title)\(item.isVariant ? "，保存方案" : "")")
        .accessibilityHint(editing ? "选择或取消选择" : "打开编辑")
        .accessibilityAddTraits(selectedIDs.contains(item.id) ? .isSelected : [])
        .contextMenu {
            Button("打开编辑") {
                guard !model.busy else { return }
                Task { await model.openImport(id: item.id) }
            }
            .disabled(model.busy)
            Button("删除", role: .destructive) { pendingDelete = [item] }
                .disabled(model.busy)
        }
    }

    private func singleContent(height: CGFloat) -> some View {
        let index = min(focusIndex, max(0, items.count - 1))
        return ScrollView {
            if items.indices.contains(index) {
                let item = items[index]
                VStack(spacing: 16) {
                    Button { activate(item) } label: {
                        CollectionPhoto(
                            url: item.isVariant ? gallery.thumbURL(for: item) : gallery.originalURL(for: item),
                            fallback: item.isVariant ? nil : gallery.thumbURL(for: item), fit: true
                        )
                            .frame(height: height)
                            .contentShape(Rectangle())
                            .overlay(alignment: .topTrailing) {
                                if editing {
                                    Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title).foregroundStyle(Ink.amber).padding(16)
                                }
                            }
                    }
                    .disabled(model.busy)
                    .accessibilityLabel(item.title)
                    Text(item.title).font(.headline).foregroundStyle(Ink.ivory)
                    HStack(spacing: 24) {
                        Button { focusIndex = max(0, index - 1) } label: {
                            Image(systemName: "chevron.left").collectionIcon()
                        }
                        .disabled(index == 0).opacity(index == 0 ? 0.35 : 1).accessibilityLabel("上一幅")
                        Text("\(index + 1) / \(items.count)").font(.subheadline.monospacedDigit()).foregroundStyle(Ink.mute)
                        Button { focusIndex = min(items.count - 1, index + 1) } label: {
                            Image(systemName: "chevron.right").collectionIcon()
                        }
                        .disabled(index == items.count - 1).opacity(index == items.count - 1 ? 0.35 : 1).accessibilityLabel("下一幅")
                    }
                    sampleButton
                }
                .padding(.vertical, 16)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 16) {
            Menu {
                if presentation == .album {
                    Picker("相册布局", selection: $hangModeRaw) {
                        ForEach(GalleryHangMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage).tag(mode.rawValue)
                        }
                    }
                }
                Button("打开内置色卡", systemImage: "camera.filters") {
                    Task { await model.openSampleInEditor() }
                }
            } label: {
                Image(systemName: presentation == .album ? hangMode.systemImage : "ellipsis").collectionIcon(color: Ink.amber)
            }
            .disabled(model.busy)
            .accessibilityLabel(presentation == .album ? "相册布局与内置色卡" : "更多作品操作")
            Rectangle().fill(Ink.hairline).frame(width: 1, height: 22)
            if editing {
                Button(selectedIDs.count == items.count ? "取消全选" : "全选") {
                    if selectedIDs.count == items.count { selectedIDs.removeAll() }
                    else { selectedIDs = Set(items.map(\.id)) }
                }
                .font(.subheadline).frame(minHeight: 44)
                Spacer(minLength: 0)
                Button {
                    batchSelection = GalleryBatchSelection(items: items.filter { selectedIDs.contains($0.id) })
                } label: { Label("批量", systemImage: "square.and.arrow.up.on.square") }
                .font(.subheadline).frame(minHeight: 44)
                .disabled(selectedIDs.isEmpty || model.busy)
                .accessibilityLabel("批量处理与导出所选照片，每批最多50张")
                Button("删除（\(selectedIDs.count)）", role: .destructive) {
                    pendingDelete = gallery.items.filter { selectedIDs.contains($0.id) }
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(Ink.ember)
                .frame(minHeight: 44)
                .disabled(selectedIDs.isEmpty || model.busy)
            } else {
                Text("点按照片继续编辑")
                    .font(.subheadline)
                    .foregroundStyle(Ink.mute)
                    .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(Ink.ivory)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Ink.void)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hairline).frame(height: 1) }
    }

    private var emptyGallery: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48, weight: .ultraLight)).foregroundStyle(Ink.amber)
                Text("你的作品，从这里开始").font(.title3.weight(.semibold)).foregroundStyle(Ink.ivory)
                Text("点右上角 ＋ 导入照片\n照片和保存方案都会保留在这里。")
                    .font(.subheadline).foregroundStyle(Ink.mute).multilineTextAlignment(.center)
                sampleButton
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 60)
        }
    }

    private var sampleButton: some View {
        Button { Task { await model.openSampleInEditor() } } label: {
            Label("试试内置色卡", systemImage: "camera.filters")
                .font(.subheadline.weight(.medium)).foregroundStyle(Ink.mute)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(model.busy)
    }

    private func activate(_ item: GalleryItem) {
        guard !model.busy else { return }
        if editing {
            if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) }
            else { selectedIDs.insert(item.id) }
        } else {
            Task { await model.openImport(id: item.id) }
        }
    }
}

// MARK: - Shared collection chrome and bounded, off-main-thread image loading

private struct CollectionHeader<Leading: View, Trailing: View>: View {
    var title: String
    var brand = false
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ObsidianHeader(title: title, brand: brand, leading: leading, trailing: trailing)
    }
}

private extension Image {
    func collectionIcon(color: Color = Ink.ivory) -> some View {
        self.font(.system(size: 21, weight: .regular))
            .foregroundStyle(color)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

private struct CollectionStatus: View {
    @ObservedObject var model: LabModel
    var body: some View {
        if let error = model.errorText {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                Text(error).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                Button { model.errorText = nil } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .accessibilityLabel("关闭错误提示")
            }
            .foregroundStyle(Ink.ember)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .accessibilityElement(children: .contain)
        } else if model.busy {
            HStack(spacing: 10) {
                ProgressView().tint(Ink.amber)
                Text(model.status).font(.subheadline).foregroundStyle(Ink.mute)
            }
            .padding(12)
        }
    }
}

private struct CollectionPhoto: View {
    let url: URL
    var fallback: URL? = nil
    var fit = false
    @State private var image: UIImage?
    @State private var finished = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Ink.surface
                if let image {
                    Image(uiImage: image).resizable()
                        .aspectRatio(contentMode: fit ? .fit : .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else if finished {
                    Image(systemName: "photo").foregroundStyle(Ink.mute).font(.title2)
                        .accessibilityLabel("暂时无法加载缩略图")
                } else {
                    ProgressView().tint(Ink.mute)
                }
            }
        }
        .task(id: url) {
            image = nil
            finished = false
            let loaded = await CollectionThumbnailLoader.shared.load(url: url, fallback: fallback)
            guard !Task.isCancelled else { return }
            image = loaded
            finished = true
        }
    }
}

/// Serial actor limits decoding concurrency to one; the cost-bounded cache holds thumbnails only.
actor CollectionThumbnailLoader {
    static let shared = CollectionThumbnailLoader()
    private let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.countLimit = 60
        return cache
    }()

    func load(url: URL, fallback: URL?) -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        for sourceURL in [url, fallback].compactMap({ $0 }) {
            guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1200,
                    kCGImageSourceShouldCacheImmediately: true,
                  ] as CFDictionary)
            else { continue }
            let image = UIImage(cgImage: cgImage)
            cache.setObject(image, forKey: url as NSURL, cost: cgImage.bytesPerRow * cgImage.height)
            return image
        }
        return nil
    }
}
