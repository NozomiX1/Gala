import Testing
import Foundation
@testable import GalaKit

// Engine.recipe force-unwraps this lookup, so every engine's default profile must ship as a file.
@Test(arguments: Engine.allCases)
func everyEngineHasABundledProfile(engine: Engine) {
    #expect(ProfileStore.bundled.recipe(id: engine.runtimeProfile.rawValue) != nil)
}

// These versions are what existing prefixes were marked with; lowering or raising one makes them reconfigure.
@Test func bundledProfilesKeepTheVersionsExistingPrefixesWereMarkedWith() {
    let versions = Dictionary(uniqueKeysWithValues: ProfileStore.bundled.recipes.map { ($0.id, $0.version) })

    #expect(versions == [
        "common": 1, "kirikiri": 1, "cat-system2": 1, "siglus-engine": 1,
        "leaf": 1, "do-kizunar": 1, "artemis-d3d11": 4, "artemis-mf-d3d11": 2,
    ])
    #expect(Engine.artemisD3D11.usesDXMTWineVariant)
    #expect(Engine.artemisMFD3D11.usesDXMTWineVariant)
    #expect(!Engine.kirikiri.usesDXMTWineVariant)
}

@Test func markerWithoutAFingerprintStaysCurrentButAnEditedRecipeDoesNot() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let manager = BottleManager(bottlesDirectory: dir)
    var game = Game(title: "T", executablePath: "/g/a.exe", engine: .kirikiri,
                    bottleConfig: BottleConfig(prefixPath: dir.appendingPathComponent("Profiles/kirikiri").path))
    // Where the migration leaves a KiriKiri game configured before that engine moved to common.
    game.profileID = "kirikiri"
    let markerURL = URL(fileURLWithPath: game.bottleConfig.prefixPath).appendingPathComponent(".gala-runtime.json")
    try FileManager.default.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let marker = { (fingerprint: String) in
        #"{"profile":"kirikiri","configVersion":1,"configuredAt":"2026-01-01T00:00:00Z","wineVersionName":"wine-staging-11.6","managedComponents":[]\#(fingerprint)}"#
    }

    // Written by 1.x: no fingerprint, so only the version decides.
    try Data(marker("").utf8).write(to: markerURL)
    #expect(try manager.runtimeMarkerStatus(for: game) == .current)

    // Written by 2.0 from a recipe that has since been edited.
    try Data(marker(#","recipeFingerprint":"something-else""#).utf8).write(to: markerURL)
    #expect(try manager.runtimeMarkerStatus(for: game) == .outdated)

    try manager.writeRuntimeMarker(for: game)
    #expect(try manager.runtimeMarkerStatus(for: game) == .current)
}

private func file(_ id: String, base: String? = nil, version: Int? = nil, components: [String]? = nil,
                  managed: [String]? = nil, dll: [String: String?]? = nil) -> ProfileFile {
    ProfileFile(id: id, name: id, base: base, version: version, components: components, managedComponents: managed, dllOverrides: dll)
}

@Test func derivedProfileAddsOverridesAndRemovesWhatItNullsOut() throws {
    let store = try ProfileStore(files: [
        file("base", components: ["quartz"], dll: ["quartz": "native", "amstream": "native"]),
        file("child", base: "base", components: ["d3dx9", "quartz"], dll: ["quartz": "builtin", "amstream": String?.none]),
    ])
    let child = try #require(store.recipe(id: "child"))

    #expect(child.preset.components == ["quartz", "d3dx9"])
    #expect(child.preset.dllOverrides == ["quartz": "builtin"])
}

@Test func askingForTheDXMTWineAlsoAsksForItsDownload() throws {
    let store = try ProfileStore(files: [file("base"), ProfileFile(id: "child", name: "child", base: "base", wine: .dxmt)])

    #expect(store.recipe(id: "child")?.preset.managedComponents == [.dxmt])
    #expect(store.recipe(id: "base")?.preset.managedComponents == [])
}

@Test func bumpingABaseVersionRaisesEveryProfileBuiltOnIt() throws {
    let before = try ProfileStore(files: [file("base"), file("child", base: "base", version: 3)])
    let after = try ProfileStore(files: [file("base", version: 2), file("child", base: "base", version: 3)])

    #expect(before.recipe(id: "child")?.version == 3)
    #expect(after.recipe(id: "child")?.version == 4)
}

@Test func fingerprintFollowsThePrefixContentsNotTheLabels() throws {
    let a = try #require(try ProfileStore(files: [file("a", dll: ["quartz": "native"])]).recipe(id: "a"))
    let renamed = try #require(try ProfileStore(files: [ProfileFile(id: "b", name: "别的名字", notes: "说明", dllOverrides: ["quartz": "native"])]).recipe(id: "b"))
    let changed = try #require(try ProfileStore(files: [file("a", dll: ["quartz": "builtin"])]).recipe(id: "a"))

    #expect(a.fingerprint == renamed.fingerprint)
    #expect(a.fingerprint != changed.fingerprint)
}

@Test func brokenProfileSetsAreRejectedWithTheReason() {
    #expect(throws: ProfileError.duplicate(id: "a")) { try ProfileStore(files: [file("a"), file("a")]) }
    #expect(throws: ProfileError.unknownBase(id: "a", base: "missing")) { try ProfileStore(files: [file("a", base: "missing")]) }
    #expect(throws: ProfileError.cycle(id: "a")) { try ProfileStore(files: [file("a", base: "b"), file("b", base: "a")]) }
    #expect(throws: ProfileError.unknownManagedComponent(id: "a", component: "nope")) { try ProfileStore(files: [file("a", managed: ["nope"])]) }
}

@Test func nullInAProfileFileDecodesAsARemoval() throws {
    let json = #"{"id":"x","name":"x","base":"common","dllOverrides":{"amstream":null,"quartz":"builtin"}}"#
    let decoded = try JSONDecoder().decode(ProfileFile.self, from: Data(json.utf8))

    #expect(decoded.dllOverrides?["quartz"] == .some("builtin"))
    #expect(decoded.dllOverrides?["amstream"] == .some(nil))
}

// MARK: - User profiles and per-game choice

private func userDirectory(_ files: [String: String]) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (name, content) in files {
        try Data(content.utf8).write(to: dir.appendingPathComponent(name))
    }
    return dir
}

