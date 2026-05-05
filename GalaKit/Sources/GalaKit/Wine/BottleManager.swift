import Foundation

struct FontSubstitute: Sendable {
    let sourceName: String
    let targetName: String
}

struct WindowMetricFont: Sendable {
    let valueName: String
    let data: [UInt8]
}

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

        if let wm = wineManager {
            // Ensure font is downloaded before installing into prefix
            if !wm.isFontInstalled {
                try? await wm.downloadFont()
            }
            try Self.installBundledFont(prefix: game.bottleConfig.prefixPath, fontSource: wm.fontFileURL)
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

        try await configureWindowMetricFonts(
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
        guard !preset.components.isEmpty || !preset.dllOverrides.isEmpty || !preset.registryValues.isEmpty else { return }

        if !preset.components.isEmpty {
            try await installWinetricks(components: preset.components, prefix: game.bottleConfig.prefixPath)
        }

        if !preset.dllOverrides.isEmpty || !preset.registryValues.isEmpty {
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

            for value in preset.registryValues {
                try await runWineCommand(
                    wineBinary: wineBinary,
                    arguments: [
                        "reg", "add", value.key,
                        "/v", value.valueName,
                        "/t", value.type,
                        "/d", value.data,
                        "/f"
                    ],
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
        // Map common Windows CJK and legacy UI fonts so Wine can render CJK
        // text in window titles, menus, dialogs, and game UI.
        let regKey = "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes"

        for substitute in Self.cjkFontSubstitutes {
            try await runWineCommand(
                wineBinary: wineBinary,
                arguments: [
                    "reg", "add", regKey,
                    "/v", substitute.sourceName,
                    "/t", "REG_SZ",
                    "/d", substitute.targetName,
                    "/f"
                ],
                prefix: prefix,
                locale: locale
            )
        }
    }

    private func configureWindowMetricFonts(wineBinary: URL, prefix: String, locale: String) async throws {
        let regKey = "HKCU\\Control Panel\\Desktop\\WindowMetrics"

        for metric in Self.cjkWindowMetricFonts {
            try await runWineCommand(
                wineBinary: wineBinary,
                arguments: [
                    "reg", "add", regKey,
                    "/v", metric.valueName,
                    "/t", "REG_BINARY",
                    "/d", metric.data.hexString,
                    "/f"
                ],
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

        // Ensure cabextract is available for winetricks
        if let wm = wineManager {
            try? await wm.downloadCabextract()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: winetricksPath)
        process.arguments = ["-q"] + components
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix
        if let wineBinary = wineManager?.wineBinaryURL {
            env["WINE"] = wineBinary.path
        }
        // Add managed tools directory to PATH so winetricks can find cabextract
        if let toolsDir = wineManager?.toolsDirectory.path {
            env["PATH"] = toolsDir + ":" + (env["PATH"] ?? "/usr/bin:/bin")
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

extension BottleManager {
    private static let cjkUIFaceName = "Source Han Sans SC"

    static let cjkFontSubstitutes: [FontSubstitute] = {
        let fontName = cjkUIFaceName
        return [
            // Wine and legacy Win32 system UI fonts (menus, dialogs, title bars)
            FontSubstitute(sourceName: "MS Shell Dlg", targetName: fontName),
            FontSubstitute(sourceName: "MS Shell Dlg 2", targetName: fontName),
            FontSubstitute(sourceName: "Tahoma", targetName: fontName),
            FontSubstitute(sourceName: "MS Sans Serif", targetName: fontName),
            FontSubstitute(sourceName: "Microsoft Sans Serif", targetName: fontName),
            FontSubstitute(sourceName: "System", targetName: fontName),
            FontSubstitute(sourceName: "Small Fonts", targetName: fontName),
            FontSubstitute(sourceName: "Arial", targetName: fontName),
            FontSubstitute(sourceName: "Arial Unicode MS", targetName: fontName),

            // Common Windows CJK fonts
            FontSubstitute(sourceName: "SimSun", targetName: fontName),
            FontSubstitute(sourceName: "NSimSun", targetName: fontName),
            FontSubstitute(sourceName: "SimHei", targetName: fontName),
            FontSubstitute(sourceName: "MS Gothic", targetName: fontName),
            FontSubstitute(sourceName: "MS PGothic", targetName: fontName),
            FontSubstitute(sourceName: "MS UI Gothic", targetName: fontName),
            FontSubstitute(sourceName: "MS Mincho", targetName: fontName),
            FontSubstitute(sourceName: "MS PMincho", targetName: fontName),
            FontSubstitute(sourceName: "Microsoft YaHei", targetName: fontName),
            FontSubstitute(sourceName: "Microsoft JhengHei", targetName: fontName),
            FontSubstitute(sourceName: "\\u5B8B\\u4F53", targetName: fontName),
            FontSubstitute(sourceName: "\\u9ED1\\u4F53", targetName: fontName),

            // Full-width Japanese names (BGI engine uses these)
            FontSubstitute(sourceName: "\u{FF2D}\u{FF33} \u{660E}\u{671D}", targetName: fontName),
            FontSubstitute(sourceName: "\u{FF2D}\u{FF33} \u{30B4}\u{30B7}\u{30C3}\u{30AF}", targetName: fontName),
            FontSubstitute(sourceName: "\u{FF2D}\u{FF33} \u{FF30}\u{660E}\u{671D}", targetName: fontName),
            FontSubstitute(sourceName: "\u{FF2D}\u{FF33} \u{FF30}\u{30B4}\u{30B7}\u{30C3}\u{30AF}", targetName: fontName),
        ]
    }()

    static let cjkWindowMetricFonts: [WindowMetricFont] = [
        WindowMetricFont(valueName: "CaptionFont", data: logFontData(height: 10, faceName: cjkUIFaceName)),
        WindowMetricFont(valueName: "IconFont", data: logFontData(height: 8, faceName: cjkUIFaceName)),
        WindowMetricFont(valueName: "MenuFont", data: logFontData(height: 8, faceName: cjkUIFaceName)),
        WindowMetricFont(valueName: "MessageFont", data: logFontData(height: 8, faceName: cjkUIFaceName)),
        WindowMetricFont(valueName: "SmCaptionFont", data: logFontData(height: 8, faceName: cjkUIFaceName)),
        WindowMetricFont(valueName: "StatusFont", data: logFontData(height: 8, faceName: cjkUIFaceName)),
    ]

    private static func logFontData(height: Int32, faceName: String) -> [UInt8] {
        var data: [UInt8] = []

        func appendInt32(_ value: Int32) {
            let raw = UInt32(bitPattern: value)
            data.append(UInt8(raw & 0xff))
            data.append(UInt8((raw >> 8) & 0xff))
            data.append(UInt8((raw >> 16) & 0xff))
            data.append(UInt8((raw >> 24) & 0xff))
        }

        appendInt32(height) // lfHeight
        appendInt32(0)      // lfWidth
        appendInt32(0)      // lfEscapement
        appendInt32(0)      // lfOrientation
        appendInt32(400)    // lfWeight
        data += [
            0x00, // lfItalic
            0x00, // lfUnderline
            0x00, // lfStrikeOut
            0x86, // lfCharSet: GB2312_CHARSET
            0x00, // lfOutPrecision
            0x00, // lfClipPrecision
            0x00, // lfQuality
            0x00, // lfPitchAndFamily
        ]

        for codeUnit in faceName.utf16.prefix(31) {
            data.append(UInt8(codeUnit & 0xff))
            data.append(UInt8((codeUnit >> 8) & 0xff))
        }
        data.append(0)
        data.append(0)

        while data.count < 92 {
            data.append(0)
        }

        return Array(data.prefix(92))
    }
}

private extension Array where Element == UInt8 {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
