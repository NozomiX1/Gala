import SwiftUI
import GalaKit

struct VNDBSearchView: View {
    let initialQuery: String
    let onSelect: (VNDBVn) -> Void
    let onSkip: () -> Void

    @State private var searchText: String
    @State private var results: [VNDBVn] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    private let client = VNDBClient()

    init(initialQuery: String, onSelect: @escaping (VNDBVn) -> Void, onSkip: @escaping () -> Void) {
        self.initialQuery = initialQuery
        self.onSelect = onSelect
        self.onSkip = onSkip
        self._searchText = State(initialValue: initialQuery)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("匹配 VNDB")
                .font(.headline)

            HStack {
                TextField("搜索...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { search() }
                Button("搜索") { search() }
                    .disabled(searchText.isEmpty || isSearching)
            }

            if isSearching {
                ProgressView()
            } else if let error = errorMessage {
                Text(error).foregroundStyle(.red).font(.caption)
            } else {
                List(results, id: \.id) { vn in
                    HStack {
                        if let thumbURL = vn.image?.thumbnail, let url = URL(string: thumbURL) {
                            AsyncImage(url: url) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Color.gray.opacity(0.2)
                            }
                            .frame(width: 40, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        VStack(alignment: .leading) {
                            Text(vn.alttitle ?? vn.title).font(.body)
                            if vn.alttitle != nil {
                                Text(vn.title).font(.caption).foregroundStyle(.secondary)
                            }
                            if let dev = vn.developers?.first?.name {
                                Text(dev).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        if let rating = vn.rating {
                            Text(String(format: "%.0f", rating))
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(vn) }
                }
                .frame(minHeight: 200)
            }

            HStack {
                Spacer()
                Button("跳过") { onSkip() }
            }
        }
        .padding()
        .frame(width: 500, height: 400)
        .task { search() }
    }

    private func search() {
        guard !searchText.isEmpty else { return }
        isSearching = true
        errorMessage = nil

        Task {
            do {
                let response = try await client.searchVN(query: searchText, results: 15)
                results = response.results
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }
}
