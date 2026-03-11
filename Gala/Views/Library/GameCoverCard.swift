import SwiftUI
import GalaKit

struct GameCoverCard: View {
    let game: Game
    let isSelected: Bool
    let imageCache: ImageCache
    let onLaunch: () -> Void
    let onDelete: () -> Void
    let onChangeExe: () -> Void
    let onSetStatus: (GameStatus) -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            coverImage
                .frame(width: 150, height: 212)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                )
                .shadow(radius: isSelected ? 4 : 2)

            Text(game.originalTitle ?? game.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 150)

            if game.totalPlayTime > 0 {
                Text(formatPlayTime(game.totalPlayTime))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button { onLaunch() } label: {
                Label("启动游戏", systemImage: "play.fill")
            }

            Button { onToggleFavorite() } label: {
                Label(game.isFavorite ? "取消收藏" : "收藏", systemImage: game.isFavorite ? "star.slash" : "star")
            }

            Divider()

            Button { onSetStatus(game.status == .completed ? .backlog : .completed) } label: {
                Label(game.status == .completed ? "取消通关" : "标记为已通关", systemImage: game.status == .completed ? "checkmark.circle.badge.xmark" : "checkmark.circle")
            }

            Button { onChangeExe() } label: {
                Label("更改启动文件", systemImage: "doc.badge.gearshape")
            }

            Divider()

            Button(role: .destructive) { onDelete() } label: {
                Label("删除游戏", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        if let coverPath = game.coverImagePath,
           let data = imageCache.load(forKey: URL(fileURLWithPath: coverPath).lastPathComponent),
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
                VStack {
                    Image(systemName: "gamecontroller")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(String(game.title.prefix(1)))
                        .font(.largeTitle.bold())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formatPlayTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
