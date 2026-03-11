import Foundation

public struct WineLaunchConfig: Sendable {
    public struct DriveMapping: Sendable {
        public let driveLetter: String
        public let targetPath: String
    }

    public let arguments: [String]
    public let workingDirectory: URL?
    public let driveMapping: DriveMapping?

    public static func buildEnvironment(game: Game, wineBinary: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        env["WINEPREFIX"] = game.bottleConfig.prefixPath
        env["LANG"] = game.bottleConfig.locale
        env["LC_ALL"] = game.bottleConfig.locale

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
            let existing = env["DYLD_FALLBACK_LIBRARY_PATH"] ?? ""
            let all = existingLibPaths + (existing.isEmpty ? [] : [existing])
            env["DYLD_FALLBACK_LIBRARY_PATH"] = all.joined(separator: ":")
        }

        if !game.bottleConfig.dllOverrides.isEmpty {
            let overrides = game.bottleConfig.dllOverrides
                .map { "\($0.key)=\($0.value)" }.joined(separator: ";")
            env["WINEDLLOVERRIDES"] = overrides
        }

        for (key, value) in game.bottleConfig.environment {
            env[key] = value
        }

        return env
    }

    public static func resolve(game: Game) throws -> WineLaunchConfig {
        let exeURL = URL(fileURLWithPath: game.executablePath)
        let gameDir = exeURL.deletingLastPathComponent()
        let exeName = exeURL.lastPathComponent

        if gameDir.path.canBeConverted(to: .ascii) {
            return WineLaunchConfig(
                arguments: game.bottleConfig.launchArguments + [exeName],
                workingDirectory: gameDir,
                driveMapping: nil
            )
        }

        // Non-ASCII path: map game directory as G: drive for the exe argument.
        // Also set workingDirectory so child processes (e.g. patch launchers)
        // can find sibling executables via relative paths.
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
