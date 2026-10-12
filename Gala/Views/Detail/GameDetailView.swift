import SwiftUI
import GalaKit

/// One game's page: its cover blurred into a dark backdrop, the essentials centred on top.
struct GameDetailView: View {
    let game: Game
    let library: LibraryViewModel
    let gameVM: GameViewModel

    private var isActive: Bool { gameVM.activeGameID == game.id }
    private var isRunning: Bool { isActive && gameVM.isRunning }
    private var isSettingUp: Bool { isActive && gameVM.isSettingUp }
    private var errorMessage: String? { isActive ? gameVM.errorMessage : nil }

    var body: some View {
        let cover = library.cover(for: game)
        GeometryReader { proxy in
            ScrollView {
                HStack(alignment: .center, spacing: 46) {
                    CoverArt(title: game.title, image: cover)
                        .frame(width: 250, height: 353)
                        .shadow(color: .black.opacity(0.5), radius: 30, y: 18)

                    info
                        .frame(maxWidth: 430, alignment: .leading)
                }
                .padding(48)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
        }
        .background { AmbientBackground(image: cover, style: .detail) }
        // The page keeps its dark look in the light appearance too.
        .environment(\.colorScheme, .dark)
        .toolbarColorScheme(.dark, for: .windowToolbar)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .hidingWindowTitle()
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(game.title)
                .font(.system(size: 31, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let developer = game.developer {
                Text(developer)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            statusLine
                .padding(.top, 14)

            HStack(spacing: 10) {
                Button(action: primaryAction) {
                    Label(primaryTitle, systemImage: game.isRuntimeConfigured ? "play.fill" : "wrench.and.screwdriver.fill")
                        .frame(minWidth: 76)
                }
                .galaButtonStyle(prominent: true)
                .disabled(gameVM.isBusy)

                Menu {
                    GameMenuItems(game: game, library: library, gameVM: gameVM)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 18, height: 18)
                }
                .menuIndicator(.hidden)
                .galaButtonStyle()
                .buttonBorderShape(.circle)
                .fixedSize()
                .help("更多")
            }
            .controlSize(.large)
            .padding(.top, 18)

            if isSettingUp {
                progressPanel
                    .padding(.top, 16)
            } else if let errorMessage {
                errorPanel(errorMessage)
                    .padding(.top, 16)
            }

            stats
                .padding(.top, 22)

            if let description = game.description, !description.isEmpty {
                Text(Self.plainText(description))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .lineLimit(7)
                    .padding(.top, 20)
            }
        }
        .foregroundStyle(.white)
    }

    private var statusLine: some View {
        let (color, text): (Color, String) = {
            if isRunning { return (.green, "运行中") }
            if isSettingUp { return (.blue, "正在配置运行环境") }
            if errorMessage != nil { return (.orange, "上次没能启动") }
            guard game.isRuntimeConfigured else { return (.gray, "还没有配置运行环境") }
            return (.green, "就绪 · \(game.engine?.displayName ?? "未识别引擎")")
        }()
        return HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .foregroundStyle(.secondary)
        }
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

    private var stats: some View {
        HStack(spacing: 30) {
            stat("游玩时间", PlayTime.text(game.totalPlayTime))
            stat("上次游玩", game.lastPlayedAt?.formatted(.relative(presentation: .named).locale(Locale(identifier: "zh_CN"))) ?? "—")
            if let rating = game.rating {
                stat("VNDB 评分", String(format: "%.0f", rating))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .galaGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
        }
    }

    private var progressPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let progress = gameVM.setupProgress {
                ProgressView(value: progress)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            Text(gameVM.setupStatus)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .galaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func errorPanel(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("没能启动")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(8)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .galaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// VNDB descriptions carry BBCode such as [url=...]...[/url]; show only the words.
    static func plainText(_ description: String) -> String {
        description.replacingOccurrences(of: #"\[/?[a-zA-Z]+(=[^\]]*)?\]"#, with: "", options: .regularExpression)
    }
}
