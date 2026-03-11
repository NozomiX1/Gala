import SwiftUI
import GalaKit
import UniformTypeIdentifiers

extension UTType {
    static let exe = UTType(filenameExtension: "exe") ?? .data
}

struct AddGameView: View {
    let viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var step: AddGameStep = .selectFile
    @State private var selectedExePath: String?
    @State private var gameDirectory: URL?
    @State private var detectedEngine: Engine?
    @State private var gameName = ""
    @State private var setupStatus = ""

    enum AddGameStep {
        case selectFile, vndbMatch, settingUp
    }

    var body: some View {
        VStack {
            switch step {
            case .selectFile:
                selectFileView
            case .vndbMatch:
                VNDBSearchView(
                    initialQuery: gameName,
                    onSelect: { vn in addGameWithVNDB(vn) },
                    onSkip: { addGameWithoutVNDB() }
                )
            case .settingUp:
                settingUpView
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private var selectFileView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Add a Game")
                .font(.title2)
            Text("Select the game's .exe file")
                .foregroundStyle(.secondary)
            Button("Choose .exe File...") {
                selectFile()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var settingUpView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(setupStatus)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.exe]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the game's .exe file"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        selectedExePath = url.path
        gameDirectory = url.deletingLastPathComponent()

        if let dir = gameDirectory {
            detectedEngine = EngineDetector.detect(in: dir)
        }

        gameName = gameDirectory?.lastPathComponent ?? url.deletingPathExtension().lastPathComponent
        step = .vndbMatch
    }

    private func addGameWithVNDB(_ vn: VNDBVn) {
        step = .settingUp
        Task {
            await setupGame(
                title: vn.alttitle ?? vn.title,
                originalTitle: vn.alttitle != nil ? vn.title : nil,
                vndbId: vn.id,
                rating: vn.rating,
                developer: vn.developers?.first?.name,
                released: vn.released,
                description: vn.description,
                coverURL: vn.image?.url
            )
        }
    }

    private func addGameWithoutVNDB() {
        step = .settingUp
        Task {
            await setupGame(title: gameName)
        }
    }

    private func setupGame(
        title: String,
        originalTitle: String? = nil,
        vndbId: String? = nil,
        rating: Double? = nil,
        developer: String? = nil,
        released: String? = nil,
        description: String? = nil,
        coverURL: String? = nil
    ) async {
        guard var exePath = selectedExePath else { return }

        // If engine detected, try to resolve the actual engine executable
        if let engine = detectedEngine, let dir = gameDirectory {
            if let resolvedExe = EngineDetector.resolveExecutable(engine: engine, in: dir) {
                exePath = resolvedExe.path
            }
        }

        let gameId = UUID()
        let prefixPath = viewModel.bottleManager.prefixPath(for: gameId)

        var coverImagePath: String?
        if let coverURL, let url = URL(string: coverURL) {
            setupStatus = "Downloading cover art..."
            if let data = try? await viewModel.vndbClient.downloadImage(from: url) {
                let key = vndbId ?? gameId.uuidString
                try? viewModel.imageCache.save(data, forKey: key)
                coverImagePath = viewModel.imageCache.path(forKey: key)
            }
        }

        var engine = detectedEngine
        if let vndbId, engine == nil {
            setupStatus = "Checking engine info..."
            if let releases = try? await viewModel.vndbClient.getReleases(vnId: vndbId) {
                if let vndbEngine = releases.compactMap({ $0.engine }).first {
                    engine = Engine.allCases.first {
                        $0.displayName.lowercased() == vndbEngine.lowercased()
                    }
                }
            }
        }

        let game = Game(
            id: gameId,
            title: title,
            originalTitle: originalTitle,
            vndbId: vndbId,
            executablePath: exePath,
            coverImagePath: coverImagePath,
            engine: engine,
            rating: rating,
            developer: developer,
            releasedAt: released,
            description: description,
            bottleConfig: BottleConfig(prefixPath: prefixPath)
        )

        if engine != .renpy {
            setupStatus = "Creating Wine prefix..."
            try? FileManager.default.createDirectory(
                atPath: prefixPath,
                withIntermediateDirectories: true
            )
        }

        viewModel.addGame(game)
        dismiss()
    }
}
