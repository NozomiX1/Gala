import SwiftUI
import GalaKit

struct GameGridView: View {
    let games: [Game]
    @Binding var selectedGameId: UUID?
    let imageCache: ImageCache

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
                            imageCache: imageCache
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
            Text("No games yet")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Click + to add your first game")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
