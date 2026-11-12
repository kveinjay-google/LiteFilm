import SwiftUI
import UIKit

enum GalleryPresentation: String, CaseIterable, Identifiable {
    case album, gallery
    var id: String { rawValue }
    var title: String { self == .album ? "相册" : "画廊" }
    var systemImage: String { self == .album ? "square.grid.2x2" : "photo.artframe" }
}

enum GalleryDirection: String, CaseIterable, Identifiable {
    case vertical, horizontal
    var id: Self { self }
    var title: String { self == .vertical ? "上下浏览" : "左右浏览" }
    var symbol: String { self == .vertical ? "arrow.up.and.down" : "arrow.left.and.right" }
    var axis: Axis.Set { self == .vertical ? .vertical : .horizontal }
}

enum GalleryWallPalette {
    static let wall = Color(red: 0.85, green: 0.84, blue: 0.81)
    static let ink = Color(red: 0.19, green: 0.18, blue: 0.16)
    static let paper = Color(red: 0.96, green: 0.95, blue: 0.92)
}

/// Use the system's projected resting point: a strong flick can cross many pages.
/// Quantizing the final origin centers a full-viewport page, including both ends.
enum GalleryPageSnap {
    static func offset(projected: CGFloat, pageLength: CGFloat, count: Int) -> CGFloat {
        guard projected.isFinite, pageLength.isFinite, pageLength > 0, count > 0 else { return 0 }
        let page = min(CGFloat(count - 1), max(0, (projected / pageLength).rounded()))
        return page * pageLength
    }
}

private struct GalleryCenterSnap: ScrollTargetBehavior {
    let direction: GalleryDirection
    let count: Int
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        if direction == .horizontal {
            target.rect.origin.x = GalleryPageSnap.offset(projected: target.rect.minX,
                pageLength: context.containerSize.width, count: count)
            target.rect.origin.y = 0
        } else {
            target.rect.origin.y = GalleryPageSnap.offset(projected: target.rect.minY,
                pageLength: context.containerSize.height, count: count)
            target.rect.origin.x = 0
        }
        target.anchor = .topLeading
    }
}

/// One complete artwork per viewport; collection mutations remain owned by the parent.
struct GalleryWallView: View {
    let items: [GalleryItem]
    let gallery: ImportGalleryStore
    let direction: GalleryDirection
    @Binding var focusedID: String?
    let editing: Bool
    let selectedIDs: Set<String>
    let busy: Bool
    let activate: (GalleryItem) -> Void
    let open: (GalleryItem) -> Void
    let delete: (GalleryItem) -> Void
    var onBrowse: () -> Void = {}

    // Ignore transient nil updates when the axis or viewport is being rebuilt.
    private var position: Binding<String?> {
        Binding(get: { focusedID }, set: { value in
            if let value, items.contains(where: { $0.id == value }) { focusedID = value }
        })
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(direction.axis, showsIndicators: false) {
                    if direction == .horizontal {
                        LazyHStack(spacing: 0) { pages(size: geometry.size) }.scrollTargetLayout()
                    } else {
                        LazyVStack(spacing: 0) { pages(size: geometry.size) }.scrollTargetLayout()
                    }
                }
                .scrollTargetBehavior(GalleryCenterSnap(direction: direction, count: items.count))
                .scrollPosition(id: position, anchor: .center)
                .modifier(GalleryBrowseObserver(focusedID: focusedID, onBrowse: onBrowse))
                .onAppear {
                    if focusedID == nil || !items.contains(where: { $0.id == focusedID }) {
                        focusedID = items.first?.id
                    }
                    if let focusedID { proxy.scrollTo(focusedID, anchor: .center) }
                }
                .onChange(of: geometry.size) { _, _ in
                    if let focusedID { proxy.scrollTo(focusedID, anchor: .center) }
                }
            }
            .id(direction)
        }
        .background(GalleryWallPalette.wall)
        .accessibilityIdentifier("gallery.exhibition")
    }

    private func pages(size: CGSize) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            artwork(item, index: index, size: size)
                .frame(width: size.width, height: size.height)
                .id(item.id)
        }
    }

    private func artwork(_ item: GalleryItem, index: Int, size: CGSize) -> some View {
        Button { activate(item) } label: {
            GalleryMountedPhoto(url: item.isVariant ? gallery.thumbURL(for: item) : gallery.originalURL(for: item),
                fallback: item.isVariant ? nil : gallery.thumbURL(for: item), alreadyFramed: item.isVariant,
                width: max(1, size.width - 40), height: max(1, size.height - 88))
                .overlay(alignment: .topTrailing) {
                    if editing {
                        Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(GalleryWallPalette.ink)
                            .padding(8).background(GalleryWallPalette.paper, in: Circle())
                    }
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
        }
        .disabled(busy)
        .accessibilityLabel("第 \(index + 1) 幅，共 \(items.count) 幅，\(item.title)")
        .accessibilityHint(editing ? "选择或取消选择" : "点按显示或隐藏操作，长按编辑作品")
        .accessibilityIdentifier("gallery.artwork.\(index)")
        .accessibilityAddTraits(selectedIDs.contains(item.id) ? .isSelected : [])
        .accessibilityAction(named: "打开编辑") { if !busy { open(item) } }
        .contextMenu {
            Button("打开编辑") { open(item) }.disabled(busy)
            Button("删除", role: .destructive) { delete(item) }.disabled(busy)
        }
    }
}

/// Mount the actual image bounds, not a cropped thumbnail or a fixed-aspect album tile.
private struct GalleryMountedPhoto: View {
    let url: URL
    let fallback: URL?
    let alreadyFramed: Bool
    let width: CGFloat
    let height: CGFloat
    @State private var image: UIImage?
    @State private var finished = false

    private let paper = Color(red: 0.96, green: 0.95, blue: 0.92)

    var body: some View {
        ZStack {
            if let image {
                let mat: CGFloat = alreadyFramed ? 0 : min(22, min(width, height) * 0.065)
                let edge: CGFloat = alreadyFramed ? 1 : min(5, max(2, height * 0.018))
                let inset = 2 * (mat + edge)
                let scale = min(max(1, width - inset) / max(1, image.size.width),
                                max(1, height - inset) / max(1, image.size.height))
                Image(uiImage: image).resizable()
                    .frame(width: image.size.width * scale, height: image.size.height * scale)
                    .padding(mat)
                    .background(paper)
                    .overlay { Rectangle().stroke(.black.opacity(0.09), lineWidth: 1) }
                    .padding(edge)
                    .background(Color(red: 0.20, green: 0.19, blue: 0.17))
                    .overlay { Rectangle().stroke(.white.opacity(0.15), lineWidth: 1) }
                    .shadow(color: Color(red: 0.22, green: 0.19, blue: 0.15).opacity(0.24), radius: 12, x: 2, y: 10)
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 2)
            } else {
                ZStack {
                    paper
                    if finished {
                        Label("照片暂时无法显示", systemImage: "photo")
                            .font(.caption).foregroundStyle(Color(white: 0.3))
                    } else {
                        ProgressView().tint(.gray)
                    }
                }
                .frame(width: max(1, width - 44), height: height * 0.65)
            }
        }
        .frame(width: width, height: height)
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

/// Observe native scrolling without introducing a competing pan recognizer.
private struct GalleryBrowseObserver: ViewModifier {
    let focusedID: String?
    let onBrowse: () -> Void
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in
                if phase == .interacting { onBrowse() }
            }
        } else {
            content.onChange(of: focusedID) { old, new in
                if old != nil && old != new { onBrowse() }
            }
        }
    }
}
