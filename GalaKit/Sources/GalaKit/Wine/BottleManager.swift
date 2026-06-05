import Foundation

struct FontSubstitute: Sendable {
    let sourceName: String
    let targetName: String
}

struct WindowMetricFont: Sendable {
    let valueName: String
    let data: [UInt8]
}

private struct WinetricksCachedDownload: Sendable {
    let relativePath: String
    let displayName: String
    let expectedByteCount: Int64
}

public struct EnginePresetProgress: Equatable, Sendable {
    public let message: String
    public let completedUnitCount: Int
    public let totalUnitCount: Int
    public let currentItemProgress: Double?

    public init(
        message: String,
        completedUnitCount: Int,
        totalUnitCount: Int,
        currentItemProgress: Double? = nil
    ) {
        self.message = message
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.currentItemProgress = currentItemProgress
    }

    public var fraction: Double? {
        guard totalUnitCount > 0 else { return nil }
        return Double(completedUnitCount) / Double(totalUnitCount)
    }
}

public struct RuntimeProfileMarker: Codable, Equatable, Sendable {
    public let profile: RuntimeProfile
    public let configVersion: Int
    public let configuredAt: Date
    public let wineVersionName: String
    public let managedComponents: [String]

    public init(
        profile: RuntimeProfile,
        configVersion: Int,
        configuredAt: Date,
        wineVersionName: String,
        managedComponents: [String]
    ) {
        self.profile = profile
        self.configVersion = configVersion
        self.configuredAt = configuredAt
        self.wineVersionName = wineVersionName
        self.managedComponents = managedComponents
    }

    static func current(for game: Game, configuredAt: Date) -> RuntimeProfileMarker? {
        guard let engine = game.engine, engine.supportsNativeLaunch != true else { return nil }
        return RuntimeProfileMarker(
            profile: engine.runtimeProfile,
            configVersion: engine.runtimeConfigVersion,
            configuredAt: configuredAt,
            wineVersionName: engine == .artemisD3D11 ? WineManager.dxmtWineVersionName : WineManager.wineVersionName,
            managedComponents: engine.preset.managedComponents.map(\.runtimeMarkerName)
        )
    }
}

public enum RuntimeMarkerStatus: Equatable, Sendable {
    case missing
    case current
    case outdated
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

