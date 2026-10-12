import Testing
import Foundation
@testable import GalaKit

@Test func candidatesIncludeReasonsAndBelowThresholdMatches() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    FileManager.default.createFile(atPath: dir.appendingPathComponent("data.pfs").path, contents: nil)

    let candidates = EngineDetector.candidates(in: dir)

    // A lone .pfs archive is a hint, not enough to accept the engine.
    #expect(candidates == [EngineDetector.Candidate(engine: .artemisD3D11, score: 35, reasons: ["pfs archive"])])
    #expect(EngineDetector.detect(in: dir) == nil)
}

@Test func launchLogKeepsOnlyTheNewestFiles() throws {
    let logs = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: logs) }
    let id = UUID()

    var created: [URL] = []
    for second in 0..<5 {
        let url = try LaunchLog.newURL(gameID: id, logsDirectory: logs, now: Date(timeIntervalSince1970: Double(second)))
        try Data("run \(second)".utf8).write(to: url)
        created.append(url)
    }

    let remaining = try FileManager.default.contentsOfDirectory(atPath: LaunchLog.directory(gameID: id, logsDirectory: logs).path)
    #expect(remaining.count == LaunchLog.keepCount)
    #expect(LaunchLog.latest(gameID: id, logsDirectory: logs)?.lastPathComponent == created.last?.lastPathComponent)
    #expect(!FileManager.default.fileExists(atPath: created[0].path))
}

@Test func logExcerptKeepsShortLogsWhole() {
    #expect(LogExcerpt.make("a\n\nb\n") == "a\nb")
}

@Test func logExcerptKeepsEarlierErrorsAndTheTail() {
    let lines = ["0024:err:module:import_dll Library d3dx9_43.dll not found"] + (1...60).map { "line \($0)" }

    let excerpt = LogExcerpt.make(lines.joined(separator: "\n"), tailLines: 10, errorLines: 5)

    #expect(excerpt.contains("d3dx9_43.dll"))
    #expect(excerpt.contains("line 60"))
    #expect(excerpt.contains("line 51"))
    #expect(!excerpt.contains("line 50\n"))
    #expect(excerpt.contains("last 10 of 61 lines"))
}

@Test func debugLaunchTurnsWineLoggingOn() {
    let game = Game(title: "Test", executablePath: "/games/test/game.exe", bottleConfig: BottleConfig(prefixPath: "/tmp/prefix"))
    let wine = URL(fileURLWithPath: "/nonexistent/bin/wine")

    // Errors only: enough to explain a failed launch without the noise.
    #expect(WineLaunchConfig.buildEnvironment(game: game, wineBinary: wine)["WINEDEBUG"] == "fixme-all")
    #expect(WineLaunchConfig.buildEnvironment(game: game, wineBinary: wine, debug: true)["WINEDEBUG"] == "+loaddll")
}

@Test func diagnosticsReportDetectionFilesLogAndHidesTheHomeDirectory() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("user-\(UUID().uuidString)")
    let gameDir = home.appendingPathComponent("Games/Sample")
    let data = home.appendingPathComponent("GalaData")
    try FileManager.default.createDirectory(at: gameDir.appendingPathComponent("movie"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    FileManager.default.createFile(atPath: gameDir.appendingPathComponent("game.exe").path, contents: nil)
    FileManager.default.createFile(atPath: gameDir.appendingPathComponent("data.xp3").path, contents: nil)

    let wineManager = WineManager(baseURL: data)
    let game = Game(
        title: "Sample",
        executablePath: gameDir.appendingPathComponent("game.exe").path,
        engine: .kirikiri,
        isRuntimeConfigured: true,
        bottleConfig: BottleConfig(
            prefixPath: wineManager.bottlesDirectory.appendingPathComponent("Profiles/kirikiri").path,
            dllOverrides: ["quartz": "builtin"]
        )
    )
    let log = try LaunchLog.newURL(gameID: game.id, logsDirectory: wineManager.logsDirectory)
    try Data("0024:err:module:import_dll Library X.dll (needed by \(gameDir.path)\\game.exe) not found".utf8).write(to: log)

    let report = Diagnostics.collect(game: game, appVersion: "2.0.0", wineManager: wineManager, home: home.path)

    #expect(report.candidates.first == Diagnostics.Candidate(engine: "KiriKiri", score: 45, reasons: ["xp3 archive"]))
    #expect(report.files == ["data.xp3", "game.exe", "movie/"])
    #expect(report.executablePath == "~/Games/Sample/game.exe")
    #expect(report.runtimeProfile == "kirikiri")
    #expect(!report.isBottleReady)
    #expect(report.runtimeMarker == "missing")
    #expect(report.logExcerpt?.contains("X.dll") == true)

    let text = report.text
    #expect(!text.contains(home.path))
    #expect(text.contains("KiriKiri：45 分（xp3 archive）"))
    #expect(text.contains("quartz=builtin"))
    #expect(text.contains("Gala 2.0.0"))

    let decoded = try JSONDecoder().decode(Diagnostics.self, from: JSONEncoder().encode(report))
    #expect(decoded == report)
}

@Test func logExcerptDropsTheMapNoiseEveryLaunchPrints() {
    let noise = (1...50).map { "002c:err:virtual:try_map_free_area mmap() error Cannot allocate memory, range \($0)" }
    let excerpt = LogExcerpt.make((noise + ["0024:err:module:import_dll Library d3dx9_43.dll not found"]).joined(separator: "\n"))

    #expect(excerpt == "0024:err:module:import_dll Library d3dx9_43.dll not found")
}

@Test func helpRequestListsWhatCanBeChangedAndCarriesTheReport() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("gala-help-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let wineManager = WineManager(baseURL: home)
    let game = Game(title: "千恋＊万花", executablePath: home.appendingPathComponent("g/game.exe").path, engine: .kirikiri)
    let report = Diagnostics.collect(game: game, appVersion: "2.0.0", wineManager: wineManager, home: home.path)

    let text = report.helpRequest(profiles: wineManager.profiles.recipes)

    #expect(text.contains("通用（common）"))
    for item in LaunchSwitch.all {
        #expect(text.contains(item.name))
        #expect(text.contains(item.hint))
    }
    #expect(text.contains("设置名 → 选项"))
    #expect(text.hasSuffix(report.text))
    #expect(!text.contains(home.path))
}
