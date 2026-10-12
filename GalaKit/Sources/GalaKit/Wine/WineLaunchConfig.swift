import Foundation

public struct MediaFoundationRuntime: Sendable {
    public let rootURL: URL
    public let gStreamerRegistryURL: URL

    public init(rootURL: URL, gStreamerRegistryURL: URL) {
        self.rootURL = rootURL
        self.gStreamerRegistryURL = gStreamerRegistryURL
    }
}

public struct WineLaunchConfig: Sendable {
    public struct DriveMapping: Sendable {
        public let driveLetter: String
        public let targetPath: String
    }

    public let arguments: [String]
    public let workingDirectory: URL?
    public let driveMapping: DriveMapping?

    public static func buildEnvironment(
        game: Game,
        wineBinary: URL,
        mediaFoundationRuntime: MediaFoundationRuntime? = nil,
        debug: Bool = false,
        recipe: RuntimeRecipe? = nil
    ) -> [String: String] {
        let recipe = recipe ?? ProfileStore.bundled.recipe(for: game)
        var env = ProcessInfo.processInfo.environment

        env["WINEPREFIX"] = game.bottleConfig.prefixPath
        env["LANG"] = game.bottleConfig.locale
        env["LC_ALL"] = game.bottleConfig.locale
        // Errors are always kept, so the first failed launch already has something to show.
        // Debug adds Wine's fixme lines and which DLLs load as native or builtin.
        env["WINEDEBUG"] = debug ? "+loaddll" : "fixme-all"
        env["MVK_CONFIG_LOG_LEVEL"] = "0"

        // Only set DYLD_FALLBACK_LIBRARY_PATH if the lib directories actually exist.
        // Setting it to non-existent paths overrides system defaults and breaks Wine.
        let wineRoot = wineBinary
            .deletingLastPathComponent().deletingLastPathComponent()
        let libExternal = wineRoot.appendingPathComponent("lib/external").path
        let lib = wineRoot.appendingPathComponent("lib").path
        let existingLibPaths = [libExternal, lib].filter {
            FileManager.default.fileExists(atPath: $0)
        }
        if !existingLibPaths.isEmpty {
            prependLibraryPaths(existingLibPaths, to: &env)
        }

        if recipe?.usesMediaFoundation == true, let mediaFoundationRuntime {
            applyMediaFoundationRuntime(mediaFoundationRuntime, to: &env)
        }

        let dllOverrides = game.launchDLLOverrides
        if !dllOverrides.isEmpty {
            env["WINEDLLOVERRIDES"] = dllOverrides.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }.joined(separator: ";")
        }

        for (key, value) in game.bottleConfig.environment {
            env[key] = value
        }

        return env
    }

    private static func applyMediaFoundationRuntime(
        _ runtime: MediaFoundationRuntime,
        to env: inout [String: String]
    ) {
        let lib = runtime.rootURL.appendingPathComponent("lib")
        let pluginDir = runtime.rootURL.appendingPathComponent("lib/gstreamer-1.0")
        let scanner = runtime.rootURL.appendingPathComponent("libexec/gstreamer-1.0/gst-plugin-scanner")

        if FileManager.default.fileExists(atPath: lib.path) {
            prependLibraryPaths([lib.path], to: &env)
        }
        if FileManager.default.fileExists(atPath: pluginDir.path) {
            env["GST_PLUGIN_PATH_1_0"] = pluginDir.path
            env["GST_PLUGIN_SYSTEM_PATH_1_0"] = ""
        }
        if FileManager.default.isExecutableFile(atPath: scanner.path) {
            env["GST_PLUGIN_SCANNER_1_0"] = scanner.path
        }

        env["GST_REGISTRY"] = runtime.gStreamerRegistryURL.path
        env["GST_REGISTRY_FORK"] = "no"
    }

    private static func prependLibraryPaths(_ paths: [String], to env: inout [String: String]) {
        let existing = env["DYLD_FALLBACK_LIBRARY_PATH"] ?? ""
        let all = paths + (existing.isEmpty ? [] : [existing])
        env["DYLD_FALLBACK_LIBRARY_PATH"] = all.joined(separator: ":")
    }

    public static func resolve(game: Game, recipe: RuntimeRecipe? = nil) throws -> WineLaunchConfig {
        let recipe = recipe ?? ProfileStore.bundled.recipe(for: game)
        let exeURL = URL(fileURLWithPath: game.executablePath)
        let gameDir = exeURL.deletingLastPathComponent()
        let exeName = exeURL.lastPathComponent
        let shouldMapGameDirectory = recipe?.features.contains(.gameDriveG) == true ||
            !gameDir.path.canBeConverted(to: .ascii)

        if !shouldMapGameDirectory {
            return WineLaunchConfig(
                arguments: game.bottleConfig.launchArguments + [exeName],
                workingDirectory: gameDir,
                driveMapping: nil
            )
        }

        // Map the game directory as G: for non-ASCII paths and for games whose
        // install registry points at G:\.
        let dosdevices = URL(fileURLWithPath: game.bottleConfig.prefixPath)
            .appendingPathComponent("dosdevices")
        try FileManager.default.createDirectory(at: dosdevices, withIntermediateDirectories: true)
        let gDrive = dosdevices.appendingPathComponent("g:")
        try? FileManager.default.removeItem(at: gDrive)
        try FileManager.default.createSymbolicLink(
            atPath: gDrive.path, withDestinationPath: gameDir.path
        )

        return WineLaunchConfig(
            arguments: game.bottleConfig.launchArguments + ["g:\\" + exeName],
            workingDirectory: gameDir,
            driveMapping: DriveMapping(driveLetter: "g:", targetPath: gameDir.path)
        )
    }
}
