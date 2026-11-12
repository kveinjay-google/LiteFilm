import SwiftUI
import UIKit

enum GalleryPresentation: String, CaseIterable, Identifiable {
    case album, gallery
    var id: String { rawValue }
    var title: String { self == .album ? "相册" : "画廊" }
    var systemImage: String { self == .album ? "square.grid.2x2" : "photo.artframe" }
}

/// Presentation only: selection, editing and deletion use the collection's existing actions.
struct GalleryWallView: View {
    let items: [GalleryItem]
    let gallery: ImportGalleryStore
    let width: CGFloat
    let editing: Bool
    let selectedIDs: Set<String>
    let busy: Bool
    let activate: (GalleryItem) -> Void
    let open: (GalleryItem) -> Void
    let delete: (GalleryItem) -> Void

    private let wall = Color(red: 0.85, green: 0.84, blue: 0.81)
    private let ink = Color(red: 0.19, green: 0.18, blue: 0.16)
    private var columns: Int { width >= 700 ? 2 : 1 }
    private var contentWidth: CGFloat { min(max(0, width - 48), 1100) }
    private var artworkWidth: CGFloat { (contentWidth - CGFloat(columns - 1) * 48) / CGFloat(columns) }

    var body: some View {
        GeometryReader { geo in
            if geo.size.height < 350 {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 36) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            artwork(item, index: index, size: CGSize(width: min(300, width * 0.44),
                                                                   height: max(60, geo.size.height - 90)))
                                .frame(width: min(300, width * 0.44))
                        }
                    }
                    .frame(minWidth: max(0, width - 48), alignment: items.count == 1 ? .center : .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                }
            } else {
                exhibitionWall
            }
        }
        .background(wall)
        .accessibilityIdentifier("gallery.exhibition")
    }

    private var exhibitionWall: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline) {
                    Text("私人展厅").font(.system(.title3, design: .serif).weight(.medium))
                    Spacer()
                    Text("\(items.count) 件作品").font(.caption.monospacedDigit())
                }
                .foregroundStyle(ink)
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.20)).frame(height: 0.5) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 48), count: columns), spacing: 44) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        artwork(item, index: index, size: CGSize(width: artworkWidth, height: min(420, artworkWidth * 1.08)))
                    }
                }
            }
            .frame(width: contentWidth)
            .padding(.top, 28)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity)
        }
    }

    private func artwork(_ item: GalleryItem, index: Int, size: CGSize) -> some View {
        Button { activate(item) } label: {
            VStack(alignment: .leading, spacing: 18) {
                GalleryMountedPhoto(url: item.isVariant ? gallery.thumbURL(for: item) : gallery.originalURL(for: item),
                                    fallback: item.isVariant ? nil : gallery.thumbURL(for: item),
                                    alreadyFramed: item.isVariant,
                                    width: size.width,
                                    height: size.height)
                    .overlay(alignment: .topTrailing) {
                        if editing {
                            Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(ink)
                                .padding(8)
                                .background(wall, in: Circle())
                        }
                    }
                HStack(alignment: .top, spacing: 12) {
                    Text(String(format: "%02d", index + 1))
                        .font(.caption.monospacedDigit()).foregroundStyle(ink.opacity(0.65))
                        .padding(.top, 3)
                    Rectangle().fill(ink.opacity(0.3)).frame(width: 1, height: 34)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.subheadline.weight(.medium)).lineLimit(2)
                        HStack(spacing: 8) {
                            Text(item.createdAt, format: .dateTime.year().month().day())
                            if item.isVariant { Text("保存方案") }
                        }
                        .font(.caption2).foregroundStyle(ink.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(ink)
                .padding(.horizontal, 6)
            }
            .contentShape(Rectangle())
        }
        .disabled(busy)
        .accessibilityLabel("\(item.title)\(item.isVariant ? "，保存方案" : "")")
        .accessibilityHint(editing ? "选择或取消选择" : "打开编辑")
        .accessibilityAddTraits(selectedIDs.contains(item.id) ? .isSelected : [])
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
