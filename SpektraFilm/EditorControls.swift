import SwiftUI

private enum EditorTool: String, CaseIterable {
    case adjust = "调整", film = "胶片", frame = "相框", text = "文字", watermark = "水印"
    var icon: String {
        switch self {
        case .film: "film"
        case .adjust: "slider.horizontal.3"
        case .frame: "square"
        case .watermark: "drop"
        case .text: "text.badge.plus"
        }
    }
}

struct EditorControls: View {
    @ObservedObject var model: LabModel
    var panelHeight: CGFloat = 218
    var onOpenFrames: () -> Void
    var onEditIdentity: () -> Void
    @State private var tool = EditorTool.adjust
    @State private var papers = false
    @State private var familyID: String?

    private var selectedFamily: String { familyID ?? model.frameCatalog.frames.first(where: { $0.id == model.frame.activeFrameId })?.familyId ?? "" }
    private var thumbnailTaskID: String {
        "\(tool.rawValue)|\(papers)|\(model.sourceTitle)|\(model.filmID)|\(model.paperID)|\(model.exposureEV)"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch tool {
                    case .film: filmPanel
                    case .adjust: AdjustmentControls(model: model)
                    case .frame: framePanel
                    case .watermark: watermarkPanel
                    case .text: PhotoTextPanel(model: model)
                    }
                }
                .padding(.vertical, tool == .adjust ? 8 : 12)
            }
            .frame(height: panelHeight)
            Rectangle().fill(Ink.hairline).frame(height: 0.5)
            HStack(spacing: 0) {
                ForEach(EditorTool.allCases, id: \.self) { item in
                    Button { tool = item } label: {
                        VStack(spacing: 6) {
                            Image(systemName: item.icon).font(.system(size: 22, weight: .regular))
                            Text(item.rawValue).font(.caption.weight(.medium))
                        }
                        .foregroundStyle(tool == item ? Ink.amber : Ink.ivory)
                        .frame(maxWidth: .infinity, minHeight: 65)
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(tool == item ? [.isSelected] : [])
                }
            }
        }
        .task(id: thumbnailTaskID) {
            if tool == .film { await model.requestCatalogThumbnails(papers: papers) }
        }
        .task(id: "\(tool.rawValue)|\(model.watermark.hashValue)|\(model.watermarkContext)") {
            if tool == .watermark { await model.requestWatermarkThumbnails() }
        }
        .onChange(of: tool) { _, _ in UISelectionFeedbackGenerator().selectionChanged() }
    }

    private var filmPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                category("胶片", selected: !papers) { papers = false }
                category("相纸", selected: papers) { papers = true }
                Spacer()
            }.padding(.horizontal, 20)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(model.stocks(papers: papers)) { stock in
                            stockTile(stock)
                        }
                    }.padding(.horizontal, 20)
                }
                .onAppear { proxy.scrollTo(papers ? model.paperID : model.filmID, anchor: .center) }
                .onChange(of: papers) { _, value in proxy.scrollTo(value ? model.paperID : model.filmID, anchor: .center) }
                .onChange(of: model.favoriteFilms) { _, _ in
                    guard !papers, let first = model.stocks(papers: false).first else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(first.id, anchor: .leading) }
                }
                .onChange(of: model.favoritePapers) { _, _ in
                    guard papers, let first = model.stocks(papers: true).first else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(first.id, anchor: .leading) }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(model.stockCode(model.filmID, papers: false))  \(model.filmLabel)")
                Text("\(model.stockCode(model.paperID, papers: true))  \(model.catalog.paper(model.paperID)?.name ?? "")")
            }
            .font(.caption).foregroundStyle(Ink.mute)
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 20)
        }
    }

    private func stockTile(_ stock: Stock) -> some View {
        let selected = stock.id == (papers ? model.paperID : model.filmID)
        let favorite = model.isFavorite(stock.id, papers: papers)
        return thumbnail(title: model.stockCode(stock.id, papers: papers),
                         image: model.catalogThumbs["\(papers ? "paper" : "film"):\(stock.id)"],
                         selected: selected, symbol: "film", captionHeight: 16)
            .overlay(alignment: .topTrailing) {
                if favorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.amber)
                        .padding(5).background(Ink.void.opacity(0.85), in: Circle())
                        .padding(5)
                }
            }
            .contentShape(Rectangle())
            .gesture(LongPressGesture(minimumDuration: 0.45)
                .exclusively(before: TapGesture())
                .onEnded { result in
                    switch result {
                    case .first:
                        model.toggleFavorite(stock.id, papers: papers)
                    case .second:
                        selectStock(stock.id)
                    }
                })
            .id(stock.id)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.stockCode(stock.id, papers: papers))，\(stock.name)")
            .accessibilityValue(favorite ? "已收藏" : "")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
            .accessibilityAction { selectStock(stock.id) }
            .accessibilityAction(named: favorite ? "取消收藏" : "收藏") {
                model.toggleFavorite(stock.id, papers: papers)
            }
    }

    private func selectStock(_ id: String) {
        if papers { model.selectPaper(id) } else { model.selectFilm(id) }
    }

    private var framePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 22) {
                        ForEach(model.frameCatalog.families) { family in
                            category(family.nameZh, selected: selectedFamily == family.id) { familyID = family.id }
                        }
                    }
                }
                Button(action: onOpenFrames) {
                    Image(systemName: "chevron.right").frame(width: 44, height: 36)
                }.accessibilityLabel("所有相框与比例")
            }.padding(.leading, 20)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        Button { model.chooseNoFrame() } label: {
                            thumbnail(title: "无框", image: model.unframedThumbnail, selected: !model.frame.enabled, symbol: "rectangle.slash")
                        }.id("none")
                        ForEach(model.frameCatalog.frames(in: selectedFamily)) { preset in
                            Button { model.chooseFrame(preset.id) } label: {
                                thumbnail(title: preset.nameZh, image: model.thumbs[preset.id],
                                          selected: model.frame.enabled && model.frame.activeFrameId == preset.id, symbol: "square")
                            }.id(preset.id)
                        }
                    }.padding(.horizontal, 20)
                }
                .onAppear { proxy.scrollTo(model.frame.enabled ? model.frame.activeFrameId : "none", anchor: .center) }
                .onChange(of: selectedFamily) { _, _ in proxy.scrollTo("none", anchor: .leading) }
            }
            ratioRow
        }
    }

    private var ratioRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                Text("比例").foregroundStyle(Ink.mute)
                ForEach(model.frameCatalog.ratioOptions.filter { option in
                    model.frameCatalog.frame(model.frame.activeFrameId)?.allowedRatioIds.contains(option.id) ?? false
                }) { ratio in
                    Button(ratio.label) { model.lockRatio(ratio.id) }
                        .foregroundStyle(model.frame.ratio.mode == "locked" && model.resolvedRatioID == ratio.id ? Ink.amber : Ink.ivory)
                }
                Button("随相框") { model.followFrameRatio() }
                    .foregroundStyle(model.frame.ratio.mode == "followFrame" ? Ink.amber : Ink.ivory)
            }
            .font(.subheadline).frame(minHeight: 36).padding(.horizontal, 20)
        }
        .disabled(!model.frame.enabled)
        .opacity(model.frame.enabled ? 1 : 0.4)
    }

    private var watermarkPanel: some View {
        VStack(spacing: 12) {
            HStack {
                Text("照片署名").font(.headline)
                Spacer()
                Button("编辑署名", action: onEditIdentity).font(.subheadline).foregroundStyle(Ink.amber)
            }.padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    Button { model.setWatermarkEnabled(false) } label: {
                        markTile("无水印", sample: "—", selected: !model.watermark.enabled)
                    }
                    ForEach(model.watermarkCatalog.presets) { preset in
                        Button { model.chooseWatermark(preset.id) } label: {
                            markTile(preset.nameZh, sample: "", image: model.watermarkThumbs[preset.id],
                                     selected: model.watermark.enabled && model.watermark.activeID == preset.id)
                        }
                    }
                }.padding(.horizontal, 20)
            }
            HStack {
                Text("长按照片上的水印可移动").font(.caption).foregroundStyle(Ink.mute)
                Spacer()
                Button("复位") { model.resetWatermarkOffset() }
                    .font(.subheadline).frame(minWidth: 44, minHeight: 36)
                    .disabled(!model.watermark.enabled)
            }.padding(.horizontal, 20)
        }
    }

    private func markTile(_ title: String, sample: String, image: UIImage? = nil, selected: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if !sample.isEmpty {
                    Text(sample).font(.system(size: 17, weight: .medium))
                } else {
                    ProgressView().tint(Ink.mute)
                }
            }
                .frame(width: 112, height: 72)
                .background(Ink.surface, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? Ink.amber : Ink.hairline, lineWidth: selected ? 2 : 0.5))
            Text(title).font(.caption).lineLimit(1)
        }.foregroundStyle(selected ? Ink.amber : Ink.ivory)
    }

    private func category(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title).font(.subheadline.weight(selected ? .semibold : .regular)).fixedSize()
                Capsule().fill(selected ? Ink.amber : .clear).frame(height: 3)
            }
            .foregroundStyle(selected ? Ink.ivory : Ink.mute)
            .frame(minHeight: 34)
        }
    }

    private func thumbnail(title: String, image: UIImage?, selected: Bool, symbol: String,
                           captionHeight: CGFloat = 32) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                Ink.surface
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().padding(3)
                } else {
                    Image(systemName: symbol).font(.title3).foregroundStyle(Ink.mute)
                }
            }
            .frame(width: 96, height: 82)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? Ink.amber : Ink.hairline, lineWidth: selected ? 2 : 0.5))
            Text(title).font(.caption).lineLimit(captionHeight <= 16 ? 1 : 2)
                .frame(width: 96, height: captionHeight, alignment: .topLeading)
                .foregroundStyle(selected ? Ink.amber : Ink.ivory)
        }
    }
}
