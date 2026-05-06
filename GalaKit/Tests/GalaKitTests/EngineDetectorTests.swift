import Testing
import Foundation
@testable import GalaKit

@Test func detectKiriKiriByXP3() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    FileManager.default.createFile(atPath: dir.appendingPathComponent("data.xp3").path, contents: nil)
    FileManager.default.createFile(atPath: dir.appendingPathComponent("game.exe").path, contents: nil)
    let result = EngineDetector.detect(in: dir)
    #expect(result == .kirikiri)
}

@Test func detectRenPyByDirectory() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let renpyDir = dir.appendingPathComponent("renpy")
    try FileManager.default.createDirectory(at: renpyDir, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: dir.appendingPathComponent("game.exe").path, contents: nil)
    let result = EngineDetector.detect(in: dir)
    #expect(result == .renpy)
}

@Test func detectUnityByDLL() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    FileManager.default.createFile(atPath: dir.appendingPathComponent("UnityPlayer.dll").path, contents: nil)
    FileManager.default.createFile(atPath: dir.appendingPathComponent("game.exe").path, contents: nil)
    let result = EngineDetector.detect(in: dir)
    #expect(result == .unity)
}

@Test func detectRPGMakerByRGSSDLL() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    FileManager.default.createFile(atPath: dir.appendingPathComponent("RGSS301.dll").path, contents: nil)
    FileManager.default.createFile(atPath: dir.appendingPathComponent("Game.exe").path, contents: nil)
    let result = EngineDetector.detect(in: dir)
    #expect(result == .rpgMaker)
}

@Test func detectXP3ByMagicBytes() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let xp3Magic = Data([0x58, 0x50, 0x33, 0x0D, 0x0A, 0x1A, 0x08, 0x00])
    try xp3Magic.write(to: dir.appendingPathComponent("archive.dat"))
    FileManager.default.createFile(atPath: dir.appendingPathComponent("game.exe").path, contents: nil)
    let result = EngineDetector.detect(in: dir)
    #expect(result == .kirikiri)
}

@Test func detectUnknownForEmptyDir() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    FileManager.default.createFile(atPath: dir.appendingPathComponent("game.exe").path, contents: nil)
    let result = EngineDetector.detect(in: dir)
    #expect(result == nil)
}

@Test func detectLeafAQUAPLUSByWA2ExecutableAndMoviePacks() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    FileManager.default.createFile(atPath: dir.appendingPathComponent("WA2_chs.exe").path, contents: nil)
    FileManager.default.createFile(atPath: dir.appendingPathComponent("mv000.pak").path, contents: nil)
    FileManager.default.createFile(atPath: dir.appendingPathComponent("mv001.pak").path, contents: nil)

    let result = EngineDetector.detect(in: dir)
    #expect(result == .leaf)
}

@Test func detectIkuraGDLFamilyProjectByFamilyProjectFiles() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    FileManager.default.createFile(atPath: dir.appendingPathComponent("kzn_sc.exe").path, contents: nil)
    FileManager.default.createFile(atPath: dir.appendingPathComponent("KIZUNAR.SUF").path, contents: nil)
    FileManager.default.createFile(atPath: dir.appendingPathComponent("FAM_OP.MPG").path, contents: nil)

    let result = EngineDetector.detect(in: dir)
    #expect(result == .ikuraGDLFamilyProject)
}

@Test func resolvesBGIExecutable() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    FileManager.default.createFile(atPath: dir.appendingPathComponent("BGI.exe").path, contents: nil)
    FileManager.default.createFile(atPath: dir.appendingPathComponent("launcher.exe").path, contents: nil)

    let resolved = EngineDetector.resolveExecutable(engine: .bgi, in: dir)
    #expect(resolved?.lastPathComponent == "BGI.exe")
}

@Test func resolvesIkuraGDLFamilyProjectExecutable() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    FileManager.default.createFile(atPath: dir.appendingPathComponent("KIZUNAR.EXE").path, contents: nil)
    FileManager.default.createFile(atPath: dir.appendingPathComponent("kzn_sc.exe").path, contents: nil)

    let resolved = EngineDetector.resolveExecutable(engine: .ikuraGDLFamilyProject, in: dir)
    #expect(resolved?.lastPathComponent == "kzn_sc.exe")
}

@Test func resolvesReturnsNilForUnknownEngine() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    FileManager.default.createFile(atPath: dir.appendingPathComponent("game.exe").path, contents: nil)

    let resolved = EngineDetector.resolveExecutable(engine: .unknown, in: dir)
    #expect(resolved == nil)
}
