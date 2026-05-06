import Testing
import Foundation
@testable import GalaKit

@Test func engineAliasResolverMapsKnownVNDBEngineNames() {
    #expect(EngineAliasResolver.resolve(vndbEngineName: "BGI/Ethornell") == .bgi)
    #expect(EngineAliasResolver.resolve(vndbEngineName: "KiriKiri") == .kirikiri)
    #expect(EngineAliasResolver.resolve(vndbEngineName: "Artemis Engine") == .artemis)
    #expect(EngineAliasResolver.resolve(vndbEngineName: "Siglus Engine") == .siglusEngine)
}

@Test func engineAliasResolverDoesNotGeneralizeSpecialProfilesWithoutLocalSignature() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    #expect(EngineAliasResolver.resolve(vndbEngineName: "Ikura GDL", gameDirectory: dir) == nil)
    #expect(EngineAliasResolver.resolve(vndbEngineName: "AQUAPLUS Engine", gameDirectory: dir) == nil)
}

@Test func engineAliasResolverMapsSpecialProfilesWhenLocalSignatureMatches() throws {
    let familyDir = try makeFamilyProjectDirectory()
    defer { try? FileManager.default.removeItem(at: familyDir) }

    let wa2Dir = try makeWA2Directory()
    defer { try? FileManager.default.removeItem(at: wa2Dir) }

    #expect(EngineAliasResolver.resolve(vndbEngineName: "Ikura GDL", gameDirectory: familyDir) == .ikuraGDLFamilyProject)
    #expect(EngineAliasResolver.resolve(vndbEngineName: "AQUAPLUS Engine", gameDirectory: wa2Dir) == .leaf)
}

@Test func engineSelectionPolicyPrefersLocalDetectionOverVNDBEngine() throws {
    let releases = [
        VNDBRelease(id: "r1", title: "New Edition", engine: "Artemis Engine", platforms: ["win"], patch: false)
    ]

    let selected = EngineSelectionPolicy.select(
        localDetection: .bgi,
        vndbReleases: releases,
        gameDirectory: nil
    )

    #expect(selected == .bgi)
}

@Test func engineSelectionPolicyIgnoresPatchAndNonWindowsReleases() {
    let releases = [
        VNDBRelease(id: "r1", title: "PSV", engine: "HuneX", platforms: ["psv"], patch: false),
        VNDBRelease(id: "r2", title: "Patch", engine: "Artemis Engine", platforms: ["win"], patch: true),
        VNDBRelease(id: "r3", title: "Windows", engine: "BGI/Ethornell", platforms: ["win"], patch: false),
    ]

    let selected = EngineSelectionPolicy.select(
        localDetection: nil,
        vndbReleases: releases,
        gameDirectory: nil
    )

    #expect(selected == .bgi)
}

@Test func engineSelectionPolicyFallsBackToUnknownForUnsupportedOrMissingEngine() {
    let releases = [
        VNDBRelease(id: "r1", title: "Windows", engine: "Family Adv System", platforms: ["win"], patch: false)
    ]

    let selected = EngineSelectionPolicy.select(
        localDetection: nil,
        vndbReleases: releases,
        gameDirectory: nil
    )

    #expect(selected == .unknown)
}

private func makeFamilyProjectDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: dir.appendingPathComponent("kzn_sc.exe").path, contents: nil)
    FileManager.default.createFile(atPath: dir.appendingPathComponent("KIZUNAR.SUF").path, contents: nil)
    FileManager.default.createFile(atPath: dir.appendingPathComponent("FAM_OP.MPG").path, contents: nil)
    return dir
}

private func makeWA2Directory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: dir.appendingPathComponent("WA2.exe").path, contents: nil)
    FileManager.default.createFile(atPath: dir.appendingPathComponent("mv000.pak").path, contents: nil)
    return dir
}
