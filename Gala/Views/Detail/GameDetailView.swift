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

                        Button {
                            gameVM.launchGame(game, viewModel: viewModel)
                        } label: {
                            Label(
                                gameVM.isRunning ? "Running..." : "Launch",
                                systemImage: gameVM.isRunning ? "stop.circle" : "play.fill"
                            )
                            .frame(width: 120)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(gameVM.isRunning)

                        if let error = gameVM.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Divider()

                HStack(spacing: 30) {
                    statItem(label: "Play Time", value: formatPlayTime(game.totalPlayTime))
                    if let lastPlayed = game.lastPlayedAt {
                        statItem(label: "Last Played", value: lastPlayed.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let rating = game.rating {
                        statItem(label: "VNDB Rating", value: String(format: "%.0f", rating))
                    }
                    statItem(label: "Status", value: game.status.rawValue.capitalized)
                }

                if let description = game.description {
                    Text("About")
                        .font(.headline)
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                if !game.tags.isEmpty {
                    Text("Tags")
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

    private func formatPlayTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "Not played"
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
