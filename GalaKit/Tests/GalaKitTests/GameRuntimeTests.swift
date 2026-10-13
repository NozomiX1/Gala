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

@Test func videoSwitchBecomesLaunchOverridesAndHandWrittenOnesWin() {
    var game = Game(title: "T", executablePath: "/tmp/g/game.exe", bottleConfig: BottleConfig(prefixPath: "/tmp/p"))
    #expect(game.launchDLLOverrides.isEmpty)

    game.launchSwitches = ["video": "builtin"]
    #expect(game.launchDLLOverrides == ["quartz": "builtin", "amstream": "builtin"])

    game.launchSwitches = ["video": "native", "graphics": "dxmt"]
    game.bottleConfig.dllOverrides = ["quartz": "builtin", "d3dx9_43": "native"]
    #expect(game.launchDLLOverrides == ["quartz": "builtin", "amstream": "native,builtin", "d3dx9_43": "native"])

    let environment = WineLaunchConfig.buildEnvironment(game: game, wineBinary: URL(fileURLWithPath: "/tmp/wine/bin/wine"))
    #expect(environment["WINEDLLOVERRIDES"] == "amstream=native,builtin;d3dx9_43=native;quartz=builtin")
}

@Test func localeSwitchSetsTheLocaleWineStartsInAndNothingElse() {
    var game = Game(title: "T", executablePath: "/tmp/g/game.exe", bottleConfig: BottleConfig(prefixPath: "/tmp/p"))
    let wine = URL(fileURLWithPath: "/tmp/wine/bin/wine")
    #expect(WineLaunchConfig.buildEnvironment(game: game, wineBinary: wine)["LC_ALL"] == "zh_CN.UTF-8")

    game.launchSwitches = ["locale": "ja"]
    let environment = WineLaunchConfig.buildEnvironment(game: game, wineBinary: wine)
    #expect(environment["LC_ALL"] == "ja_JP.UTF-8")
    #expect(environment["LANG"] == "ja_JP.UTF-8")
    // Creating and repairing the prefix still follows the stored locale.
    #expect(game.bottleConfig.locale == "zh_CN.UTF-8")
    #expect(game.launchDLLOverrides.isEmpty)

    game.bottleConfig.locale = "ja_JP.UTF-8"
    game.launchSwitches = ["locale": "zh"]
    #expect(game.launchLocale == "zh_CN.UTF-8")
}

@Test func aProfilesDLLChoicesArePassedAtLaunchWithTheGamesOwnOnTop() throws {
    var game = Game(title: "SP", executablePath: "/tmp/g/SiglusEngine.exe", engine: .siglusEngine, bottleConfig: BottleConfig(prefixPath: "/tmp/p"))
    let wine = URL(fileURLWithPath: "/tmp/wine/bin/wine")
    let recipe = try #require(ProfileStore.bundled.recipe(for: game))

    let fromProfile = try #require(WineLaunchConfig.buildEnvironment(game: game, wineBinary: wine, recipe: recipe)["WINEDLLOVERRIDES"])
    #expect(fromProfile.contains("quartz=builtin"))
    #expect(fromProfile.contains("xaudio2_7=native"))

    game.launchSwitches = ["video": "native"]
    let withSwitch = try #require(WineLaunchConfig.buildEnvironment(game: game, wineBinary: wine, recipe: recipe)["WINEDLLOVERRIDES"])
    #expect(withSwitch.contains("quartz=native,builtin"))
    #expect(withSwitch.contains("xaudio2_7=native"))

    // A common game passes nothing: the components brought their own settings into the prefix.
    let bgi = Game(title: "B", executablePath: "/tmp/g/BGI.exe", engine: .bgi, bottleConfig: BottleConfig(prefixPath: "/tmp/p"))
    #expect(WineLaunchConfig.buildEnvironment(game: bgi, wineBinary: wine)["WINEDLLOVERRIDES"] == nil)
}

