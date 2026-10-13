import SwiftUI
import GalaKit

/// One game's page: its cover blurred into a dark backdrop, the essentials centred on top.
struct GameDetailView: View {
    let game: Game
    let library: LibraryViewModel
    let gameVM: GameViewModel

    @State private var sheet: Sheet?
    @State private var advice: [String] = []

    /// One sheet at a time, so the failure sheet can hand over to the run settings or the help text.
    private enum Sheet: String, Identifiable {
        case runSettings, helpRequest, failure, importProfile
        var id: String { rawValue }
    }

    private static let coverSize = CGSize(width: 250, height: 353)

    private var isActive: Bool { gameVM.activeGameID == game.id }
    private var isRunning: Bool { isActive && gameVM.isRunning }
    private var isSettingUp: Bool { isActive && gameVM.isSettingUp }
    private var errorMessage: String? { isActive ? gameVM.errorMessage : nil }

    var body: some View {
        let cover = library.cover(for: game)
        GeometryReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 46) {
                    CoverArt(title: game.title, image: cover)
                        .frame(width: Self.coverSize.width, height: Self.coverSize.height)
                        .shadow(color: .black.opacity(0.5), radius: 30, y: 18)

                    // As tall as the cover: the title hangs from its top edge, the facts sit on its bottom edge.
                    info
                        .frame(width: 430, alignment: .leading)
                        .frame(minHeight: Self.coverSize.height, alignment: .top)
                }
                // Without this the row stretches to the window's height and the facts drop to the bottom edge.
                .fixedSize(horizontal: false, vertical: true)
                .padding(48)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
        }
        .background { AmbientBackground(image: cover, style: .detail) }
        .task(id: game.id) { await library.loadFactsIfMissing(for: game) }
        // Read again when a run ends or the profile changes: both can change what there is to suggest. The log can be large.
        .task(id: "\(game.id)|\(isRunning)|\(game.profileID ?? "")|\(game.launchSwitches)") {
            let game = game, wineManager = library.wineManagerInstance
            advice = await Task.detached { GameRuntime(wineManager: wineManager).advice(for: game) }.value
        }
        // The page keeps its dark look in the light appearance too.
        .environment(\.colorScheme, .dark)
        .toolbarColorScheme(.dark, for: .windowToolbar)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .hidingWindowTitle()
        // Attached after the dark colour scheme above, so the sheets follow the system appearance.
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .runSettings:
                RunSettingsView(game: game, library: library, advice: advice, showsAdvanced: debugRunSettings == "advanced", showsDetail: debugRunSettings == "detail")
            case .helpRequest:
                HelpRequestView(game: game, library: library)
            case .importProfile:
                ImportProfileView(game: game, library: library, initialText: debugValue("GALA_DEBUG_IMPORT") ?? "") { updated in
                    // Straight on to building it: the user has already read what it will do and agreed.
                    gameVM.configureRuntime(for: updated, viewModel: library)
                }
            case .failure:
                FailureView(
                    title: game.title,
                    message: errorMessage ?? "",
                    onChangeSettings: { self.sheet = .runSettings },
                    onCopyHelp: { self.sheet = .helpRequest }
                )
            }
        }
        // A new failure opens its sheet once, also when the page is opened just after the launch failed.
        .onChange(of: isActive && gameVM.hasUnseenFailure && !isSettingUp, initial: true) { _, unseen in
            guard unseen else { return }
            gameVM.hasUnseenFailure = false
            sheet = .failure
        }
        .onAppear {
            if debugRunSettings != nil { sheet = .runSettings }
            if debugValue("GALA_DEBUG_HELP") != nil { sheet = .helpRequest }
            if debugValue("GALA_DEBUG_IMPORT") != nil { sheet = .importProfile }
        }
    }

    /// Set to open the run settings right away, for screenshots; "advanced" also unfolds the advanced fields.
    private var debugRunSettings: String? { debugValue("GALA_DEBUG_RUNSETTINGS") }

    private func debugValue(_ name: String) -> String? {
        #if DEBUG
        ProcessInfo.processInfo.environment[name]
        #else
        nil
        #endif
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 0) {
            // One line always: a long title shrinks instead of wrapping, so every page has the same height.
            Text(game.title)
                .font(.system(size: 38, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            if let chineseTitle = game.chineseTitle, chineseTitle != game.title {
                Text(chineseTitle)
                    .font(.system(size: 17))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 6)
            }
            if !byline.isEmpty {
                Text(byline)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
            }

            statusLine
                .padding(.top, 18)

            // Equal spacers keep the actions midway between the status line and the facts.
            Spacer(minLength: 16)

            actions

            Spacer(minLength: 16)

            facts
        }
        .foregroundStyle(.white)
    }

    /// Developer and release date, whichever are known.
    private var byline: String {
        [game.developer, game.releasedAt]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var statusLine: some View {
        let (color, text): (Color, String) = {
            if isRunning { return (.green, "运行中") }
            if isSettingUp { return (.blue, setupText) }
            if errorMessage != nil { return (.orange, "上次没能启动") }
            return game.isRuntimeConfigured ? (.green, "就绪") : (.gray, "还没有配置运行环境")
        }()
        return HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            if !isRunning, !isSettingUp, errorMessage != nil {
                Button("查看原因") { sheet = .failure }
                    .buttonStyle(.link)
            } else if !isRunning, !isSettingUp, advice.contains(where: { !game.acknowledgedAdvice.contains($0) }) {
                Button("查看建议") { sheet = .runSettings }
                    .buttonStyle(.link)
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: primaryAction) {
                Label(primaryTitle, systemImage: game.isRuntimeConfigured ? "play.fill" : "wrench.and.screwdriver.fill")
                    .frame(minWidth: 76)
            }
            .galaButtonStyle(prominent: true)
            .disabled(gameVM.isBusy)

            iconButton(game.isFavorite ? "star.fill" : "star", help: game.isFavorite ? "取消收藏" : "收藏") {
                library.toggleFavorite(game)
            }
            iconButton(
                game.status == .completed ? "checkmark.circle.fill" : "checkmark.circle",
                help: game.status == .completed ? "取消通关标记" : "标记为已通关"
            ) {
                library.toggleCompleted(game)
            }
            iconButton("slider.horizontal.3", help: "运行设置") {
                sheet = .runSettings
            }
            .disabled(gameVM.isBusy)

            // A Menu draws its own button smaller than its neighbours on some SDK and system pairs, and square on macOS 15.
            // So the look comes from the same button as the others, and an invisible menu on top takes the click.
            iconButton("ellipsis", help: "更多") {}
                .overlay {
                    // The menu's own control is only as large as its label, so the label is given the button's size.
                    GeometryReader { geometry in
                        Menu {
                            Button("复制求助信息…") { sheet = .helpRequest }
                        Button("导入运行环境…") { sheet = .importProfile }
                            Button("导出诊断信息…", action: exportDiagnostics)
                            Divider()
                            GameMenuItems(game: game, library: library, gameVM: gameVM, includesToggles: false)
                        } label: {
                            Color.clear
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.button)
                        .menuIndicator(.hidden)
                        .buttonStyle(.plain)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .help("更多")
                    }
                }
        }
        .controlSize(.extraLarge)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 18, height: 18)
        }
        .galaButtonStyle()
        .buttonBorderShape(.circle)
        .help(help)
    }

    /// The current setup step with its percentage, in the status line so configuring moves nothing on the page.
    private var setupText: String {
        let step = gameVM.setupStatus.isEmpty ? "正在配置运行环境" : gameVM.setupStatus
        guard let progress = gameVM.setupProgress, progress > 0 else { return step }
        return "\(step) \(Int(progress * 100))%"
    }

    private var primaryTitle: String {
        if isRunning { return "运行中" }
        if isSettingUp { return "配置中" }
        return game.isRuntimeConfigured ? "启动" : "配置环境"
    }

    private func primaryAction() {
        if game.isRuntimeConfigured {
            gameVM.launchGame(game, viewModel: library)
        } else {
            gameVM.configureRuntime(for: game, viewModel: library)
        }
    }

    // MARK: - Facts

    /// Two rows of three: the player's own numbers, then facts about the game.
    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: 26, verticalSpacing: 18) {
            GridRow {
                fact("游玩时间", PlayTime.text(game.totalPlayTime))
                fact("上次游玩", game.lastPlayedAt?.formatted(.relative(presentation: .named).locale(Locale(identifier: "zh_CN"))) ?? "—")
                fact("通关时长", game.lengthMinutes.map { "约 \(max(1, Int((Double($0) / 60).rounded()))) 小时" } ?? "—")
            }
            GridRow {
                fact("VNDB 评分", ratingText)
                fact("中文", chineseText)
                fact("引擎", engineText)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .galaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var ratingText: String {
        guard let rating = game.rating else { return "—" }
        let score = String(format: "%.0f", rating)
        return game.voteCount.map { "\(score)（\($0) 人）" } ?? score
    }

    private var engineText: String {
        guard let engine = game.engine, engine != .unknown else { return "未识别" }
        return engine.familyName
    }

    private var chineseText: String {
        switch game.chineseAvailability {
        case .official: return "官方中文"
        case .fan: return "民间汉化"
        case .some(.none): return "无中文"
        case nil: return "—"
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exportDiagnostics() {
        Task { @MainActor in
            let text = await library.diagnostics(for: game).text
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "Gala 诊断 - \(game.title).txt"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try Data(text.utf8).write(to: url)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}
