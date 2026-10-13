import SwiftUI
import UniformTypeIdentifiers
import GalaKit

/// Takes a profile as text, from a chat assistant or another user, and shows what it would do before it is used.
/// Nothing is written until 导入并使用.
struct ImportProfileView: View {
    let game: Game
    let library: LibraryViewModel
    /// Called with the game already pointed at the imported profile.
    let onImport: (Game) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var saveError: String?
    /// Whether the environment this one takes over from is removed along with it. Offered only when nothing else needs it.
    @State private var deletesPrevious = true

    private var wineManager: WineManager { library.wineManagerInstance }

    init(game: Game, library: LibraryViewModel, initialText: String = "", onImport: @escaping (Game) -> Void) {
        self.game = game
        self.library = library
        self.onImport = onImport
        _text = State(initialValue: initialText)
    }

    private var outcome: Result<ProfileImport, ProfileImportError>? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do {
            return .success(try ProfileImport.parse(text, userDirectory: wineManager.profilesDirectory))
        } catch let error as ProfileImportError {
            return .failure(error)
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
    }

    var body: some View {
        let outcome = outcome
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("导入运行环境")
                    .font(.title2.weight(.semibold))
                Text("把 AI 助手或别人给你的运行环境粘贴到下面。确认之后会用到「\(game.title)」上。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)

            TextEditor(text: $text)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 96)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("在这里粘贴，或者把 .json 文件拖进来")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .padding(14)
                            .allowsHitTesting(false)
                    }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first, let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
                    text = content
                    return true
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)

            HStack(spacing: 14) {
                Button("粘贴") { text = NSPasteboard.general.string(forType: .string) ?? text }
                Button("选择文件…", action: chooseFile)
                    .buttonStyle(.link)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            ScrollView {
                Group {
                    switch outcome {
                    case nil:
                        Text("粘贴之后，这里会列出它要做的事。")
                            .foregroundStyle(.secondary)
                    case .failure(let error):
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    case .success(let imported):
                        preview(imported)
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
            // Without this the list can open scrolled to its end when the text is already there as the sheet appears.
            .defaultScrollAnchor(.top)
            .frame(height: 204)

            if case .success(let imported) = outcome {
                Divider()
                consequences(imported)
            }

            Divider()

            HStack(spacing: 14) {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("导入并使用") {
                    if case .success(let imported) = outcome { use(imported) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled({ if case .success = outcome { return false } else { return true } }())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 560)
        .alert("没能导入", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("好") {}
        } message: {
            Text(saveError ?? "")
        }
    }

    /// What this file itself asks for, spelled out in full; what it inherits is one line.
    @ViewBuilder
    private func preview(_ imported: ProfileImport) -> some View {
        let detail = wineManager.profiles.detail(of: imported.recipe)
        let own = detail.rows.filter { $0.source == nil && $0.label != "基于" }
        let inherited = detail.rows.filter { $0.source != nil }.count
        let base = imported.recipe.baseID.flatMap { wineManager.profiles.recipe(id: $0)?.name }
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(imported.file.name)
                    .font(.headline)
                Text(detail.summary)
                    .foregroundStyle(.secondary)
                if !imported.absorbed.isEmpty {
                    // It was written on top of these; what is listed below is theirs and its own together.
                    Text("已并入「\(imported.absorbed.map(\.name).joined(separator: "」「"))」的内容，下面列出的是合并后的全部改动。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if own.isEmpty, imported.removals.isEmpty {
                Text("它没有自己的改动，和「\(base ?? "")」完全一样。")
                    .foregroundStyle(.secondary)
            } else if !own.isEmpty {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 5) {
                    ForEach(own) { row in
                        GridRow {
                            Text(row.label)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                            Text(row.value)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if !imported.removals.isEmpty {
                Text("去掉继承来的：" + imported.removals.joined(separator: "、"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if inherited > 0, let base {
                Text("另外继承「\(base)」的 \(inherited) 项。")
                    .foregroundStyle(.secondary)
            }

        }
    }

    /// What confirming will do. Kept out of the scrolling list above so a long file cannot push it out of sight.
    @ViewBuilder
    private func consequences(_ imported: ProfileImport) -> some View {
        let base = imported.recipe.baseID.flatMap { wineManager.profiles.recipe(id: $0)?.name }
        VStack(alignment: .leading, spacing: 8) {
            if let replaced = imported.replaces {
                Label("会替换你已有的运行环境「\(replaced)」。", systemImage: "arrow.triangle.2.circlepath")
            }
            if imported.needsOwnPrefix {
                let source = imported.absorbed.first?.name ?? base
                Label(source.map { "需要新建一个环境：从「\($0)」复制一份，再加上还没有的部分。" } ?? "需要从零新建一个环境，要等几分钟。", systemImage: "shippingbox")
            } else {
                Label("不需要新建环境，直接使用「\(base ?? "")」的环境。", systemImage: "bolt")
            }
            if let previous = removablePrevious(for: imported) {
                Toggle("同时删除「\(previous.name)」（这个游戏现在用的环境，没有别的游戏在用）", isOn: $deletesPrevious)
                    .toggleStyle(.checkbox)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .plainText]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        text = content
    }

    /// The environment the game is on now, when importing this one leaves it with no use: the user's own,
    /// on no other game, and with no other profile written on top of it.
    private func removablePrevious(for imported: ProfileImport) -> RuntimeRecipe? {
        guard let id = game.profileID, id != imported.file.id,
              let previous = wineManager.profiles.recipe(id: id), previous.isUserProvided,
              !library.games.contains(where: { $0.id != game.id && $0.profileID == id }),
              ProfileStore.userProfiles(basedOn: id, in: wineManager.profilesDirectory).isEmpty else { return nil }
        return previous
    }

    private func use(_ imported: ProfileImport) {
        let previous = deletesPrevious ? removablePrevious(for: imported) : nil
        do {
            try imported.save(to: wineManager.profilesDirectory)
        } catch {
            saveError = error.localizedDescription
            return
        }
        wineManager.reloadProfiles()
        let bottleManager = BottleManager(bottlesDirectory: wineManager.bottlesDirectory, wineManager: wineManager)
        // Start from the prefix of the attempt it was written on, which already holds most of it. This has to
        // happen here: once folded flat, the file no longer names that attempt.
        if imported.needsOwnPrefix, let source = imported.absorbed.first {
            bottleManager.seedPrefix(forProfile: imported.file.id, fromProfile: source.id)
        }
        var updated = game
        updated.useProfile(imported.file.id, bottlesDirectory: wineManager.bottlesDirectory, profiles: wineManager.profiles)
        library.updateGame(updated)
        if let previous {
            bottleManager.deletePrefix(ownedByProfile: previous.id)
            try? ProfileStore.deleteUserProfile(id: previous.id, in: wineManager.profilesDirectory)
            wineManager.reloadProfiles()
        }
        dismiss()
        onImport(updated)
    }
}
