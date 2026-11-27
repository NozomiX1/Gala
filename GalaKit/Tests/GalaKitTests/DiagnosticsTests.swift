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
    #expect(WineLaunchConfig.buildEnvironment(game: game, wineBinary: wine)["WINEDEBUG"] == "fixme-all,+loaddll")
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
    #expect(report.runtimeProfile == "common")
    #expect(!report.isBottleReady)
    #expect(report.runtimeMarker == "missing")
    #expect(report.logExcerpt?.contains("X.dll") == true)

    let text = report.text
    #expect(!text.contains(home.path))
    #expect(text.contains("KiriKiri：45 分（xp3 archive）"))
    #expect(text.contains("quartz=builtin"))
    #expect(text.contains("Gala 2.0.0"))

    #expect(!report.isEngineFromVNDB)
    #expect(!report.looksPacked)

    let decoded = try JSONDecoder().decode(Diagnostics.self, from: JSONEncoder().encode(report))
    #expect(decoded == report)
}

@Test func diagnosticsSayWhenTheEngineWasNotFoundLocallyAndWhenTheLaunchFileLooksPacked() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("user-\(UUID().uuidString)")
    let gameDir = home.appendingPathComponent("Games/Sample")
    try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    let executable = gameDir.appendingPathComponent("game.exe")
    try writeExecutable(sections: ["        ", ".rsrc"], to: executable)

    // Nothing in the folder says KiriKiri: the label came from VNDB, as with the Whale original of ノラとと.
    let game = Game(title: "Sample", executablePath: executable.path, engine: .kirikiri)
    let report = Diagnostics.collect(
        game: game,
        appVersion: "2.0.1",
        wineManager: WineManager(baseURL: home.appendingPathComponent("GalaData")),
        home: home.path
    )

    #expect(report.isEngineFromVNDB)
    #expect(report.looksPacked)
    // The profile's own notes go along, so a known catch reaches whoever reads the report.
    #expect(report.profileNotes == ProfileStore.bundled.recipe(id: "common")?.notes)
    #expect(report.profileNotes.map { report.text.contains("【环境说明】\($0)") } == true)
    #expect(report.text.contains("取自 VNDB 的登记"))
    #expect(report.text.contains("像是加了保护壳"))
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

/// A PE header with the given section names and nothing else.
private func writeExecutable(sections: [String], to url: URL) throws {
    var data = Data(count: 0x80 + 24 + sections.count * 40)
    data[0] = 0x4D; data[1] = 0x5A
    data[0x3C] = 0x80
    data.replaceSubrange(0x80..<0x84, with: Data("PE\0\0".utf8))
    data[0x86] = UInt8(sections.count)
    for (index, name) in sections.enumerated() {
        let start = 0x80 + 24 + index * 40
        data.replaceSubrange(start..<start + name.utf8.count, with: Data(name.utf8))
    }
    try data.write(to: url)
}

@Test func aNamelessOrProtectorSectionMarksAnExecutableAsPacked() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let plain = dir.appendingPathComponent("plain.exe")
    try writeExecutable(sections: [".text", ".adata", ".rdata", ".rsrc"], to: plain)
    let nameless = dir.appendingPathComponent("nameless.exe")
    try writeExecutable(sections: ["        ", ".rsrc", "rkqjpsru"], to: nameless)
    let enigma = dir.appendingPathComponent("enigma.exe")
    try writeExecutable(sections: [".text", ".enigma1"], to: enigma)

    #expect(!EngineDetector.looksPacked(plain))
    #expect(EngineDetector.looksPacked(nameless))
    #expect(EngineDetector.looksPacked(enigma))
    #expect(!EngineDetector.looksPacked(dir.appendingPathComponent("missing.exe")))
}

