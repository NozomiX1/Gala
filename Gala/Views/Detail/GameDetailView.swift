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
                                ProgressView()
                                Text(gameVM.setupStatus)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Button {
                                gameVM.launchGame(game, viewModel: viewModel)
                            } label: {
                                Label(
                                    gameVM.isRunning ? "运行中..." : "启动",
                                    systemImage: gameVM.isRunning ? "stop.circle" : "play.fill"
                                )
                                .frame(width: 120)
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

                if !game.tags.isEmpty {
                    Text("标签")
                        .font(.headline)
                    FlowLayout(spacing: 6) {
                        ForEach(game.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.secondary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
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

    private func statusText(_ status: GameStatus) -> String {
        switch status {
        case .backlog: return "待玩"
        case .playing: return "正在游玩"
        case .completed: return "已通关"
        case .dropped: return "已搁置"
        }
    }

    private func formatPlayTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours)小时\(minutes)分钟" }
        if minutes > 0 { return "\(minutes)分钟" }
        return "未游玩"
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
