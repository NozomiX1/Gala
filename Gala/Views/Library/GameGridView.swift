import SwiftUI
import GalaKit

struct GameGridView: View {
    let games: [Game]
    @Binding var selectedGameId: UUID?
    let imageCache: ImageCache
    let onLaunch: (Game) -> Void
    let onDelete: (Game) -> Void
    let onChangeExe: (Game) -> Void
    let onSetStatus: (Game, GameStatus) -> Void
    let onToggleFavorite: (Game) -> Void

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200))]

    var body: some View {
        if games.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(games) { game in
                        GameCoverCard(
                            game: game,
                            isSelected: selectedGameId == game.id,
                            imageCache: imageCache,
                            onLaunch: { onLaunch(game) },
                            onDelete: { onDelete(game) },
                            onChangeExe: { onChangeExe(game) },
                            onSetStatus: { status in onSetStatus(game, status) },
                            onToggleFavorite: { onToggleFavorite(game) }
                        )
                        .onTapGesture {
                            selectedGameId = game.id
                        }
                    }
                }
                .padding()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.square.dashed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("还没有游戏")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("点击 + 添加你的第一个游戏")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
