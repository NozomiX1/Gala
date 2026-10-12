import SwiftUI
import GalaKit

struct GameDetailView: View {
    let game: Game
    let viewModel: LibraryViewModel
    @State private var gameVM = GameViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 20) {
                    coverImage
                        .frame(width: 200, height: 283)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 4)

                    VStack(alignment: .leading, spacing: 8) {
                        if let originalTitle = game.originalTitle {
                            Text(originalTitle)
                                .font(.title.bold())
                            Text(game.title)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(game.title)
                                .font(.title.bold())
                        }

                        if let developer = game.developer {
                            Text(developer)
                                .foregroundStyle(.secondary)
                        }

                        if let engine = game.engine {
                            Label(engine.displayName, systemImage: "gearshape")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.blue.opacity(0.1))
                                .clipShape(Capsule())
                        }

                        Spacer()

                        if gameVM.isSettingUp {
                            VStack(spacing: 4) {
                                if let setupProgress = gameVM.setupProgress {
                                    ProgressView(value: setupProgress)
                                        .frame(width: 160)
                                } else {
                                    ProgressView()
                                }
                                Text(gameVM.setupStatus)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 200)
                            }
                        } else {
                            Button {
                                if game.isRuntimeConfigured {
                                    gameVM.launchGame(game, viewModel: viewModel)
                                } else {
                                    gameVM.configureRuntime(for: game, viewModel: viewModel)
                                }
                            } label: {
                                Label(
                                    primaryButtonTitle,
                                    systemImage: primaryButtonIcon
                                )
                                .frame(width: 130)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(gameVM.isRunning)
                        }

                        if let error = gameVM.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                }

                Divider()

                HStack(spacing: 30) {
                    statItem(label: "游玩时间", value: formatPlayTime(game.totalPlayTime))
                    if let lastPlayed = game.lastPlayedAt {
                        statItem(label: "上次游玩", value: lastPlayed.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let rating = game.rating {
                        statItem(label: "VNDB 评分", value: String(format: "%.0f", rating))
                    }
                }

                if let description = game.description {
                    Text("简介")
                        .font(.headline)
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        if let coverPath = game.coverImagePath,
           let data = viewModel.imageCache.load(forKey: URL(fileURLWithPath: coverPath).lastPathComponent),
           let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(
                    colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "gamecontroller")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var primaryButtonTitle: String {
        if gameVM.isRunning { return "运行中..." }
        return game.isRuntimeConfigured ? "启动" : "配置环境"
    }

    private var primaryButtonIcon: String {
        if gameVM.isRunning { return "stop.circle" }
        return game.isRuntimeConfigured ? "play.fill" : "wrench.and.screwdriver"
    }

    private func formatPlayTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours)小时\(minutes)分钟" }
        if minutes > 0 { return "\(minutes)分钟" }
        return "未游玩"
    }
}