    public func prefixPath(for engine: Engine?) -> String {
        let profileName = (engine?.runtimeProfile ?? .common).rawValue
        return bottlesDirectory
            .appendingPathComponent("Profiles")
            .appendingPathComponent(profileName)
            .path
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

    public func applyEnginePreset(
        for game: Game,
        progressHandler: (@Sendable (EnginePresetProgress) -> Void)? = nil
    ) async throws {
        guard let engine = game.engine else { return }
        let preset = engine.preset
        let registryValues = preset.registryValues + engine.gameSpecificRegistryValues(for: game)
        guard !preset.components.isEmpty ||
            !preset.managedComponents.isEmpty ||
            !preset.dllOverrides.isEmpty ||
            !registryValues.isEmpty else { return }

        let totalUnitCount = preset.components.count +
            preset.managedComponents.count +
            preset.dllOverrides.count +
            registryValues.count
        var completedUnitCount = 0

        for component in preset.components {
            progressHandler?(
                EnginePresetProgress(
                    message: "正在安装 \(Self.displayName(forWinetricksComponent: component))...",
                    completedUnitCount: completedUnitCount,
                    totalUnitCount: totalUnitCount
                )
            )
            try await installWinetricks(
                components: [component],
                prefix: game.bottleConfig.prefixPath,
                completedUnitCount: completedUnitCount,
                totalUnitCount: totalUnitCount,
                progressHandler: progressHandler
            )
            completedUnitCount += 1
            progressHandler?(
                EnginePresetProgress(
                    message: "\(Self.displayName(forWinetricksComponent: component)) 已安装",
                    completedUnitCount: completedUnitCount,
                    totalUnitCount: totalUnitCount
                )
            )
        }

        for component in preset.managedComponents {
            progressHandler?(
                EnginePresetProgress(
                    message: "正在准备 \(Self.displayName(forManagedComponent: component))...",
                    completedUnitCount: completedUnitCount,
                    totalUnitCount: totalUnitCount
                )
            )
            try await installManagedRuntimeComponent(
                component,
                for: game,
                completedUnitCount: completedUnitCount,
                totalUnitCount: totalUnitCount,
                progressHandler: progressHandler
            )
            completedUnitCount += 1
            progressHandler?(
                EnginePresetProgress(
                    message: "\(Self.displayName(forManagedComponent: component)) 已安装",
                    completedUnitCount: completedUnitCount,
                    totalUnitCount: totalUnitCount
                )
            )
        }

        if !preset.dllOverrides.isEmpty || !registryValues.isEmpty {
            guard let wineBinary = wineManager?.wineBinaryURL else { return }
            for (dll, mode) in preset.dllOverrides {
                progressHandler?(
                    EnginePresetProgress(
                        message: "正在写入 DLL 覆盖 \(dll)...",
                        completedUnitCount: completedUnitCount,
                        totalUnitCount: totalUnitCount
                    )
                )
                try await runWineCommand(
                    wineBinary: wineBinary,
                    arguments: ["reg", "add", "HKCU\\Software\\Wine\\DllOverrides",
                               "/v", dll, "/t", "REG_SZ", "/d", mode, "/f"],
                    prefix: game.bottleConfig.prefixPath,
                    locale: game.bottleConfig.locale
                )
                completedUnitCount += 1
            }

            for value in registryValues {
                progressHandler?(
                    EnginePresetProgress(
                        message: "正在写入注册表 \(value.valueName)...",
                        completedUnitCount: completedUnitCount,
                        totalUnitCount: totalUnitCount
                    )
                )
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
                completedUnitCount += 1
            }
        }
    }

    public func deleteBottle(for game: Game) throws {
        let prefixURL = URL(fileURLWithPath: game.bottleConfig.prefixPath)
        if FileManager.default.fileExists(atPath: prefixURL.path) {
            try FileManager.default.removeItem(at: prefixURL)
        }
    }

    public func writeRuntimeMarker(for game: Game, configuredAt: Date = Date()) throws {
        guard let marker = RuntimeProfileMarker.current(for: game, configuredAt: configuredAt) else { return }
        let markerURL = Self.runtimeMarkerURL(prefix: game.bottleConfig.prefixPath)
        try FileManager.default.createDirectory(
            at: markerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(marker).write(to: markerURL, options: .atomic)
    }

    public func runtimeMarkerStatus(for game: Game) throws -> RuntimeMarkerStatus {
        guard let current = RuntimeProfileMarker.current(for: game, configuredAt: Date()) else {
            return .missing
        }

        let markerURL = Self.runtimeMarkerURL(prefix: game.bottleConfig.prefixPath)
        guard FileManager.default.fileExists(atPath: markerURL.path) else {
            return .missing
        }

        let data = try Data(contentsOf: markerURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let marker = try decoder.decode(RuntimeProfileMarker.self, from: data)

        return marker.profile == current.profile &&
            marker.configVersion == current.configVersion &&
            marker.wineVersionName == current.wineVersionName &&
            marker.managedComponents == current.managedComponents ? .current : .outdated
    }

    private static func runtimeMarkerURL(prefix: String) -> URL {
        URL(fileURLWithPath: prefix).appendingPathComponent(".gala-runtime.json")
    }

    private func installManagedRuntimeComponent(
        _ component: ManagedRuntimeComponent,
        for game: Game,
        completedUnitCount: Int,
        totalUnitCount: Int,
        progressHandler: (@Sendable (EnginePresetProgress) -> Void)?
    ) async throws {
        switch component {
        case .dxmt:
            guard let wineManager else { throw WineError.wineNotInstalled }
            try await wineManager.ensureDXMTWineVariant { progress in
                progressHandler?(
                    EnginePresetProgress(
                        message: "正在下载 DXMT 图形运行时...",
                        completedUnitCount: completedUnitCount,
                        totalUnitCount: totalUnitCount,
                        currentItemProgress: progress
                    )
                )
            }
            try Self.installDXMTPEOverrides(
                from: wineManager.dxmtWineDirectory,
                toPrefix: game.bottleConfig.prefixPath
            )
        }
    }

    private static func installDXMTPEOverrides(from wineRoot: URL, toPrefix prefix: String) throws {
        let prefixURL = URL(fileURLWithPath: prefix)
        let wineLib = dxmtWineLibDirectory(in: wineRoot)
        let mappings = [
            ("x86_64-windows", "drive_c/windows/system32"),
            ("i386-windows", "drive_c/windows/syswow64"),
        ]

        for (sourceDirectoryName, targetDirectoryName) in mappings {
            let sourceDirectory = wineLib.appendingPathComponent(sourceDirectoryName)
            let targetDirectory = prefixURL.appendingPathComponent(targetDirectoryName)
            guard let sourceFiles = try? FileManager.default.contentsOfDirectory(
                at: sourceDirectory,
                includingPropertiesForKeys: nil
            ) else {
                throw WineError.extractionFailed
            }

            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            for sourceFile in sourceFiles where sourceFile.pathExtension.lowercased() == "dll" {
                let targetFile = targetDirectory.appendingPathComponent(sourceFile.lastPathComponent)
                try? FileManager.default.removeItem(at: targetFile)
                try FileManager.default.copyItem(at: sourceFile, to: targetFile)
            }
        }
    }

    private static func dxmtWineLibDirectory(in wineRoot: URL) -> URL {
        let appBundle = wineRoot.appendingPathComponent("Contents/Resources/wine/lib/wine")
        if FileManager.default.fileExists(atPath: appBundle.path) {
            return appBundle
        }
        return wineRoot.appendingPathComponent("lib/wine")
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

    static func findWinetricks(wineManager: WineManager? = nil) -> String? {
        if let managedPath = wineManager?.winetricksURL.path,
           FileManager.default.isExecutableFile(atPath: managedPath) {
            return managedPath
        }

        return ["/opt/homebrew/bin/winetricks", "/usr/local/bin/winetricks"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func installWinetricks(
        components: [String],
        prefix: String,
        completedUnitCount: Int = 0,
        totalUnitCount: Int = 0,
        progressHandler: (@Sendable (EnginePresetProgress) -> Void)? = nil
    ) async throws {
        if let wm = wineManager {
            try await wm.downloadCabextract()
            try await wm.downloadWinetricks()
            try FileManager.default.createDirectory(at: wm.winetricksCacheDirectory, withIntermediateDirectories: true)
        }

        guard let winetricksPath = Self.findWinetricks(wineManager: wineManager) else {
            throw WineError.helperToolNotInstalled("winetricks")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: winetricksPath)
        process.arguments = ["-q"] + components
        process.environment = Self.winetricksEnvironment(
            prefix: prefix,
            locale: "zh_CN.UTF-8",
            wineBinary: wineManager?.wineBinaryURL?.path,
            toolsDirectory: wineManager?.toolsDirectory.path,
            cacheDirectory: wineManager?.winetricksCacheDirectory.path
        )

        let monitor = Self.startWinetricksDownloadMonitor(
            components: components,
            cacheDirectory: wineManager?.winetricksCacheDirectory,
            completedUnitCount: completedUnitCount,
            totalUnitCount: totalUnitCount,
            progressHandler: progressHandler
        )
        defer {
            monitor?.cancel()
        }

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw WineError.helperToolFailed("winetricks", process.terminationStatus)
        }
    }

    static func winetricksEnvironment(
        prefix: String,
        locale: String,
        wineBinary: String?,
        toolsDirectory: String?,
        cacheDirectory: String?
    ) -> [String: String] {
        var env = Self.wineCommandEnvironment(prefix: prefix, locale: locale)
        if let wineBinary {
            env["WINE"] = wineBinary
        }
        if let toolsDirectory {
            env["PATH"] = toolsDirectory + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        }
        if let cacheDirectory {
            env["W_CACHE"] = cacheDirectory
        }
        return env
    }

    private static func displayName(forWinetricksComponent component: String) -> String {
        switch component {
        case "quartz":
            return "DirectShow 核心组件 quartz"
        case "amstream":
            return "DirectShow 流媒体组件 amstream"
        case "lavfilters":
            return "LAV Filters 解码器"
        default:
            return component
        }
    }

    private static func displayName(forManagedComponent component: ManagedRuntimeComponent) -> String {
        switch component {
        case .dxmt:
            return "DXMT 图形运行时"
        }
    }

    private static func startWinetricksDownloadMonitor(
        components: [String],
        cacheDirectory: URL?,
        completedUnitCount: Int,
        totalUnitCount: Int,
        progressHandler: (@Sendable (EnginePresetProgress) -> Void)?
    ) -> Task<Void, Never>? {
        guard let cacheDirectory, let progressHandler else { return nil }

        let downloads = components.flatMap(Self.cachedDownloads(forWinetricksComponent:))
        guard !downloads.isEmpty else { return nil }

        return Task.detached {
            while !Task.isCancelled {
                for download in downloads {
                    let fileURL = cacheDirectory.appendingPathComponent(download.relativePath)
                    guard let byteCount = Self.fileSize(at: fileURL),
                          byteCount > 0,
                          byteCount < download.expectedByteCount else {
                        continue
                    }

                    progressHandler(
                        EnginePresetProgress(
                            message: "正在下载 \(download.displayName)...",
                            completedUnitCount: completedUnitCount,
                            totalUnitCount: totalUnitCount,
                            currentItemProgress: Double(byteCount) / Double(download.expectedByteCount)
                        )
                    )
                    break
                }

                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private static func cachedDownloads(forWinetricksComponent component: String) -> [WinetricksCachedDownload] {
        switch component {
        case "quartz", "amstream":
            return [
                WinetricksCachedDownload(
                    relativePath: "win7sp1/windows6.1-KB976932-X86.exe",
                    displayName: "Windows 7 SP1 x86 组件包",
                    expectedByteCount: 563_934_504
                ),
                WinetricksCachedDownload(
                    relativePath: "win7sp1/windows6.1-KB976932-X64.exe",
                    displayName: "Windows 7 SP1 x64 组件包",
                    expectedByteCount: 947_070_088
                ),
            ]
        case "lavfilters":
            return [
                WinetricksCachedDownload(
                    relativePath: "lavfilters/LAVFilters-0.74.1-Installer.exe",
                    displayName: "LAV Filters 安装器",
                    expectedByteCount: 12_560_912
                ),
            ]
        default:
            return []
        }
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.int64Value
    }

    private func runWineCommand(wineBinary: URL, arguments: [String], prefix: String, locale: String) async throws {
        let process = Process()
        process.executableURL = wineBinary
        process.arguments = arguments
        process.environment = Self.wineCommandEnvironment(prefix: prefix, locale: locale)
        try process.run()
        process.waitUntilExit()
    }

    static func wineCommandEnvironment(prefix: String, locale: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix
        env["LANG"] = locale
        env["LC_ALL"] = locale
        env["WINEDEBUG"] = "-all"
        env["MVK_CONFIG_LOG_LEVEL"] = "0"
        return env
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

private extension ManagedRuntimeComponent {
    var runtimeMarkerName: String {
        switch self {
        case .dxmt:
            return "dxmt@v0.80"
        }
    }
}
