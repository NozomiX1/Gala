import Testing
import Foundation
@testable import GalaKit

@Test func bottleManagerWritesRuntimeMarkerAfterConfiguration() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let prefix = tempDir.appendingPathComponent("Profiles/artemis-d3d11")
    let game = Game(
        title: "Amakano 3",
        executablePath: "/Games/Amakano3/Amakano3_chs.exe",
        engine: .artemisD3D11,
        bottleConfig: BottleConfig(prefixPath: prefix.path)
    )
    let configuredAt = Date(timeIntervalSince1970: 1_800_000_000)
    let bottleManager = BottleManager(bottlesDirectory: tempDir)

    try bottleManager.writeRuntimeMarker(for: game, configuredAt: configuredAt)

    let markerURL = prefix.appendingPathComponent(".gala-runtime.json")
    let data = try Data(contentsOf: markerURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let marker = try decoder.decode(RuntimeProfileMarker.self, from: data)

    // artemis-d3d11 lives in common's prefix, so the marker is common's and both kinds of game read it as current.
    #expect(marker.profile == "common")
    #expect(marker.configVersion == Engine.bgi.runtimeConfigVersion)
    #expect(marker.wineVersionName == WineManager.wineVersionName)
    #expect(marker.managedComponents == [])
    #expect(marker.configuredAt == configuredAt)
    #expect(try bottleManager.runtimeMarkerStatus(for: game) == .current)
    let commonGame = Game(title: "BGI", executablePath: "/Games/b/BGI.exe", engine: .bgi,
                          bottleConfig: BottleConfig(prefixPath: prefix.path))
    #expect(try bottleManager.runtimeMarkerStatus(for: commonGame) == .current)
}

@Test func aPrefixMarkedByArtemisD3D11BeforeItSharedABottleStaysCurrent() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let prefix = tempDir.appendingPathComponent("Profiles/artemis-d3d11")
    try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
    let game = Game(title: "ハミダシ", executablePath: "/Games/h/h.exe", engine: .artemisD3D11,
                    isRuntimeConfigured: true, bottleConfig: BottleConfig(prefixPath: prefix.path))
    // As 2.0 wrote it.
    let recipe = try #require(ProfileStore.bundled.recipe(id: "artemis-d3d11"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(RuntimeProfileMarker.current(for: recipe, configuredAt: Date()))
        .write(to: prefix.appendingPathComponent(".gala-runtime.json"))

    #expect(try BottleManager(bottlesDirectory: tempDir).runtimeMarkerStatus(for: game) == .current)
}

@Test func bottleManagerWritesDXMTMarkerForArtemisMediaFoundationProfile() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let prefix = tempDir.appendingPathComponent("Profiles/artemis-mf-d3d11")
    let game = Game(
        title: "Amakano 3",
        executablePath: "/Games/Amakano3/Amakano3_chs.exe",
        engine: .artemisMFD3D11,
        bottleConfig: BottleConfig(prefixPath: prefix.path)
    )
    let bottleManager = BottleManager(bottlesDirectory: tempDir)

    try bottleManager.writeRuntimeMarker(for: game)

    let markerURL = prefix.appendingPathComponent(".gala-runtime.json")
    let data = try Data(contentsOf: markerURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let marker = try decoder.decode(RuntimeProfileMarker.self, from: data)

    #expect(marker.profile == "artemis-mf-d3d11")
    #expect(marker.configVersion == Engine.artemisMFD3D11.runtimeConfigVersion)
    #expect(marker.wineVersionName == WineManager.dxmtWineVersionName)
    #expect(marker.managedComponents == ["dxmt@v0.80", "gala-mf-runtime@1.0"])
}

@Test func runtimeMarkerStatusDetectsOutdatedConfigVersion() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let prefix = tempDir.appendingPathComponent("Profiles/common")
    let game = Game(
        title: "BGI",
        executablePath: "/Games/BGI.exe",
        engine: .bgi,
        bottleConfig: BottleConfig(prefixPath: prefix.path)
    )
    let marker = RuntimeProfileMarker(
        profile: "common",
        configVersion: 0,
        configuredAt: Date(timeIntervalSince1970: 1_700_000_000),
        wineVersionName: WineManager.wineVersionName,
        managedComponents: []
    )
    try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(marker).write(to: prefix.appendingPathComponent(".gala-runtime.json"))

    #expect(try BottleManager(bottlesDirectory: tempDir).runtimeMarkerStatus(for: game) == .outdated)
}

