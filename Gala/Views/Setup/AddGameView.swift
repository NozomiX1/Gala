import SwiftUI
import GalaKit
import UniformTypeIdentifiers

extension UTType {
    static let exe = UTType(filenameExtension: "exe") ?? .data
}

/// Matches a chosen executable against VNDB and adds it to the library.
struct AddGameView: View {
    let viewModel: LibraryViewModel
    let executable: URL
    @Environment(\.dismiss) private var dismiss

    @State private var query: String
    @State private var results: [VNDBVn] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var addingStatus: String?
    @State private var engineDetection: Task<Engine?, Never>?

    private var gameDirectory: URL { executable.deletingLastPathComponent() }

    init(viewModel: LibraryViewModel, executable: URL) {
        self.viewModel = viewModel
        self.executable = executable
        _query = State(initialValue: executable.deletingLastPathComponent().lastPathComponent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("添加游戏")
                    .font(.title2.weight(.semibold))
                Text("\(executable.lastPathComponent) · \(gameDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("在 VNDB 上搜索这个游戏", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await search() } }
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(.quaternary.opacity(0.6), in: Capsule())
            .padding(.horizontal, 24)
            .padding(.top, 16)

            resultList
                .padding(.top, 10)

            Divider()

            HStack {
                Button("不匹配，直接添加") {
                    add(matching: nil)
                }
                .buttonStyle(.link)
                Spacer()
                if let addingStatus {
                    ProgressView()
                        .controlSize(.small)
                    Text(addingStatus)
                        .foregroundStyle(.secondary)
                }
                Button("取消", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        // Tall enough for the results found, up to five and a half rows before scrolling.
        .frame(width: 520, height: 196 + 81 * min(max(CGFloat(results.count), 2), 5.5))
        .disabled(addingStatus != nil)
        .task {
            let directory = gameDirectory
            engineDetection = Task.detached(priority: .userInitiated) {
                EngineDetector.detect(in: directory)
            }
            await search()
        }
    }

    @ViewBuilder
    private var resultList: some View {
        if let searchError {
            placeholder("exclamationmark.triangle", "没能连上 VNDB", searchError)
        } else if results.isEmpty && !isSearching {
            placeholder("questionmark.circle", "没有找到匹配的游戏", "换个名字再搜，或者不匹配直接添加。")
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(results, id: \.id) { vn in
                        ResultRow(vn: vn) { add(matching: vn) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    private func placeholder(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSearching = true
        searchError = nil
        do {
            results = try await viewModel.vndbClient.searchVN(query: text, results: 15).results
        } catch {
            results = []
            searchError = error.localizedDescription
        }
        isSearching = false
    }

    private func add(matching vn: VNDBVn?) {
        Task { @MainActor in
            let gameId = UUID()

            var coverImagePath: String?
            if let vn, let coverURL = vn.image?.url, let url = URL(string: coverURL) {
                addingStatus = "下载封面..."
                if let data = try? await viewModel.vndbClient.downloadImage(from: url) {
                    try? viewModel.imageCache.save(data, forKey: vn.id)
                    coverImagePath = viewModel.imageCache.path(forKey: vn.id)
                }
            }

            addingStatus = "检测引擎信息..."
            var engine = await engineDetection?.value
            if engine == nil, let vn, let releases = try? await viewModel.vndbClient.getReleases(vnId: vn.id) {
                engine = EngineSelectionPolicy.select(
                    localDetection: nil,
                    vndbReleases: releases,
                    gameDirectory: gameDirectory
                )
            }
            let resolvedEngine = engine ?? .unknown

            viewModel.addGame(Game(
                id: gameId,
                title: vn.map { $0.alttitle ?? $0.title } ?? gameDirectory.lastPathComponent,
                originalTitle: vn?.alttitle != nil ? vn?.title : nil,
                vndbId: vn?.id,
                executablePath: executable.path,
                coverImagePath: coverImagePath,
                engine: resolvedEngine,
                rating: vn?.rating,
                developer: vn?.developers?.first?.name,
                releasedAt: vn?.released,
                description: vn?.description,
                isRuntimeConfigured: false,
                runtimeProfileMigrationVersion: RuntimeProfileMigration.currentRulesVersion,
                runtimeProfileMigrationExecutablePath: executable.path,
                bottleConfig: BottleConfig(prefixPath: viewModel.bottleManager.prefixPath(for: resolvedEngine))
            ))
            dismiss()
        }
    }
}

private struct ResultRow: View {
    let vn: VNDBVn
    let onChoose: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onChoose) {
            HStack(spacing: 14) {
                AsyncImage(url: vn.image?.thumbnail.flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(width: 46, height: 65)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(vn.alttitle ?? vn.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text([vn.alttitle == nil ? nil : vn.title, vn.developers?.first?.name]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let released = vn.released {
                        Text(released)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 8)

                if let rating = vn.rating {
                    Text(String(format: "%.0f", rating))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(isHovering ? AnyShapeStyle(.quaternary.opacity(0.7)) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