@Test func userProfileBuildsOnABundledOneAndIsMarkedAsTheUsers() throws {
    let dir = try userDirectory(["mine.json": #"{"id":"my-noraneko","name":"我的修改","base":"kirikiri","dllOverrides":{"quartz":"builtin"}}"#])
    defer { try? FileManager.default.removeItem(at: dir) }

    let (store, problems) = ProfileStore.loading(userDirectory: dir)
    let mine = try #require(store.recipe(id: "my-noraneko"))

    #expect(problems.isEmpty)
    #expect(mine.isUserProvided)
    #expect(mine.preset.dllOverrides["quartz"] == "builtin")
    #expect(mine.preset.components == ["quartz", "amstream", "lavfilters"])
    #expect(store.recipe(id: "kirikiri")?.isUserProvided == false)
    #expect(mine.fingerprint != store.recipe(id: "kirikiri")?.fingerprint)
}

@Test func userFileWithABundledIdReplacesItForEveryProfileBuiltOnIt() throws {
    let dir = try userDirectory(["common.json": #"{"id":"common","name":"我的通用","components":["quartz"]}"#])
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = ProfileStore.loading(userDirectory: dir).store

    #expect(store.recipe(id: "common")?.isUserProvided == true)
    #expect(store.recipe(id: "kirikiri")?.preset.components == ["quartz"])
    #expect(ProfileStore.bundled.recipe(id: "kirikiri")?.preset.components == ["quartz", "amstream", "lavfilters"])
}

@Test func brokenUserFilesAreLeftOutAndReportedWithoutLosingTheRest() throws {
    let dir = try userDirectory([
        "a-not-json.json": "{ this is not json",
        "b-bad-base.json": #"{"id":"orphan","name":"x","base":"no-such-profile"}"#,
        "c-good.json": #"{"id":"good","name":"好的","base":"common"}"#,
        "notes.txt": "ignored",
    ])
    defer { try? FileManager.default.removeItem(at: dir) }

    let (store, problems) = ProfileStore.loading(userDirectory: dir)

    #expect(store.recipe(id: "good") != nil)
    #expect(store.recipe(id: "orphan") == nil)
    #expect(store.recipes.count == ProfileStore.bundled.recipes.count + 1)
    #expect(problems.count == 2)
    #expect(problems.contains(.unknownBase(id: "orphan", base: "no-such-profile")))
}

@Test func aGameUsesItsChosenProfileAndFallsBackWhenThatProfileIsGone() throws {
    let dir = try userDirectory(["mine.json": #"{"id":"mine","name":"我的","base":"common"}"#])
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = ProfileStore.loading(userDirectory: dir).store
    var game = Game(title: "T", executablePath: "/g/a.exe", engine: .kirikiri)

    #expect(store.recipe(for: game)?.id == "common")

    game.profileID = "mine"
    #expect(store.recipe(for: game)?.id == "mine")

    game.profileID = "deleted-since"
    #expect(store.recipe(for: game)?.id == "common")

    #expect(try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game)).profileID == "deleted-since")
}

@Test func chosenProfileDecidesTheWineVariantTheGameDriveAndTheMarker() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let wineManager = WineManager(baseURL: home)
    try Data(#"{"id":"mine","name":"我的","base":"do-kizunar","wine":"dxmt"}"#.utf8)
        .write(to: wineManager.profilesDirectory.appendingPathComponent("mine.json"))
    wineManager.reloadProfiles()
    let dxmtWine = wineManager.dxmtWineDirectory.appendingPathComponent("Contents/Resources/wine/bin/wine")
    try FileManager.default.createDirectory(at: dxmtWine.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: dxmtWine.path, contents: Data("x".utf8))

    let bottleManager = BottleManager(bottlesDirectory: wineManager.bottlesDirectory, wineManager: wineManager)
    var game = Game(title: "T", executablePath: "/games/t/a.exe", engine: .bgi, profileID: nil,
                    bottleConfig: BottleConfig(prefixPath: bottleManager.prefixPath(forProfile: "mine")))
    game.profileID = "mine"
    let recipe = try #require(wineManager.profiles.recipe(for: game))

    #expect(wineManager.wineBinaryURL(for: game)?.path == dxmtWine.path)
    #expect(try WineLaunchConfig.resolve(game: game, recipe: recipe).driveMapping?.driveLetter == "g:")
    #expect(try WineLaunchConfig.resolve(game: Game(title: "T", executablePath: "/games/t/a.exe", engine: .bgi,
                                                    bottleConfig: BottleConfig(prefixPath: game.bottleConfig.prefixPath))).driveMapping == nil)

    try bottleManager.writeRuntimeMarker(for: game)
    #expect(try bottleManager.runtimeMarkerStatus(for: game) == .current)
    let marker = try String(contentsOf: URL(fileURLWithPath: game.bottleConfig.prefixPath).appendingPathComponent(".gala-runtime.json"), encoding: .utf8)
    #expect(marker.contains(#""profile" : "mine""#))

    // Editing the file makes the prefix stale without anyone touching a version number.
    try Data(#"{"id":"mine","name":"我的","base":"do-kizunar","wine":"dxmt","dllOverrides":{"quartz":"native"}}"#.utf8)
        .write(to: wineManager.profilesDirectory.appendingPathComponent("mine.json"))
    wineManager.reloadProfiles()
    #expect(try bottleManager.runtimeMarkerStatus(for: game) == .outdated)
}

@Test func migrationLeavesAHandPickedProfileAlone() {
    let bottles = URL(fileURLWithPath: "/tmp/Gala/Bottles")
    var game = Game(title: "T", executablePath: "/games/unity/game.exe", engine: .unity, isRuntimeConfigured: true,
                    runtimeProfileMigrationVersion: 1,
                    bottleConfig: BottleConfig(prefixPath: bottles.appendingPathComponent("Profiles/mine").path))
    game.profileID = "mine"

    let migrated = RuntimeProfileMigration.migrate(games: [game], bottlesDirectory: bottles) { _ in .artemisD3D11 }

    #expect(migrated[0].bottleConfig.prefixPath == game.bottleConfig.prefixPath)
    #expect(migrated[0].isRuntimeConfigured)
    #expect(migrated[0].engine == .unity)
}

@Test func compatibilityDocumentMatchesTheBundledProfiles() throws {
    let document = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/compatibility.md")

    // Out of date? Run: swift run --package-path GalaKit gala-cli compat > docs/compatibility.md
    #expect(try String(contentsOf: document, encoding: .utf8) == ProfileStore.bundled.compatibilityMarkdown)
}
