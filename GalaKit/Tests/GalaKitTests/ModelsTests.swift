import Testing
import Foundation
@testable import GalaKit

@Test func gameRoundTripsJSON() throws {
    let game = Game(
        title: "Fate/stay night",
        originalTitle: "Fate/stay night",
        executablePath: "/path/to/fate.exe"
    )
    let data = try JSONEncoder().encode(game)
    let decoded = try JSONDecoder().decode(Game.self, from: data)
    #expect(decoded.title == "Fate/stay night")
    #expect(decoded.originalTitle == "Fate/stay night")
    #expect(decoded.executablePath == "/path/to/fate.exe")
    #expect(decoded.totalPlayTime == 0)
    #expect(decoded.status == .backlog)
    #expect(decoded.engine == nil)
    #expect(decoded.bottleConfig.locale == "zh_CN.UTF-8")
}

@Test func engineHasPreset() {
    let preset = Engine.kirikiri.preset
    #expect(preset.components.contains("quartz"))
    #expect(preset.components.contains("lavfilters"))
    #expect(preset.dllOverrides["quartz"] == "native")
}

@Test func enginePresetForUnknownIsBaseOnly() {
    let preset = Engine.unknown.preset
    #expect(preset.components.isEmpty)
    #expect(preset.dllOverrides.isEmpty)
}

@Test func legacyVideoPresetCoversDirectShowBasedEngines() {
    let engines: [Engine] = [.artemis, .nscripter, .yuris, .realLive]

    for engine in engines {
        let preset = engine.preset
        #expect(preset.components.contains("quartz"))
        #expect(preset.components.contains("amstream"))
        #expect(preset.components.contains("lavfilters"))
        #expect(preset.dllOverrides.isEmpty)
        #expect(preset.registryValues.isEmpty)
    }
}

@Test func leafPresetInstallsLegacyVideoComponents() {
    let preset = Engine.leaf.preset
    #expect(preset.components.contains("quartz"))
    #expect(preset.components.contains("amstream"))
    #expect(preset.components.contains("lavfilters"))
    #expect(preset.dllOverrides["quartz"] == "builtin")
    #expect(preset.dllOverrides["amstream"] == "builtin")
    #expect(preset.dllOverrides["devenum"] == "builtin")
    #expect(preset.dllOverrides["*quartz"] == "builtin")
    #expect(preset.dllOverrides["*amstream"] == "builtin")
    #expect(preset.dllOverrides["*devenum"] == "builtin")
    #expect(preset.dllOverrides["wmvdecod"] == "disabled")
    #expect(preset.dllOverrides["wmadmod"] == "disabled")
    #expect(preset.dllOverrides["winegstreamer"] == "disabled")
}

@Test func leafPresetForcesLAVVideoToRGBOutput() {
    let lavOutputKey = "HKCU\\Software\\LAV\\Video\\Output"
    let preset = Engine.leaf.preset
    let values = Dictionary(uniqueKeysWithValues: preset.registryValues
        .filter { $0.key == lavOutputKey }
        .map { ($0.valueName, $0.data) })

    #expect(values["nv12"] == "0")
    #expect(values["yv12"] == "0")
    #expect(values["yuy2"] == "0")
    #expect(values["uyvy"] == "0")
    #expect(values["rgb24"] == "1")
    #expect(values["rgb32"] == "1")
    #expect(preset.registryValues.allSatisfy { $0.type == "REG_DWORD" })
}

@Test func bottleConfigDefaults() {
    let config = BottleConfig(prefixPath: "/tmp/test")
    #expect(config.locale == "zh_CN.UTF-8")
    #expect(config.windowsVersion == .win10)
    #expect(config.dllOverrides.isEmpty)
}