@Test func graphicsSwitchPicksTheWineBuildInBothDirections() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("gala-switch-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let wineManager = WineManager(baseURL: home)
    var kirikiri = Game(title: "K", executablePath: "/tmp/g/k.exe", engine: .kirikiri)
    var artemis = Game(title: "A", executablePath: "/tmp/g/a.exe", engine: .artemisD3D11)

    #expect(!wineManager.usesDXMTWine(for: kirikiri))
    #expect(wineManager.usesDXMTWine(for: artemis))

    kirikiri.launchSwitches = ["graphics": "dxmt"]
    artemis.launchSwitches = ["graphics": "builtin"]
    #expect(wineManager.usesDXMTWine(for: kirikiri))
    #expect(!wineManager.usesDXMTWine(for: artemis))

    // An option this version does not know is ignored rather than guessed at.
    artemis.launchSwitches = ["graphics": "vulkan"]
    #expect(wineManager.usesDXMTWine(for: artemis))
}

@Test func switchesSurviveSavingAndOldLibrariesLoadWithoutThem() throws {
    var game = Game(title: "T", executablePath: "/tmp/g/game.exe")
    game.launchSwitches = ["video": "builtin"]
    let data = try JSONEncoder().encode(game)
    #expect(try JSONDecoder().decode(Game.self, from: data).launchSwitches == ["video": "builtin"])

    var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["launchSwitches"] = nil
    let old = try JSONDecoder().decode(Game.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(old.launchSwitches.isEmpty)
}

@Test func exportedProfileCarriesTheSwitchesAndSurvivesJSON() throws {
    var game = Game(title: "千恋＊万花", executablePath: "/tmp/g/game.exe", engine: .kirikiri)
    game.launchSwitches = ["video": "builtin", "graphics": "dxmt"]
    game.bottleConfig.environment = ["FOO": "1"]
    game.bottleConfig.launchArguments = ["-windowed"]
    let base = try #require(ProfileStore.bundled.recipe(for: game))

    var file = game.exportedProfile(base: base)
    #expect(file.base == "common")
    #expect(file.wine == .dxmt)
    #expect(file.dllOverrides == ["quartz": "builtin", "amstream": "builtin"])
    // Nothing is left for a note to explain: the file holds the whole launch half.
    #expect(file.environment == ["FOO": "1"])
    #expect(file.launchArguments == ["-windowed"])
    #expect(file.locale == nil)
    #expect(file.notes == nil)

    game.launchSwitches["locale"] = "ja"
    file = game.exportedProfile(base: base)
    #expect(file.locale == "ja_JP.UTF-8")

    // Read back as someone else's profile, it launches a plain game the same way.
    let store = try ProfileStore(files: ProfileStore.bundledFiles + [file])
    let recipe = try #require(store.recipe(id: file.id))
    let other = Game(title: "T", executablePath: "/tmp/h/h.exe", profileID: file.id, bottleConfig: BottleConfig(prefixPath: "/tmp/p"))
    let environment = WineLaunchConfig.buildEnvironment(game: other, wineBinary: URL(fileURLWithPath: "/tmp/wine/bin/wine"), recipe: recipe)
    #expect(environment["FOO"] == "1")
    #expect(environment["LC_ALL"] == "ja_JP.UTF-8")
    #expect(environment["WINEDLLOVERRIDES"] == "amstream=builtin;quartz=builtin")
    #expect(try WineLaunchConfig.resolve(game: other, recipe: recipe).arguments == ["h.exe", "-windowed"])
    #expect(recipe.usesDXMTWine)
    #expect(recipe.bottleID == "common")

    // Round-trips through JSON the way a user's file is read.
    let decoded = try JSONDecoder().decode(ProfileFile.self, from: JSONEncoder().encode(file))
    #expect(decoded == file)
}

@Test func keyValueTextTakesSeveralPairsAndSkipsWhatIsNotOne() {
    #expect(BottleConfig.pairs(from: "quartz = builtin; nonsense;=x\nA=b=c；d3d9=native") == ["quartz": "builtin", "A": "b=c", "d3d9": "native"])
    #expect(BottleConfig.text(from: ["b": "2", "a": "1"]) == "a=1; b=2")
    #expect(BottleConfig.pairs(from: BottleConfig.text(from: ["b": "2", "a": "1"])) == ["b": "2", "a": "1"])
}
