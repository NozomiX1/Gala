import SwiftUI
import GalaKit

/// The main screen: a wall of covers over a backdrop tinted by the most recently played game.
struct LibraryView: View {
    @Bindable var library: LibraryViewModel
    let gameVM: GameViewModel
    @Binding var filter: LibraryFilter
    let onOpen: (Game) -> Void
    let onAdd: (URL?) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 150), spacing: 28, alignment: .top)]

    var body: some View {
        let games = library.games(matching: filter)
        ScrollView {
            if games.isEmpty {
                emptyState
                    .containerRelativeFrame(.vertical) { height, _ in height * 0.8 }
            } else {
                LazyVGrid(columns: columns, spacing: 30) {
                    ForEach(games) { game in
                        CoverCard(
                            game: game,
                            image: library.cover(for: game),
                            isRunning: gameVM.isRunning && gameVM.activeGameID == game.id,
                            onOpen: { onOpen(game) },
                            onPrimaryAction: { primaryAction(for: game) }
                        )
                        .contextMenu { GameMenuItems(game: game, library: library, gameVM: gameVM) }
                    }
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AmbientBackground(image: library.ambientCover, style: .wall) }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            onAdd(url)
            return true
        }
        .searchable(text: $library.searchText, prompt: "搜索")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("筛选", selection: $filter) {
                    ForEach(LibraryFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onAdd(nil)
                } label: {
                    Label("添加游戏", systemImage: "plus")
                }
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarColorScheme(colorScheme, for: .windowToolbar)
        .hidingWindowTitle()
    }

    private func primaryAction(for game: Game) {
        if game.isRuntimeConfigured {
            gameVM.launchGame(game, viewModel: library)
        } else {
            gameVM.configureRuntime(for: game, viewModel: library)
        }
        // Configuring shows progress, and a failed launch shows why; both live on the detail page.
        onOpen(game)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: library.games.isEmpty ? "plus.square.dashed" : "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text(library.games.isEmpty ? "还没有游戏" : "没有符合条件的游戏")
                .font(.title3)
                .foregroundStyle(.secondary)
            if library.games.isEmpty {
                Text("点右上角的 +，或者把游戏文件夹拖进来")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CoverCard: View {
    let game: Game
    let image: NSImage?
    let isRunning: Bool
    let onOpen: () -> Void
    let onPrimaryAction: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverArt(title: game.title, image: image)
                .frame(width: 150, height: 212)
                .shadow(color: .black.opacity(isHovering ? 0.28 : 0.16), radius: isHovering ? 12 : 6, y: isHovering ? 8 : 3)
                .overlay(alignment: .bottomTrailing) {
                    if isHovering {
                        Button(action: onPrimaryAction) {
                            Image(systemName: game.isRuntimeConfigured ? "play.fill" : "wrench.and.screwdriver.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 32, height: 32)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .galaGlass(in: Circle())
                        .help(game.isRuntimeConfigured ? "启动" : "配置环境")
                        .padding(8)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .offset(y: isHovering ? -3 : 0)

            VStack(alignment: .leading, spacing: 1) {
                Text(game.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 150, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovering)
    }

    private var subtitle: String {
        if isRunning { return "运行中" }
        if !game.isRuntimeConfigured { return "未配置" }
        return PlayTime.text(game.totalPlayTime)
    }
}

/// Actions on a game, shared by the cover's context menu and the detail page's "more" button.
struct GameMenuItems: View {
    let game: Game
    let library: LibraryViewModel
    let gameVM: GameViewModel
    /// The detail page has its own buttons for favourite and completed.
    var includesToggles = true

    var body: some View {
        Button("更改启动文件…", action: changeExecutable)

        Divider()

        if includesToggles {
            Button(game.isFavorite ? "取消收藏" : "收藏") {
                library.toggleFavorite(game)
            }
            Button(game.status == .completed ? "取消通关标记" : "标记为已通关") {
                library.toggleCompleted(game)
            }

            Divider()
        }

        if game.isRuntimeConfigured {
            Button("移除运行环境") {
                library.removeRuntime(for: game)
            }
        }
        Button("从库中移除", role: .destructive) {
            library.removeFromLibrary(game)
        }
    }

    private func changeExecutable() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.exe]
        panel.canChooseDirectories = false
        panel.message = "选择新的启动文件"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var updated = game
        updated.executablePath = url.path
        library.updateGame(updated)
    }
}
