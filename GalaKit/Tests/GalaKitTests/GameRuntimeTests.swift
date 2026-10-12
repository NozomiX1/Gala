import Testing
import Foundation
@testable import GalaKit

/// A data directory with a fake Wine binary, so the checks that only look at the file system can run.
private func makeRuntime() throws -> (GameRuntime, URL) {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let wineManager = WineManager(baseURL: home)
    let wine = wineManager.wineDirectory.appendingPathComponent("active/Contents/Resources/wine/bin/wine")
    try FileManager.default.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: wine.path, contents: Data("x".utf8))
    return (GameRuntime(wineManager: wineManager), home)
}

private func game(_ engine: Engine, in runtime: GameRuntime, configured: Bool = true) -> Game {
    let prefix = BottleManager(bottlesDirectory: runtime.wineManager.bottlesDirectory).prefixPath(for: engine)
    return Game(
        title: "Test",
        executablePath: "/games/test/game.exe",
        engine: engine,
        isRuntimeConfigured: configured,
        bottleConfig: BottleConfig(prefixPath: prefix)
    )
}

private func makeBottleReady(for game: Game) throws {
    let prefix = URL(fileURLWithPath: game.bottleConfig.prefixPath)
    try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: prefix.appendingPathComponent("system.reg").path, contents: nil)
}

private func blocker(_ body: () throws -> URL) -> LaunchBlocker? {
    do { _ = try body(); return nil } catch { return error as? LaunchBlocker }
}

@Test func launchIsBlockedUntilTheGameIsConfigured() throws {
    let (runtime, home) = try makeRuntime()
    defer { try? FileManager.default.removeItem(at: home) }

    #expect(blocker { try runtime.wineBinaryForLaunch(game(.bgi, in: runtime, configured: false)) } == .notConfigured)
}

@Test func launchIsBlockedWhenTheBottleIsGone() throws {
    let (runtime, home) = try makeRuntime()
    defer { try? FileManager.default.removeItem(at: home) }

    let result = blocker { try runtime.wineBinaryForLaunch(game(.bgi, in: runtime)) }

    #expect(result == .bottleMissing)
    #expect(result?.requiresReconfiguration == true)
}

@Test func launchIsBlockedWhenTheDXMTWineVariantIsMissing() throws {
    let (runtime, home) = try makeRuntime()
    defer { try? FileManager.default.removeItem(at: home) }

    #expect(blocker { try runtime.wineBinaryForLaunch(game(.artemisD3D11, in: runtime)) } == .dxmtMissing)
}

@Test func launchIsBlockedWhenTheProfileMarkerIsOutdated() throws {
    let (runtime, home) = try makeRuntime()
    defer { try? FileManager.default.removeItem(at: home) }
    let game = game(.bgi, in: runtime)
    try makeBottleReady(for: game)
    let stale = #"{"profile":"common","configVersion":0,"configuredAt":"2026-01-01T00:00:00Z","wineVersionName":"wine-staging-11.6","managedComponents":[]}"#
    try Data(stale.utf8).write(to: URL(fileURLWithPath: game.bottleConfig.prefixPath).appendingPathComponent(".gala-runtime.json"))

    #expect(blocker { try runtime.wineBinaryForLaunch(game) } == .presetOutdated)
}

@Test func launchUsesTheManagedWineWhenTheBottleIsCurrent() throws {
    let (runtime, home) = try makeRuntime()
    defer { try? FileManager.default.removeItem(at: home) }
    let game = game(.bgi, in: runtime)
    try makeBottleReady(for: game)
    try BottleManager(bottlesDirectory: runtime.wineManager.bottlesDirectory).writeRuntimeMarker(for: game)

    #expect(try runtime.wineBinaryForLaunch(game).lastPathComponent == "wine")
}

@Test func configureReusesACurrentBottleWithoutRunningWine() async throws {
    let (runtime, home) = try makeRuntime()
    defer { try? FileManager.default.removeItem(at: home) }
    let game = game(.bgi, in: runtime, configured: false)
    try makeBottleReady(for: game)
    try BottleManager(bottlesDirectory: runtime.wineManager.bottlesDirectory).writeRuntimeMarker(for: game)

    let messages = Messages()
    // The fake Wine binary cannot run, so this only succeeds if no Wine command is attempted.
    try await runtime.configure(game) { message, _ in messages.append(message) }

    #expect(messages.all.last == "复用已有运行环境...")
}

@Test func configureFailsEarlyWithoutWine() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let runtime = GameRuntime(wineManager: WineManager(baseURL: home))

    await #expect(throws: LaunchBlocker.wineMissing) {
        try await runtime.configure(game(.bgi, in: runtime, configured: false)) { _, _ in }
    }
}

private final class Messages: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func append(_ message: String) { lock.lock(); items.append(message); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}
