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

    /// Check if a bottle has been fully initialized (has system.reg from wineboot)
    public func isBottleReady(for game: Game) -> Bool {
        let systemReg = URL(fileURLWithPath: game.bottleConfig.prefixPath)
            .appendingPathComponent("system.reg")
        return FileManager.default.fileExists(atPath: systemReg.path)
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

        try await configureLocale(
            wineBinary: wineBinary,
            prefix: game.bottleConfig.prefixPath,
            locale: game.bottleConfig.locale
        )

        if let fontURL = wineManager?.fontFileURL {
            try Self.installBundledFont(prefix: game.bottleConfig.prefixPath, fontSource: fontURL)
        }

        try await registerFont(
            wineBinary: wineBinary,
            prefix: game.bottleConfig.prefixPath,
            locale: game.bottleConfig.locale
        )

        try await configureFontSubstitutes(
            wineBinary: wineBinary,
            prefix: game.bottleConfig.prefixPath,
            locale: game.bottleConfig.locale
        )

        try await configureFontSmoothing(
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

    private func configureLocale(wineBinary: URL, prefix: String, locale: String) async throws {
        let (acp, oemcp, lang): (String, String, String) = if locale.hasPrefix("zh_CN") {
            ("936", "936", "0804")
        } else {
            ("932", "932", "0411")
        }

        let regCommands: [(key: String, value: String, data: String)] = [
            ("HKLM\\System\\CurrentControlSet\\Control\\Nls\\CodePage", "ACP", acp),
            ("HKLM\\System\\CurrentControlSet\\Control\\Nls\\CodePage", "OEMCP", oemcp),
            ("HKLM\\System\\CurrentControlSet\\Control\\Nls\\Language", "Default", lang),
            ("HKLM\\System\\CurrentControlSet\\Control\\Nls\\Language", "InstallLanguage", lang),
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

    // MARK: - CJK Fonts

    /// Install the downloaded Source Han Sans SC font into a Wine prefix's Fonts directory.
    public static func installBundledFont(prefix: String, fontSource: URL) throws {
        let fontsDir = URL(fileURLWithPath: prefix)
            .appendingPathComponent("drive_c/windows/Fonts")
        try FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)

        let dest = fontsDir.appendingPathComponent(fontSource.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        guard FileManager.default.fileExists(atPath: fontSource.path) else { return }

        try FileManager.default.copyItem(at: fontSource, to: dest)
    }

    private func registerFont(wineBinary: URL, prefix: String, locale: String) async throws {
        let regKey = "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts"
        try await runWineCommand(
            wineBinary: wineBinary,
            arguments: ["reg", "add", regKey,
                       "/v", "Source Han Sans SC Regular (TrueType)",
                       "/t", "REG_SZ",
                       "/d", "SourceHanSansSC-Regular.otf",
                       "/f"],
            prefix: prefix,
            locale: locale
        )
    }

    private func configureFontSubstitutes(wineBinary: URL, prefix: String, locale: String) async throws {
        // Map common Windows CJK fonts to macOS system fonts so Wine can render
        // CJK text in window titles, dialogs, and game UI.
        let regKey = "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes"
        let fontName = "Source Han Sans SC"
        let substitutes: [(String, String)] = [
            ("SimSun", fontName),
            ("NSimSun", fontName),
            ("MS Gothic", fontName),
            ("MS PGothic", fontName),
            ("MS UI Gothic", fontName),
            ("MS Mincho", fontName),
            ("MS PMincho", fontName),
            ("Microsoft YaHei", fontName),
            ("\\u5B8B\\u4F53", fontName),
            ("\\u9ED1\\u4F53", fontName),
            // Full-width Japanese names (BGI engine uses these)
            ("\u{FF2D}\u{FF33} \u{660E}\u{671D}", fontName),           // ＭＳ 明朝
            ("\u{FF2D}\u{FF33} \u{30B4}\u{30B7}\u{30C3}\u{30AF}", fontName), // ＭＳ ゴシック
            ("\u{FF2D}\u{FF33} \u{FF30}\u{660E}\u{671D}", fontName),   // ＭＳ Ｐ明朝
            ("\u{FF2D}\u{FF33} \u{FF30}\u{30B4}\u{30B7}\u{30C3}\u{30AF}", fontName), // ＭＳ Ｐゴシック
        ]

        for (from, to) in substitutes {
            try await runWineCommand(
                wineBinary: wineBinary,
                arguments: ["reg", "add", regKey, "/v", from, "/t", "REG_SZ", "/d", to, "/f"],
                prefix: prefix,
                locale: locale
            )
        }
    }

    private func configureFontSmoothing(wineBinary: URL, prefix: String, locale: String) async throws {
        let regKey = "HKCU\\Control Panel\\Desktop"
        let settings: [(String, String)] = [
            ("FontSmoothing", "2"),
            ("FontSmoothingType", "2"),        // FreeType subpixel rendering
            ("FontSmoothingGamma", "1000"),
            ("FontSmoothingOrientation", "1"),  // RGB
        ]
        for (name, data) in settings {
            try await runWineCommand(
                wineBinary: wineBinary,
                arguments: ["reg", "add", regKey, "/v", name, "/t", "REG_SZ", "/d", data, "/f"],
                prefix: prefix,
                locale: locale
            )
        }
    }

    // MARK: - Winetricks (optional, for engine presets)

    private static func findWinetricks() -> String? {
        ["/opt/homebrew/bin/winetricks", "/usr/local/bin/winetricks"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    private func installWinetricks(components: [String], prefix: String) async throws {
        guard let winetricksPath = Self.findWinetricks() else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: winetricksPath)
        process.arguments = ["-q"] + components
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix
        if let wineBinary = wineManager?.wineBinaryURL {
            env["WINE"] = wineBinary.path
        }
        process.environment = env
        try process.run()
        process.waitUntilExit()
    }

    private func runWineCommand(wineBinary: URL, arguments: [String], prefix: String, locale: String) async throws {
        let process = Process()
        process.executableURL = wineBinary
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix
        env["LANG"] = locale
        env["LC_ALL"] = locale
        process.environment = env
        try process.run()
        process.waitUntilExit()
    }
}
