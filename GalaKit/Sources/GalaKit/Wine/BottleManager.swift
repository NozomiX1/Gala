import CoreText
import Foundation
import os

/// How the optional fonts stand; see `BottleManager.optionalFontStatus()`.
public struct OptionalFontStatus: Equatable, Sendable {
    public let areFontsInstalled: Bool
    public let outdatedPrefixCount: Int

    /// Nothing left to download or to apply.
    public var isSettled: Bool { areFontsInstalled && outdatedPrefixCount == 0 }
}

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
    public let profile: String
    public let configVersion: Int
    public let configuredAt: Date
    public let wineVersionName: String
    public let managedComponents: [String]
    /// What the prefix was built from. Absent in markers written before profiles became files.
    public let recipeFingerprint: String?
    /// 2 since the fingerprint covers only what is in the prefix. Absent in older markers, whose fingerprint
    /// also covered DLL overrides and the Wine build and so cannot be compared with today's.
    public let format: Int?
    /// True for a prefix from before format 2 whose profile had DLL overrides, which that version wrote into it.
    /// They do no harm to the games using it, but a copy would carry them, so it is not used as a clone source.
    public let carriesDLLOverrides: Bool?

    public init(
        profile: String,
        configVersion: Int,
        configuredAt: Date,
        wineVersionName: String,
        managedComponents: [String],
        recipeFingerprint: String? = nil,
        format: Int? = nil,
        carriesDLLOverrides: Bool? = nil
    ) {
        self.profile = profile
        self.configVersion = configVersion
        self.configuredAt = configuredAt
        self.wineVersionName = wineVersionName
        self.managedComponents = managedComponents
        self.recipeFingerprint = recipeFingerprint
        self.format = format
        self.carriesDLLOverrides = carriesDLLOverrides
    }

    static let currentFormat = 2

    /// Whether this marker was written for the given recipe as it reads now.
    func matches(_ recipe: RuntimeRecipe) -> Bool {
        let current = Self.current(for: recipe, configuredAt: configuredAt)
        return profile == current.profile &&
            configVersion == current.configVersion &&
            wineVersionName == current.wineVersionName &&
            managedComponents == current.managedComponents &&
            // An edited profile file changes the fingerprint even when nobody raised its version.
            (format != Self.currentFormat || recipeFingerprint == current.recipeFingerprint)
    }

    static func current(for recipe: RuntimeRecipe, configuredAt: Date) -> RuntimeProfileMarker {
        RuntimeProfileMarker(
            profile: recipe.id,
            configVersion: recipe.version,
            configuredAt: configuredAt,
            wineVersionName: recipe.usesDXMTWine ? WineManager.dxmtWineVersionName : WineManager.wineVersionName,
            managedComponents: recipe.preset.managedComponents.map(\.runtimeMarkerName),
            recipeFingerprint: recipe.fingerprint,
            format: currentFormat
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

    private var profiles: ProfileStore { wineManager?.profiles ?? .bundled }

    public func prefixPath(for engine: Engine?) -> String {
        Self.prefixPath(for: engine, bottlesDirectory: bottlesDirectory, profiles: profiles)
    }

    static func prefixPath(for engine: Engine?, bottlesDirectory: URL, profiles: ProfileStore = .bundled) -> String {
        prefixPath(forProfile: (engine?.runtimeProfile ?? .common).rawValue, bottlesDirectory: bottlesDirectory, profiles: profiles)
    }

    /// The prefix a profile's games run in: its own, or its base's when it only changes how a game is launched.
    public func prefixPath(forProfile id: String) -> String {
        Self.prefixPath(forProfile: id, bottlesDirectory: bottlesDirectory, profiles: profiles)
    }

    static func prefixPath(forProfile id: String, bottlesDirectory: URL, profiles: ProfileStore = .bundled) -> String {
        bottlesDirectory
            .appendingPathComponent("Profiles")
            .appendingPathComponent(profiles.bottleID(forProfile: id))
            .path
    }

    /// Check if a bottle has been fully initialized (has system.reg from wineboot)
    public func isBottleReady(for game: Game) -> Bool {
        let systemReg = URL(fileURLWithPath: game.bottleConfig.prefixPath)
            .appendingPathComponent("system.reg")
        return FileManager.default.fileExists(atPath: systemReg.path)
    }

    /// A built prefix of one of the game's ancestors, nearest first, to start the game's own from.
    func cloneSource(for game: Game) -> URL? {
        guard let recipe = profiles.bottleRecipe(for: game) else { return nil }
        for id in recipe.cloneCandidates {
            guard let candidate = profiles.recipe(id: id) else { continue }
            let prefix = URL(fileURLWithPath: prefixPath(forProfile: id))
            guard prefix.path != game.bottleConfig.prefixPath,
                  FileManager.default.fileExists(atPath: prefix.appendingPathComponent("system.reg").path),
                  let marker = Self.readMarker(prefix: prefix.path), marker.matches(candidate) else { continue }
            // Before format 2 a profile's DLL overrides were written into its prefix; a clone would carry them along.
            if marker.carriesDLLOverrides == true { continue }
            if marker.format != RuntimeProfileMarker.currentFormat, !candidate.preset.dllOverrides.isEmpty { continue }
            return prefix
        }
        return nil
    }

    /// Starts a profile's prefix as a copy of another profile's built one, when a file was written on top of that
    /// profile and then folded flat: the lineage no longer says so, but that prefix already holds most of what is needed.
    /// Returns whether a copy was made; the caller configures the game either way.
    @discardableResult
    public func seedPrefix(forProfile id: String, fromProfile sourceID: String) -> Bool {
        let target = URL(fileURLWithPath: prefixPath(forProfile: id))
        let source = URL(fileURLWithPath: prefixPath(forProfile: sourceID))
        guard target.path != source.path,
              !FileManager.default.fileExists(atPath: target.path),
              FileManager.default.fileExists(atPath: source.appendingPathComponent("system.reg").path),
              let sourceRecipe = profiles.recipe(id: profiles.bottleID(forProfile: sourceID)),
              let marker = Self.readMarker(prefix: source.path), marker.matches(sourceRecipe),
              marker.carriesDLLOverrides != true, marker.format == RuntimeProfileMarker.currentFormat else { return false }
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard copyfile(source.path, target.path, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_CLONE)) == 0 else { return false }
        try? FileManager.default.removeItem(at: Self.runtimeMarkerURL(prefix: target.path))
        return true
    }

    /// Prefixes on disk that no game points at: left behind when a game moved to another profile, or by a profile
    /// no game uses any more. They may still hold a game's saves, so nothing deletes them without being asked.
    public func unusedPrefixes(inUse paths: Set<String>) -> [URL] {
        let used = Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        let root = bottlesDirectory.appendingPathComponent("Profiles")
        return ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { $0.hasDirectoryPath && !used.contains($0.standardizedFileURL.path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Deletes the prefix a profile owns. One it merely shares with its base is not its to delete.
    public func deletePrefix(ownedByProfile id: String) {
        guard profiles.bottleID(forProfile: id) == id else { return }
        try? FileManager.default.removeItem(atPath: prefixPath(forProfile: id))
    }

    public func createBottle(for game: Game) async throws {
        let prefixURL = URL(fileURLWithPath: game.bottleConfig.prefixPath)

        if let source = cloneSource(for: game) {
            // On APFS this takes no time and no space until the copy is written to; elsewhere it is an ordinary copy.
            try? FileManager.default.removeItem(at: prefixURL)
            try FileManager.default.createDirectory(at: prefixURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard copyfile(source.path, prefixURL.path, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_CLONE)) == 0 else {
                throw WineError.helperToolFailed("copyfile", errno)
            }
            // The copy is not configured as this game's profile until its own half has been applied.
            try? FileManager.default.removeItem(at: Self.runtimeMarkerURL(prefix: prefixURL.path))
            return
        }

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

        // Before the substitutes are chosen: they point at these fonts only when macOS has them.
        await Self.downloadOnDemandFonts()

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
        guard let preset = profiles.recipe(for: game)?.preset else { return }
        let registryValues = preset.registryValues
        let registryKeysToDelete = preset.registryKeysToDelete
        // DLL overrides are not written here: they are passed at every launch (`WineLaunchConfig`), so they never
        // need undoing and a profile that differs only in them needs no prefix of its own.
        guard !preset.components.isEmpty ||
            !preset.managedComponents.isEmpty ||
            !registryValues.isEmpty ||
            !registryKeysToDelete.isEmpty else { return }

        // winetricks keeps a list of what it installed; in a cloned prefix that covers everything the source had.
        let installedLog = URL(fileURLWithPath: game.bottleConfig.prefixPath).appendingPathComponent("winetricks.log")
        let installed = Set(((try? String(contentsOf: installedLog, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init))
        let components = preset.components.filter { !installed.contains($0) }

        let totalUnitCount = components.count +
            preset.managedComponents.count +
            registryKeysToDelete.count +
            registryValues.count
        var completedUnitCount = 0

        for component in components {
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

        if !registryValues.isEmpty || !registryKeysToDelete.isEmpty {
            guard let wineBinary = wineManager?.wineBinaryURL else { return }

            for key in registryKeysToDelete {
                progressHandler?(
                    EnginePresetProgress(
                        message: "正在清理注册表 \(key)...",
                        completedUnitCount: completedUnitCount,
                        totalUnitCount: totalUnitCount
                    )
                )
                try await deleteRegistryKeyIfPresent(
                    key,
                    wineBinary: wineBinary,
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

    private func deleteRegistryKeyIfPresent(
        _ key: String,
        wineBinary: URL,
        prefix: String,
        locale: String
    ) async throws {
        do {
            try await runWineCommand(
                wineBinary: wineBinary,
                arguments: ["reg", "query", key],
                prefix: prefix,
                locale: locale
            )
        } catch WineError.helperToolFailed(let name, _) where name == "reg" {
            return
        }

        try await runWineCommand(
            wineBinary: wineBinary,
            arguments: ["reg", "delete", key, "/f"],
            prefix: prefix,
            locale: locale
        )
    }

    public func deleteBottle(for game: Game) throws {
        let prefixURL = URL(fileURLWithPath: game.bottleConfig.prefixPath)
        if FileManager.default.fileExists(atPath: prefixURL.path) {
            try FileManager.default.removeItem(at: prefixURL)
        }
    }

    public func writeRuntimeMarker(for game: Game, configuredAt: Date = Date(), carriesDLLOverrides: Bool? = nil) throws {
        // A shared prefix carries its owner's marker, so every profile using it reads the same one.
        guard let recipe = profiles.bottleRecipe(for: game) else { return }
        let current = RuntimeProfileMarker.current(for: recipe, configuredAt: configuredAt)
        let marker = RuntimeProfileMarker(
            profile: current.profile,
            configVersion: current.configVersion,
            configuredAt: current.configuredAt,
            wineVersionName: current.wineVersionName,
            managedComponents: current.managedComponents,
            recipeFingerprint: current.recipeFingerprint,
            format: current.format,
            // Once true it stays true: reconfiguring in place does not take the old entries out.
            carriesDLLOverrides: carriesDLLOverrides ?? Self.readMarker(prefix: game.bottleConfig.prefixPath)?.carriesDLLOverrides
        )
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
        guard let recipe = profiles.recipe(for: game), let bottleRecipe = profiles.bottleRecipe(for: game) else {
            return .missing
        }
        let markerURL = Self.runtimeMarkerURL(prefix: game.bottleConfig.prefixPath)
        guard FileManager.default.fileExists(atPath: markerURL.path) else {
            return .missing
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let marker = try decoder.decode(RuntimeProfileMarker.self, from: Data(contentsOf: markerURL))

        // The game's own marker is still accepted: prefixes made before a profile began sharing a bottle carry it.
        return [recipe, bottleRecipe].contains(where: marker.matches) ? .current : .outdated
    }

    private static func readMarker(prefix: String) -> RuntimeProfileMarker? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: runtimeMarkerURL(prefix: prefix))).flatMap { try? decoder.decode(RuntimeProfileMarker.self, from: $0) }
    }

    /// Rewrites a marker from before format 2 once it has been found current, so later edits to the profile file
    /// are noticed again: the old fingerprint cannot be compared with today's.
    public func adoptOlderMarker(for game: Game) {
        guard let marker = Self.readMarker(prefix: game.bottleConfig.prefixPath),
              marker.format != RuntimeProfileMarker.currentFormat,
              (try? runtimeMarkerStatus(for: game)) == .current else { return }
        let hadOverrides = profiles.recipe(for: game)?.preset.dllOverrides.isEmpty == false
        try? writeRuntimeMarker(for: game, configuredAt: marker.configuredAt, carriesDLLOverrides: hadOverrides ? true : nil)
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
        case .mediaFoundation:
            guard let wineManager else { throw WineError.wineNotInstalled }
            try await wineManager.ensureMediaFoundationRuntime { progress in
                progressHandler?(
                    EnginePresetProgress(
                        message: "正在下载 Media Foundation 媒体运行时...",
                        completedUnitCount: completedUnitCount,
                        totalUnitCount: totalUnitCount,
                        currentItemProgress: progress
                    )
                )
            }
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

        for substitute in Self.cjkFontSubstitutes(installedFamilies: Self.installedOnDemandFontFamilies()) {
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
        guard let managedPath = wineManager?.winetricksURL.path,
              FileManager.default.isExecutableFile(atPath: managedPath) else {
            return nil
        }
        return managedPath
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
        case .mediaFoundation:
            return "Media Foundation 媒体运行时"
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

        guard process.terminationStatus == 0 else {
            let commandName = arguments.first ?? "wine"
            throw WineError.helperToolFailed(commandName, process.terminationStatus)
        }
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
    /// A font name as a game written for Japanese Windows ends up asking for it in a prefix with the Chinese code page:
    /// its Shift-JIS bytes read as GBK. "ＭＳ 明朝" becomes "俵俽 柧挬".
    static func misreadAsGBK(_ japaneseName: String) -> String? {
        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.dosChineseSimplif.rawValue)
        ))
        return japaneseName.data(using: .shiftJIS).flatMap { String(data: $0, encoding: gbk) }
    }

    static func cjkFontSubstitutes(installedFamilies: Set<String>) -> [FontSubstitute] {
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
            FontSubstitute(sourceName: "宋体", targetName: fontName),
            FontSubstitute(sourceName: "黑体", targetName: fontName),

            // Full-width Japanese names (BGI engine uses these)
            FontSubstitute(sourceName: "\u{FF2D}\u{FF33} \u{660E}\u{671D}", targetName: fontName),
            FontSubstitute(sourceName: "\u{FF2D}\u{FF33} \u{30B4}\u{30B7}\u{30C3}\u{30AF}", targetName: fontName),
            FontSubstitute(sourceName: "\u{FF2D}\u{FF33} \u{FF30}\u{660E}\u{671D}", targetName: fontName),
            FontSubstitute(sourceName: "\u{FF2D}\u{FF33} \u{FF30}\u{30B4}\u{30B7}\u{30C3}\u{30AF}", targetName: fontName),
        ] + misreadJapaneseFontSubstitutes(installedFamilies: installedFamilies)
    }

    /// Apple fonts that fit the games below and that macOS fetches on request instead of shipping: the family name
    /// Wine knows each by, and the PostScript name macOS wants when asked for one. They cannot be redistributed.
    static let onDemandFonts = [
        (family: "SimSong", postScriptName: "SimSong-Regular"),
        (family: "STHeiti", postScriptName: "STHeiti"),
    ]

    /// Asking for a missing font by name returns a fallback, so the font is here only if the same name comes back.
    /// CoreText is asked on another thread and given a few seconds: without a login session (a build machine)
    /// looking up a font macOS could download never returns, and that must not hang whoever asked.
    static func isFontInstalled(postScriptName: String, timeout: TimeInterval = 5) -> Bool {
        let found = OSAllocatedUnfairLock(initialState: false)
        let answered = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let name = CTFontCopyPostScriptName(CTFontCreateWithName(postScriptName as CFString, 12, nil)) as String
            found.withLock { $0 = name == postScriptName }
            answered.signal()
        }
        return answered.wait(timeout: .now() + timeout) == .success && found.withLock { $0 }
    }

    static func installedOnDemandFontFamilies() -> Set<String> {
        Set(onDemandFonts.filter { isFontInstalled(postScriptName: $0.postScriptName) }.map(\.family))
    }

    /// Has macOS download the on-demand fonts it lacks. Returns when it finishes, fails (offline), or the time runs out;
    /// whatever is missing afterwards is covered by the fallback substitutes.
    static func downloadOnDemandFonts(
        _ postScriptNames: [String] = onDemandFonts.map(\.postScriptName),
        timeout: TimeInterval = 120
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // The handler and the timeout race; whichever comes first resumes, the other finds nothing left to do.
            let pending = OSAllocatedUnfairLock<CheckedContinuation<Void, Never>?>(initialState: continuation)
            let finish: @Sendable () -> Void = { pending.withLock { $0.take() }?.resume() }
            // Every CoreText call happens on this queue, never on the caller's thread: see `isFontInstalled`.
            DispatchQueue.global().async {
                let missing = postScriptNames.filter { !isFontInstalled(postScriptName: $0) }
                guard !missing.isEmpty else { return finish() }
                let descriptors = missing.map { CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: $0] as CFDictionary) }
                CTFontDescriptorMatchFontDescriptorsWithProgressHandler(descriptors as CFArray, nil) { state, _ in
                    if state == .didFinish { finish() }
                    return true
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: finish)
        }
    }

    /// The existing prefixes, one per runtime profile that has been configured.
    private var existingPrefixes: [URL] {
        let profiles = bottlesDirectory.appendingPathComponent("Profiles")
        return ((try? FileManager.default.contentsOfDirectory(at: profiles, includingPropertiesForKeys: nil)) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("system.reg").path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Whether a prefix's registry file already holds these substitutes, read the way Wine writes them:
    /// `"name"="target"` with every non-ASCII character of the name as `\xNNNN`.
    static func prefix(_ prefix: URL, has substitutes: [FontSubstitute]) -> Bool {
        // Searched as bytes: the file is several megabytes, and a String search of it takes long enough to stall the UI.
        guard let registry = try? Data(contentsOf: prefix.appendingPathComponent("system.reg"), options: .mappedIfSafe) else {
            return false
        }
        return substitutes.allSatisfy { substitute in
            let name = substitute.sourceName.utf16.map { $0 < 0x80 ? String(UnicodeScalar(UInt8($0))) : String(format: "\\x%04x", $0) }.joined()
            return registry.range(of: Data("\"\(name)\"=\"\(substitute.targetName)\"".utf8)) != nil
        }
    }

    /// Whether macOS has the optional Song and Hei fonts, and how many existing prefixes do not point at
    /// the best fonts available right now. A prefix configured by 1.x has no such substitutes at all.
    public func optionalFontStatus() -> OptionalFontStatus {
        let installed = Self.installedOnDemandFontFamilies()
        let wanted = Self.misreadJapaneseFontSubstitutes(installedFamilies: installed)
        return OptionalFontStatus(
            areFontsInstalled: installed.count == Self.onDemandFonts.count,
            outdatedPrefixCount: existingPrefixes.filter { !Self.prefix($0, has: wanted) }.count
        )
    }

    /// Has macOS download whichever optional font is missing, then points every existing prefix at what is installed,
    /// so nobody has to rebuild a prefix to get the fonts.
    public func installOptionalFonts() async throws {
        guard let wineBinary = wineManager?.wineBinaryURL else { throw WineError.wineNotInstalled }
        await Self.downloadOnDemandFonts()

        let wanted = Self.misreadJapaneseFontSubstitutes(installedFamilies: Self.installedOnDemandFontFamilies())
        let locale = BottleConfig(prefixPath: "").locale
        for prefix in existingPrefixes where !Self.prefix(prefix, has: wanted) {
            for substitute in wanted {
                try await runWineCommand(
                    wineBinary: wineBinary,
                    arguments: [
                        "reg", "add", "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes",
                        "/v", substitute.sourceName, "/t", "REG_SZ", "/d", substitute.targetName, "/f",
                    ],
                    prefix: prefix.path,
                    locale: locale
                )
            }
            // Wine writes the registry file when its server exits; wait so the status read right after sees it.
            WineProcess.waitForWineDescendants(
                wineBinary: wineBinary,
                environment: Self.wineCommandEnvironment(prefix: prefix.path, locale: locale)
            )
        }
    }

    /// Without these no font matches the misread name, every request falls back to the same default font,
    /// and a game's Mincho/Gothic (宋体/黑体) option changes nothing. Seen with 穢翼のユースティア (BGI).
    ///
    /// Such a game asks for an explicit cell (height 48, width 24), sized for the MS fonts. Wine derives the glyph size
    /// from the substitute's own line height and its width from the substitute's average character width, so the target
    /// has to match on both or the text comes out small, squeezed, or overlapping. The first choice of each pair matches;
    /// it is a font macOS downloads on demand, so it may be absent, and the second choice ships with every macOS.
    static func misreadJapaneseFontSubstitutes(installedFamilies: Set<String>) -> [FontSubstitute] {
        // SimSong: size 1.00, width 1.00 of what the game expects. STSong: 1.00 and 1.23, so its glyphs touch.
        let serif = installedFamilies.contains("SimSong") ? "SimSong" : "STSong"
        // STHeiti: 1.00 and 1.04. Arial Unicode MS: 0.75 and 1.13, readable but small; it is what Wine fell back to before.
        let sans = installedFamilies.contains("STHeiti") ? "STHeiti" : "Arial Unicode MS"
        return [
            ("ＭＳ 明朝", serif),
            ("ＭＳ Ｐ明朝", serif),
            ("ＭＳ ゴシック", sans),
            ("ＭＳ Ｐゴシック", sans),
        ].compactMap { name, target in
            misreadAsGBK(name).map { FontSubstitute(sourceName: $0, targetName: target) }
        }
    }

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
        case .mediaFoundation:
            return "gala-mf-runtime@1.0"
        }
    }
}
