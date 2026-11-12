import Foundation
import SwiftUI

struct SavedRecipe: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var recipe: GalleryRecipe
}

/// Small, local-only recipe library. Spatial edits belong to a photo, never a portable recipe.
@MainActor
final class RecipeBook: ObservableObject {
    @Published private(set) var presets: [SavedRecipe] = []
    @Published private(set) var copied: GalleryRecipe?
    private let defaults: UserDefaults
    private static let key = "litefilm.recipes.v1"
    private static let clipboardKey = "litefilm.recipeClipboard.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([SavedRecipe].self, from: data) {
            presets = Array(saved.prefix(50)).map {
                SavedRecipe(id: $0.id, name: String($0.name.prefix(60)), recipe: Self.portable($0.recipe))
            }
        }
        if let data = defaults.data(forKey: Self.clipboardKey),
           let saved = try? JSONDecoder().decode(GalleryRecipe.self, from: data) { copied = Self.portable(saved) }
    }

    static func portable(_ source: GalleryRecipe) -> GalleryRecipe {
        var recipe = source
        var edits = (source.adjustments ?? PhotoAdjustments()).sanitized()
        edits.geometry = PhotoGeometry()
        edits.retouch = RetouchEdits()
        recipe.adjustments = edits
        recipe.textLayers = PhotoTextLayer.sanitized(source.textLayers ?? [])
        recipe.exposureEV = source.exposureEV.isFinite ? min(2, max(-2, source.exposureEV)) : 0
        return recipe
    }

    func save(name: String, recipe: GalleryRecipe) throws {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !name.isEmpty else { throw EngineError.message("请为配方起一个名字。") }
        guard presets.count < 50 else { throw EngineError.message("最多保存 50 个配方，请先删除不用的配方。") }
        var next = presets
        next.insert(SavedRecipe(name: name, recipe: Self.portable(recipe)), at: 0)
        let data = try JSONEncoder().encode(next)
        defaults.set(data, forKey: Self.key)
        presets = next
    }

    func remove(id: UUID) throws {
        let next = presets.filter { $0.id != id }
        let data = try JSONEncoder().encode(next)
        defaults.set(data, forKey: Self.key)
        presets = next
    }

    func copy(_ recipe: GalleryRecipe) throws {
        let next = Self.portable(recipe)
        let data = try JSONEncoder().encode(next)
        defaults.set(data, forKey: Self.clipboardKey)
        copied = next
    }
}

struct EditHistoryItem: Identifiable {
    let id = UUID()
    let title: String
    let snapshot: EditSnapshot

    static func describe(from old: EditSnapshot, to new: EditSnapshot) -> String {
        var parts: [String] = []
        if old.filmID != new.filmID { parts.append("胶片") }
        if old.paperID != new.paperID { parts.append("相纸") }
        if old.exposureEV != new.exposureEV { parts.append("曝光") }
        if old.adjustments.geometry != new.adjustments.geometry { parts.append("裁剪") }
        if old.adjustments.retouch != new.adjustments.retouch { parts.append("局部修饰") }
        var a = old.adjustments, b = new.adjustments
        a.geometry = PhotoGeometry(); b.geometry = PhotoGeometry()
        a.retouch = RetouchEdits(); b.retouch = RetouchEdits()
        if a != b { parts.append("调色") }
        if old.frame != new.frame { parts.append("相框") }
        if old.watermark != new.watermark { parts.append("水印") }
        if old.textLayers != new.textLayers { parts.append("文字") }
        return parts.isEmpty ? "编辑" : parts.joined(separator: " · ")
    }
}

struct RecipeBookSheet: View {
    @ObservedObject var model: LabModel
    @ObservedObject private var book: RecipeBook
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var message: String?
    @State private var deletion: SavedRecipe?

    init(model: LabModel) { self.model = model; self.book = model.recipeBook }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("为当前配方命名", text: $name)
                    Button("保存当前配方", systemImage: "plus.circle") {
                        do {
                            try book.save(name: name, recipe: model.currentRecipe(portable: true))
                            name = ""; message = "配方已保存"
                        } catch { message = error.localizedDescription }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
                    Button("复制当前调整", systemImage: "doc.on.doc") {
                        do { try book.copy(model.currentRecipe(portable: true)); message = "已复制，可应用到其他照片或批量处理" }
                        catch { message = error.localizedDescription }
                    }.disabled(model.busy)
                    if let copied = book.copied {
                        Button("应用已复制的调整", systemImage: "doc.on.clipboard") {
                            model.applyPortableRecipe(copied); dismiss()
                        }.disabled(model.busy)
                    }
                } footer: {
                    Text("配方包含调色、胶片、相纸、相框、文字和水印。应用时保留目标照片的裁剪和局部修饰。最多保存 50 个。")
                }
                if let message { Text(message).font(.footnote).foregroundStyle(Ink.amber) }
                Section("我的配方（\(book.presets.count)）") {
                    if book.presets.isEmpty { Text("保存喜欢的效果，下次一键使用。").foregroundStyle(Ink.mute) }
                    ForEach(book.presets) { preset in
                        HStack {
                            Button {
                                model.applyPortableRecipe(preset.recipe); dismiss()
                            } label: {
                                Label(preset.name, systemImage: "slider.horizontal.3").frame(maxWidth: .infinity, alignment: .leading)
                            }.disabled(model.busy)
                            Button(role: .destructive) { deletion = preset } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                                .accessibilityLabel("删除配方\(preset.name)")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Ink.void)
            .navigationTitle("我的配方").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .confirmationDialog("删除这个配方？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
                Button("删除", role: .destructive) {
                    if let deletion { do { try book.remove(id: deletion.id) } catch { message = error.localizedDescription } }
                    deletion = nil
                }
            }
        }.tint(Ink.amber).preferredColorScheme(.dark)
    }
}

struct EditHistorySheet: View {
    @ObservedObject var model: LabModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.editHistory.isEmpty { Text("还没有编辑记录").foregroundStyle(Ink.mute) }
                    ForEach(Array(model.editHistory.enumerated()), id: \.element.id) { index, step in
                        Button { model.restoreHistory(id: step.id); dismiss() } label: {
                            HStack {
                                Text(String(format: "%02d", index)).monospacedDigit().foregroundStyle(Ink.mute)
                                Text(step.title)
                                Spacer()
                                if index == model.historyCursor { Image(systemName: "checkmark").foregroundStyle(Ink.amber) }
                            }.frame(minHeight: 36)
                        }.disabled(model.busy)
                    }
                } footer: {
                    Text("记录本次编辑的最近 60 步。点按可回到某一步；回退后继续编辑会开启新分支。切换照片或关闭应用后不保留历史，当前效果仍会保存。")
                }
            }
            .scrollContentBackground(.hidden).background(Ink.void)
            .navigationTitle("编辑历史").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.tint(Ink.amber).preferredColorScheme(.dark)
    }
}