@Test func runtimeMarkerStatusMissingDoesNotForceReconfiguration() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let game = Game(
        title: "Existing Bottle",
        executablePath: "/Games/game.exe",
        engine: .bgi,
        bottleConfig: BottleConfig(prefixPath: tempDir.appendingPathComponent("Profiles/common").path)
    )

    #expect(try BottleManager(bottlesDirectory: tempDir).runtimeMarkerStatus(for: game) == .missing)
}

/// A stand-in for a built prefix: the file Wine leaves behind, something to tell copies apart, and a marker.
private func makeBuiltPrefix(_ manager: BottleManager, profile: String, markerJSON: String? = nil) throws -> URL {
    let prefix = URL(fileURLWithPath: manager.prefixPath(forProfile: profile))
    try FileManager.default.createDirectory(at: prefix.appendingPathComponent("drive_c"), withIntermediateDirectories: true)
    try Data("registry of \(profile)".utf8).write(to: prefix.appendingPathComponent("system.reg"))
    try Data("quartz\namstream\nlavfilters\n".utf8).write(to: prefix.appendingPathComponent("winetricks.log"))
    if let markerJSON {
        try Data(markerJSON.utf8).write(to: prefix.appendingPathComponent(".gala-runtime.json"))
    } else {
        try manager.writeRuntimeMarker(for: Game(title: profile, executablePath: "/g/a.exe", profileID: profile,
                                                 bottleConfig: BottleConfig(prefixPath: prefix.path)))
    }
    return prefix
}

@Test func aNewPrefixStartsAsACopyOfItsBuiltBase() async throws {
    let bottles = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: bottles) }
    let manager = BottleManager(bottlesDirectory: bottles)
    let common = try makeBuiltPrefix(manager, profile: "common")

    let leaf = Game(title: "WA2", executablePath: "/g/WA2.exe", engine: .leaf,
                    bottleConfig: BottleConfig(prefixPath: manager.prefixPath(for: Engine.leaf)))
    #expect(manager.cloneSource(for: leaf)?.path == common.path)

    // No Wine is needed for this path, which is the point: nothing is installed again.
    try await manager.createBottle(for: leaf)
    let prefix = URL(fileURLWithPath: leaf.bottleConfig.prefixPath)
    #expect(try String(contentsOf: prefix.appendingPathComponent("system.reg"), encoding: .utf8) == "registry of common")
    #expect(FileManager.default.fileExists(atPath: prefix.appendingPathComponent("winetricks.log").path))
    // Not yet marked: the game's own registry values still have to be written.
    #expect(try manager.runtimeMarkerStatus(for: leaf) == .missing)
    #expect(manager.isBottleReady(for: leaf))

    // A profile without a base, and common itself, have nothing to copy.
    let mf = Game(title: "A3", executablePath: "/g/a.exe", engine: .artemisMFD3D11,
                  bottleConfig: BottleConfig(prefixPath: manager.prefixPath(for: Engine.artemisMFD3D11)))
    #expect(manager.cloneSource(for: mf) == nil)
    let bgi = Game(title: "B", executablePath: "/g/b.exe", engine: .bgi,
                   bottleConfig: BottleConfig(prefixPath: manager.prefixPath(for: Engine.bgi)))
    #expect(manager.cloneSource(for: bgi) == nil)
}

