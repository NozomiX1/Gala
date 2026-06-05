import Testing
import Foundation
@testable import GalaKit

@Test func mediaOverlayReturnsOriginalGameForOtherProfiles() async throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let ffmpeg = try makeFakeFFmpeg(in: tempDir)
    let game = Game(
        title: "Hamidashi",
        executablePath: tempDir.appendingPathComponent("Hamidashi.exe").path,
        engine: .artemisD3D11
    )
    let manager = MediaCompatibilityManager(
        overlaysDirectory: tempDir.appendingPathComponent("Overlays"),
        ffmpegURL: ffmpeg
    )

    let launchGame = try await manager.prepareLaunchGame(for: game)

    #expect(launchGame.executablePath == game.executablePath)
}

@Test func mediaOverlayConvertsWMVAudioAndLaunchesFromOverlay() async throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let gameDir = tempDir.appendingPathComponent("Amakano3")
    let movieDir = gameDir.appendingPathComponent("movie")
    let saveDir = gameDir.appendingPathComponent("savedata_chs")
    try FileManager.default.createDirectory(at: movieDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)

    let exe = gameDir.appendingPathComponent("Amakano3_chs.exe")
    let pfs = gameDir.appendingPathComponent("Amakano3.pfs")
    let sourceMovie = movieDir.appendingPathComponent("op_chs.wmv")
    let sourceText = movieDir.appendingPathComponent("notes.txt")
    FileManager.default.createFile(atPath: exe.path, contents: Data("exe".utf8))
    FileManager.default.createFile(atPath: pfs.path, contents: Data("archive".utf8))
    FileManager.default.createFile(atPath: sourceMovie.path, contents: Data("original-wmv".utf8))
    FileManager.default.createFile(atPath: sourceText.path, contents: Data("text".utf8))

    let ffmpeg = try makeFakeFFmpeg(in: tempDir)
    let game = Game(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
        title: "Amakano 3",
        executablePath: exe.path,
        engine: .artemisMFD3D11
    )
    let manager = MediaCompatibilityManager(
        overlaysDirectory: tempDir.appendingPathComponent("Overlays"),
        ffmpegURL: ffmpeg
    )

    let launchGame = try await manager.prepareLaunchGame(for: game)

    let overlayDir = tempDir.appendingPathComponent("Overlays/00000000-0000-0000-0000-000000000123")
    #expect(launchGame.executablePath == overlayDir.appendingPathComponent("Amakano3_chs.exe").path)

    let overlayExeDestination = try FileManager.default.destinationOfSymbolicLink(
        atPath: overlayDir.appendingPathComponent("Amakano3_chs.exe").path
    )
    #expect(canonicalPath(overlayExeDestination) == canonicalPath(exe.path))

    let overlayArchiveDestination = try FileManager.default.destinationOfSymbolicLink(
        atPath: overlayDir.appendingPathComponent("Amakano3.pfs").path
    )
    #expect(canonicalPath(overlayArchiveDestination) == canonicalPath(pfs.path))

    let overlaySaveDestination = try FileManager.default.destinationOfSymbolicLink(
        atPath: overlayDir.appendingPathComponent("savedata_chs").path
    )
    #expect(canonicalPath(overlaySaveDestination) == canonicalPath(saveDir.path))

    let convertedMovie = overlayDir.appendingPathComponent("movie/op_chs.wmv")
    #expect(try String(contentsOf: convertedMovie) == "converted:\(sourceMovie.path)")

    let sourceTextDestination = try FileManager.default.destinationOfSymbolicLink(
        atPath: overlayDir.appendingPathComponent("movie/notes.txt").path
    )
    #expect(canonicalPath(sourceTextDestination) == canonicalPath(sourceText.path))
    #expect(try String(contentsOf: sourceMovie) == "original-wmv")
}

@Test func mediaOverlayReusesCurrentManifestWithoutReconversion() async throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let gameDir = tempDir.appendingPathComponent("Amakano3")
    let movieDir = gameDir.appendingPathComponent("movie")
    try FileManager.default.createDirectory(at: movieDir, withIntermediateDirectories: true)
    let exe = gameDir.appendingPathComponent("Amakano3_chs.exe")
    let sourceMovie = movieDir.appendingPathComponent("op_chs.wmv")
    FileManager.default.createFile(atPath: exe.path, contents: Data("exe".utf8))
    FileManager.default.createFile(atPath: sourceMovie.path, contents: Data("original-wmv".utf8))

    let ffmpeg = try makeFakeFFmpeg(in: tempDir)
    let game = Game(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000456")!,
        title: "Amakano 3",
        executablePath: exe.path,
        engine: .artemisMFD3D11
    )
    let manager = MediaCompatibilityManager(
        overlaysDirectory: tempDir.appendingPathComponent("Overlays"),
        ffmpegURL: ffmpeg
    )

    _ = try await manager.prepareLaunchGame(for: game)
    try Data("#!/bin/sh\nexit 42\n".utf8).write(to: ffmpeg)

    let launchGame = try await manager.prepareLaunchGame(for: game)

    #expect(launchGame.executablePath.hasSuffix("Amakano3_chs.exe"))
    let convertedMovie = tempDir
        .appendingPathComponent("Overlays/00000000-0000-0000-0000-000000000456/movie/op_chs.wmv")
    #expect(try String(contentsOf: convertedMovie) == "converted:\(sourceMovie.path)")
}

private func makeTempDir() throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    return tempDir
}

private func makeFakeFFmpeg(in tempDir: URL) throws -> URL {
    let ffmpeg = tempDir.appendingPathComponent("ffmpeg")
    let script = """
    #!/bin/sh
    input=""
    previous=""
    for arg in "$@"; do
      if [ "$previous" = "-i" ]; then
        input="$arg"
      fi
      previous="$arg"
      output="$arg"
    done
    printf "converted:%s" "$input" > "$output"
    """
    try Data(script.utf8).write(to: ffmpeg)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffmpeg.path)
    return ffmpeg
}

private func canonicalPath(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
}
