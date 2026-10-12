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

    @State private var viewedScreenshot: VNDBScreenshot?

    private var detail: VNDBDetail? { library.detail(for: game) }
    private var screenshots: [VNDBScreenshot] { detail?.safeScreenshots ?? [] }
    /// Something sits between the title and the actions: a status panel, screenshots, or their placeholders.
    private var hasMiddle: Bool {
        isSettingUp || errorMessage != nil || !screenshots.isEmpty || (game.vndbId != nil && detail == nil)
    }

    var body: some View {
        let cover = library.cover(for: game)
        GeometryReader { proxy in
            ScrollView {
                HStack(alignment: hasMiddle ? .top : .center, spacing: 46) {
                    CoverArt(title: game.title, image: cover)
                        .frame(width: Self.coverSize.width, height: Self.coverSize.height)
                        .shadow(color: .black.opacity(0.5), radius: 30, y: 18)

                    // As tall as the cover: the title hangs from its top edge, the actions sit on its bottom edge.
                    // With nothing for the middle, the column shrinks to its content and centres on the cover instead.
                    info
                        .frame(width: 420, alignment: .leading)
                        .frame(minHeight: hasMiddle ? Self.coverSize.height : nil, alignment: .top)
                }
                // Without this the row stretches to the window's height and the actions drop to the bottom edge.
                .fixedSize(horizontal: false, vertical: true)
                .padding(48)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
        }
        .background { AmbientBackground(image: cover, style: .detail) }
        .overlay { screenshotViewer }
        .task(id: game.vndbId) { await library.loadDetail(for: game) }
        // The page keeps its dark look in the light appearance too.
        .environment(\.colorScheme, .dark)
        .toolbarColorScheme(.dark, for: .windowToolbar)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .hidingWindowTitle()
    }

    private static let coverSize = CGSize(width: 250, height: 353)

    private var info: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(game.title)
                .font(.system(size: 34, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let chineseTitle = detail?.chineseTitle, chineseTitle != game.title {
                Text(chineseTitle)
                    .font(.title3)
                    .padding(.top, 4)
            }
            if !byline.isEmpty {
                Text(byline)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            statusLine
                .padding(.top, 14)

            if hasMiddle {
                Spacer(minLength: 18)
                if isSettingUp {
                    progressPanel
                } else if let errorMessage {
                    errorPanel(errorMessage)
                } else {
                    screenshotStrip
                }
                Spacer(minLength: 18)
            } else {
                Spacer()
                    .frame(height: 22)
            }

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

            stats
                .padding(.top, 18)
        }
        .foregroundStyle(.white)
    }

    /// Developer and release year, whichever are known.
    private var byline: String {
        [game.developer, game.releasedAt.map { String($0.prefix(4)) }]
            .compactMap { $0 }
            .joined(separator: " · ")
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
            if let minutes = detail?.lengthMinutes, minutes > 0 {
                stat("通关时长", "约 \(max(1, Int((Double(minutes) / 60).rounded()))) 小时")
            }
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

    /// Up to three screenshots; grey slots stand in while they are being fetched.
    private var screenshotStrip: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                let shot = screenshots.indices.contains(index) ? screenshots[index] : nil
                Button {
                    viewedScreenshot = shot
                } label: {
                    Color.white.opacity(0.08)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay {
                            if let shot {
                                AsyncImage(url: URL(string: shot.url)) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Color.clear
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(shot == nil)
                .opacity(shot == nil && detail != nil ? 0 : 1)
            }
        }
    }

    /// The clicked screenshot at full size. Clicking it shows the next one; clicking around it closes.
    @ViewBuilder
    private var screenshotViewer: some View {
        if let shot = viewedScreenshot {
            ZStack {
                Color.black.opacity(0.75)
                    .ignoresSafeArea()
                    .onTapGesture { viewedScreenshot = nil }
                AsyncImage(url: URL(string: shot.url)) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(56)
                .onTapGesture {
                    let index = screenshots.firstIndex(of: shot) ?? 0
                    viewedScreenshot = screenshots[(index + 1) % screenshots.count]
                }
            }
            .onExitCommand { viewedScreenshot = nil }
            .transition(.opacity)
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
}