@Test func anOlderPrefixWithDLLOverridesWrittenIntoItIsNotCopied() throws {
    let bottles = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: bottles) }
    let wineManager = WineManager(baseURL: bottles)
    try Data(#"{"id":"on-leaf","name":"x","base":"leaf","components":["xact"]}"#.utf8)
        .write(to: wineManager.profilesDirectory.appendingPathComponent("on-leaf.json"))
    wineManager.reloadProfiles()
    let manager = BottleManager(bottlesDirectory: wineManager.bottlesDirectory, wineManager: wineManager)
    let older = { (profile: String) in
        #"{"profile":"\#(profile)","configVersion":1,"configuredAt":"2026-01-01T00:00:00Z","wineVersionName":"wine-staging-11.6","managedComponents":[],"recipeFingerprint":"from-2.1"}"#
    }
    // As 2.1 left them: common's own overrides equal what winetricks writes, leaf's do not.
    let common = try makeBuiltPrefix(manager, profile: "common", markerJSON: older("common"))
    _ = try makeBuiltPrefix(manager, profile: "leaf", markerJSON: older("leaf"))

    var game = Game(title: "T", executablePath: "/g/a.exe", engine: .bgi)
    game.useProfile("on-leaf", bottlesDirectory: wineManager.bottlesDirectory, profiles: wineManager.profiles)
    #expect(game.bottleConfig.prefixPath.hasSuffix("Profiles/on-leaf"))
    #expect(wineManager.profiles.recipe(id: "on-leaf")?.cloneCandidates == ["leaf", "common"])
    #expect(manager.cloneSource(for: game)?.path == common.path)

    // Finding the older prefix current rewrites its marker, and the marker remembers what the prefix carries.
    let leafGame = Game(title: "WA2", executablePath: "/g/WA2.exe", engine: .leaf, isRuntimeConfigured: true,
                        bottleConfig: BottleConfig(prefixPath: manager.prefixPath(forProfile: "leaf")))
    manager.adoptOlderMarker(for: leafGame)
    #expect(try manager.runtimeMarkerStatus(for: leafGame) == .current)
    #expect(try String(contentsOf: URL(fileURLWithPath: leafGame.bottleConfig.prefixPath).appendingPathComponent(".gala-runtime.json"), encoding: .utf8).contains(#""carriesDLLOverrides" : true"#))
    #expect(manager.cloneSource(for: game)?.path == common.path)
    // Reconfiguring it in place does not make it clean either.
    try manager.writeRuntimeMarker(for: leafGame)
    #expect(manager.cloneSource(for: game)?.path == common.path)

    // Built by this version, leaf's prefix holds no DLL overrides of Gala's and is the nearer source.
    try FileManager.default.removeItem(atPath: leafGame.bottleConfig.prefixPath)
    let leaf = try makeBuiltPrefix(manager, profile: "leaf")
    #expect(manager.cloneSource(for: game)?.path == leaf.path)
}

@Test func aFlattenedProfileStartsFromThePrefixOfTheAttemptItReplaces() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let wineManager = WineManager(baseURL: home)
    for (id, components) in [("one", #"["d3dx9"]"#), ("two", #"["d3dx9","wmp11"]"#)] {
        try Data(#"{"id":"\#(id)","name":"\#(id)","base":"common","components":\#(components)}"#.utf8)
            .write(to: wineManager.profilesDirectory.appendingPathComponent("\(id).json"))
    }
    wineManager.reloadProfiles()
    let manager = BottleManager(bottlesDirectory: wineManager.bottlesDirectory, wineManager: wineManager)
    let one = try makeBuiltPrefix(manager, profile: "one")

    #expect(manager.seedPrefix(forProfile: "two", fromProfile: "one"))
    let two = URL(fileURLWithPath: manager.prefixPath(forProfile: "two"))
    #expect(try String(contentsOf: two.appendingPathComponent("system.reg"), encoding: .utf8) == "registry of one")
    #expect(!FileManager.default.fileExists(atPath: two.appendingPathComponent(".gala-runtime.json").path))
    // Never over a prefix that is already there.
    #expect(!manager.seedPrefix(forProfile: "two", fromProfile: "one"))

    // The earlier attempt's prefix goes with it; common's is not a derived profile's to delete.
    manager.deletePrefix(ownedByProfile: "one")
    #expect(!FileManager.default.fileExists(atPath: one.path))
    _ = try makeBuiltPrefix(manager, profile: "common")
    manager.deletePrefix(ownedByProfile: "artemis-d3d11")
    #expect(FileManager.default.fileExists(atPath: manager.prefixPath(forProfile: "common")))
}

@Test func prefixesNoGamePointsAtAreFound() throws {
    let bottles = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: bottles) }
    let manager = BottleManager(bottlesDirectory: bottles)
    for name in ["common", "leaf", "my-old-trial"] {
        try FileManager.default.createDirectory(at: bottles.appendingPathComponent("Profiles/\(name)"), withIntermediateDirectories: true)
    }
    try Data().write(to: bottles.appendingPathComponent("Profiles/.DS_Store"))

    // A trailing slash or a dot segment in a stored path is still the same folder.
    let inUse: Set<String> = [manager.prefixPath(forProfile: "common") + "/", bottles.path + "/Profiles/./leaf"]
    #expect(manager.unusedPrefixes(inUse: inUse).map(\.lastPathComponent) == ["my-old-trial"])
    #expect(manager.unusedPrefixes(inUse: []).map(\.lastPathComponent) == ["common", "leaf", "my-old-trial"])
}