private let d3d11Log = #"""
00d8:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\d3d11.dll" at 00006FFFF9E90000: builtin
00d8:trace:loaddll:build_module Loaded L"Z:\\Games\\名前 with space\\game.exe" at 0000000140000000: native
00d8:trace:loaddll:build_module Loaded L"C:\\windows\\syswow64\\quartz.dll" at 6FF10000: native
00d8:trace:loaddll:build_module Loaded L"C:\\windows\\syswow64\\LAVSplitter.ax" at 10000000: native
00d8:trace:loaddll:build_module Loaded L"C:\\windows\\syswow64\\wmp.dll" at 70000000: builtin
0024:err:module:import_dll Library X.dll not found
"""#

@Test func aLaunchLogSaysWhatTheGameUsedAndWhatToTry() {
    let observation = LaunchObservation(log: d3d11Log)
    #expect(observation.modules["quartz.dll"] == "native")
    #expect(observation.modules["game.exe"] == "native")
    #expect(observation.summary == "图形：D3D11 · 视频：DirectShow（Windows 原版）、LAV 解码器、Windows Media Player 控件（Wine 的空壳）")

    // Run with plain Wine: both findings come with something to try.
    let advice = observation.advice(usesDXMTWine: false, usesMediaFoundationRuntime: false)
    #expect(advice.count == 2)
    #expect(advice[0].contains("DXMT"))
    #expect(advice[1].contains("Windows Media Player"))
    // Already on the DXMT build: nothing left to suggest about graphics.
    #expect(observation.advice(usesDXMTWine: true, usesMediaFoundationRuntime: false).count == 1)

    #expect(LaunchObservation(log: "0024:err:module:import_dll Library X.dll not found").isEmpty)
    // The module list stays out of the excerpt and out of the quick-exit message.
    #expect(!LogExcerpt.make(d3d11Log).contains("loaddll"))
    #expect(LogExcerpt.make(d3d11Log).contains("X.dll"))
    #expect(WineLaunchDiagnostics.isHarmlessWineNoise(String(d3d11Log.split(separator: "\n")[0])))
}

@Test func adviceComesFromTheProfileAndFromTheLastLaunchAndReachesTheReport() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("user-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let wineManager = WineManager(baseURL: home.appendingPathComponent("GalaData"))
    let runtime = GameRuntime(wineManager: wineManager)
    let game = Game(title: "Summer Pockets", executablePath: home.appendingPathComponent("g/SiglusEngine.exe").path, engine: .siglusEngine)

    // Before any launch only the profile speaks.
    #expect(runtime.observation(for: game) == nil)
    #expect(runtime.advice(for: game).count == 1)
    #expect(runtime.advice(for: game)[0].contains("MCI"))

    try Data(d3d11Log.utf8).write(to: try LaunchLog.newURL(gameID: game.id, logsDirectory: wineManager.logsDirectory))
    #expect(runtime.advice(for: game).count == 3)

    let report = Diagnostics.collect(game: game, appVersion: "2.1.0", wineManager: wineManager, home: home.path)
    #expect(report.advice == runtime.advice(for: game))
    #expect(report.text.contains("【上次运行实际用到的】图形：D3D11"))
    #expect(report.text.contains("【建议】"))
    #expect(try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game)).acknowledgedAdvice.isEmpty)
}

@Test func direct2DOnD3D11DoesNotRecommendDXMTAndSuggestsDisablingDrawDeviceD2D() {
    let drawDeviceLog = #"""
    00e0:trace:loaddll:build_module Loaded L"Z:\\Games\\DC5\\plugin\\DrawDeviceD2Dv2.dll" at 777B0000: native
    00e0:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\D3D11.DLL" at 773D0000: builtin
    00e0:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\D2D1.DLL" at 76E90000: builtin
    """#
    let d2dPluginObs = LaunchObservation(log: drawDeviceLog)
    #expect(d2dPluginObs.usesD3D11)
    #expect(d2dPluginObs.usesD2D1)
    #expect(d2dPluginObs.direct2DDrawPlugin == "DrawDeviceD2Dv2")
    #expect(d2dPluginObs.summary == "图形：D3D11、Direct2D · 视频：这次运行没有用到")

    let plainItems = d2dPluginObs.adviceItems(usesDXMTWine: false, usesMediaFoundationRuntime: false)
    #expect(plainItems.count == 1)
    #expect(plainItems[0].message.contains("DrawDeviceD2Dv2=disabled"))
    #expect(!plainItems[0].message.contains("换成 DXMT"))
    #expect(plainItems[0].action == .init(dllOverrides: ["DrawDeviceD2Dv2": "disabled"]))

    let dxmtItems = d2dPluginObs.adviceItems(usesDXMTWine: true, usesMediaFoundationRuntime: false)
    #expect(dxmtItems.count == 1)
    #expect(dxmtItems[0].message.contains("DrawDeviceD2Dv2=disabled"))
    #expect(dxmtItems[0].message.contains("不兼容"))
    #expect(dxmtItems[0].action == .init(
        launchSwitches: [LaunchSwitch.graphics.id: "builtin"],
        dllOverrides: ["DrawDeviceD2Dv2": "disabled"]
    ))

    let genericD2DLog = #"""
    00e0:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\D3D11.DLL" at 773D0000: builtin
    00e0:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\D2D1.DLL" at 76E90000: builtin
    """#
    let genericObs = LaunchObservation(log: genericD2DLog)
    #expect(genericObs.direct2DDrawPlugin == nil)
    #expect(genericObs.adviceItems(usesDXMTWine: false, usesMediaFoundationRuntime: false).isEmpty)
    #expect(genericObs.adviceItems(usesDXMTWine: true, usesMediaFoundationRuntime: false).first?.action == .init(
        launchSwitches: [LaunchSwitch.graphics.id: "builtin"]
    ))

    let mfD3D11Log = #"""
    00e0:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\d3d11.dll" at 773D0000: builtin
    00e0:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\mf.dll" at 77DD0000: builtin
    00e0:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\wmp.dll" at 70000000: builtin
    """#
    let mfItems = LaunchObservation(log: mfD3D11Log).adviceItems(usesDXMTWine: false, usesMediaFoundationRuntime: false)
    #expect(mfItems.map(\.action) == [
        .init(launchSwitches: [LaunchSwitch.graphics.id: "dxmt"]),
        nil,
        .init(launchSwitches: [LaunchSwitch.mediaFoundation.id: "on"]),
    ])
    #expect(LaunchObservation(log: mfD3D11Log).adviceItems(usesDXMTWine: true, usesMediaFoundationRuntime: true).count == 1)
}

@Test func wmaPacketTooSmallAdviceRequiresWMADMODAndErrorText() {
    let wmaLog = #"""
    00e0:trace:loaddll:build_module Loaded L"C:\\windows\\syswow64\\wmadmod.dll" at 77000000: builtin
    00f0:err:gstreamer:gst_ffmpeg_log_callback [wmapro @ 0x1] Input packet too small (16384 < 20434)
    """#
    let obs = LaunchObservation(log: wmaLog)
    #expect(obs.hasWMAPacketTooSmallError)
    let items = obs.adviceItems(usesDXMTWine: false, usesMediaFoundationRuntime: true)
    #expect(items.count == 1)
    #expect(items[0].message.contains("wmadmod=disabled"))
    #expect(items[0].action == .init(dllOverrides: ["wmadmod": "disabled"]))

    let withoutWMADMOD = LaunchObservation(log: "00f0:err:gstreamer: Input packet too small (16384 < 20434)")
    #expect(!withoutWMADMOD.hasWMAPacketTooSmallError)
    #expect(withoutWMADMOD.adviceItems(usesDXMTWine: false, usesMediaFoundationRuntime: true).isEmpty)
}
