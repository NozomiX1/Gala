import Foundation

public final class BottleManager: @unchecked Sendable {
    private let bottlesDirectory: URL
    private let wineManager: WineManager?

    public init(bottlesDirectory: URL, wineManager: WineManager? = nil) {
        self.bottlesDirectory = bottlesDirectory
        self.wineManager = wineManager
        try? FileManager.default.createDirectory(at: bottlesDirectory, withIntermediateDirectories: true)
    }

    public func prefixPath(for gameId: UUID) -> String {
        bottlesDirectory.appendingPathComponent(gameId.uuidString).path
    }

    public func createBottle(for game: Game) async throws {
        let prefixURL = URL(fileURLWithPath: game.bottleConfig.prefixPath)
        try FileManager.default.createDirectory(at: prefixURL, withIntermediateDirectories: true)

        guard let wineBinary = wineManager?.wineBinaryURL else {
            throw WineError.wineNotInstalled
        }

        try await runWineCommand(
            wineBinary: wineBinary,
            arguments: ["wineboot", "--init"],
            prefix: game.bottleConfig.prefixPath,
            locale: game.bottleConfig.locale
        )

        try await configureJapaneseLocale(
            wineBinary: wineBinary,
            prefix: game.bottleConfig.prefixPath,
            locale: game.bottleConfig.locale
        )
    }

    public func applyEnginePreset(for game: Game) async throws {
        guard let engine = game.engine else { return }
        let preset = engine.preset
        guard !preset.components.isEmpty || !preset.dllOverrides.isEmpty else { return }

        if !preset.components.isEmpty {
            try await installWinetricks(components: preset.components, prefix: game.bottleConfig.prefixPath)
        }

        if !preset.dllOverrides.isEmpty {
            guard let wineBinary = wineManager?.wineBinaryURL else { return }
            for (dll, mode) in preset.dllOverrides {
                try await runWineCommand(
                    wineBinary: wineBinary,
                    arguments: ["reg", "add", "HKCU\\Software\\Wine\\DllOverrides",
                               "/v", dll, "/t", "REG_SZ", "/d", mode, "/f"],
                    prefix: game.bottleConfig.prefixPath,
                    locale: game.bottleConfig.locale
                )
            }
        }
    }

    public func deleteBottle(for game: Game) throws {
        let prefixURL = URL(fileURLWithPath: game.bottleConfig.prefixPath)
        if FileManager.default.fileExists(atPath: prefixURL.path) {
            try FileManager.default.removeItem(at: prefixURL)
        }
    }

    private func configureJapaneseLocale(wineBinary: URL, prefix: String, locale: String) async throws {
        let regCommands: [(key: String, value: String, data: String)] = [
            ("HKLM\\System\\CurrentControlSet\\Control\\Nls\\CodePage", "ACP", "932"),
            ("HKLM\\System\\CurrentControlSet\\Control\\Nls\\CodePage", "OEMCP", "932"),
            ("HKLM\\System\\CurrentControlSet\\Control\\Nls\\Language", "Default", "0411"),
            ("HKLM\\System\\CurrentControlSet\\Control\\Nls\\Language", "InstallLanguage", "0411"),
        ]

        for cmd in regCommands {
            try await runWineCommand(
                wineBinary: wineBinary,
                arguments: ["reg", "add", cmd.key, "/v", cmd.value, "/t", "REG_SZ", "/d", cmd.data, "/f"],
                prefix: prefix,
                locale: locale
            )
        }
    }

    private func installWinetricks(components: [String], prefix: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["winetricks", "-q"] + components
        process.environment = [
            "WINEPREFIX": prefix,
            "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        ]
        try process.run()
        process.waitUntilExit()
    }

    private func runWineCommand(wineBinary: URL, arguments: [String], prefix: String, locale: String) async throws {
        let process = Process()
        process.executableURL = wineBinary
        process.arguments = arguments
        process.environment = [
            "WINEPREFIX": prefix,
            "LANG": locale,
            "LC_ALL": locale,
        ]
        try process.run()
        process.waitUntilExit()
    }
}
