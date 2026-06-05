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

    #expect(marker.profile == .artemisD3D11)
    #expect(marker.configVersion == Engine.artemisD3D11.runtimeConfigVersion)
    #expect(marker.wineVersionName == WineManager.dxmtWineVersionName)
    #expect(marker.managedComponents == ["dxmt@v0.80"])
    #expect(marker.configuredAt == configuredAt)
    #expect(try bottleManager.runtimeMarkerStatus(for: game) == .current)
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

    #expect(marker.profile == .artemisMFD3D11)
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
        profile: .common,
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
