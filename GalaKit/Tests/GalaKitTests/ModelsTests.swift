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
    #expect(decoded.isRuntimeConfigured == false)
}

@Test func gameRuntimeConfiguredRoundTripsJSON() throws {
    let game = Game(
        title: "Configured Game",
        executablePath: "/path/to/game.exe",
        isRuntimeConfigured: true,
        bottleConfig: BottleConfig(prefixPath: "/tmp/Gala/Bottles/Profiles/kirikiri")
    )

    let data = try JSONEncoder().encode(game)
    let decoded = try JSONDecoder().decode(Game.self, from: data)

    #expect(decoded.isRuntimeConfigured == true)
    #expect(decoded.bottleConfig.prefixPath == "/tmp/Gala/Bottles/Profiles/kirikiri")
}

@Test func gameDecodesLegacyRuntimeAsConfiguredWhenPrefixExists() throws {
    let json = """
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "title": "Legacy Game",
      "executablePath": "/path/to/game.exe",
      "bottleConfig": {
        "prefixPath": "/tmp/Gala/Bottles/Profiles/kirikiri",
        "windowsVersion": "win10",
        "dllOverrides": {},
        "environment": {},
        "launchArguments": [],
        "locale": "zh_CN.UTF-8",
        "winetricksComponents": []
      }
    }
    """

    let decoded = try JSONDecoder().decode(Game.self, from: Data(json.utf8))

    #expect(decoded.isRuntimeConfigured == true)
}

@Test func gameDecodesLegacyRuntimeAsUnconfiguredWhenPrefixIsEmpty() throws {
    let json = """
    {
      "id": "00000000-0000-0000-0000-000000000002",
      "title": "Unconfigured Legacy Game",
      "executablePath": "/path/to/game.exe",
      "bottleConfig": {
        "prefixPath": "",
        "windowsVersion": "win10",
        "dllOverrides": {},
        "environment": {},
        "launchArguments": [],
        "locale": "zh_CN.UTF-8",
        "winetricksComponents": []
      }
    }
    """

    let decoded = try JSONDecoder().decode(Game.self, from: Data(json.utf8))

    #expect(decoded.isRuntimeConfigured == false)
}

@Test func engineDecodesLegacyDOKizunarRawValueAsIkuraGDLFamilyProject() throws {
    let decoded = try JSONDecoder().decode(Engine.self, from: Data(#""doKizunar""#.utf8))

    #expect(decoded == .ikuraGDLFamilyProject)
}

@Test func engineHasPreset() {
    let preset = Engine.kirikiri.preset
    #expect(preset.components.contains("quartz"))
    #expect(preset.components.contains("lavfilters"))
    #expect(preset.dllOverrides["quartz"] == "native")
}

@Test func commonPresetCoversUnknownAndUnderdetectedLegacyEngines() {
    let engines: [Engine] = [.unknown, .majiro, .advHD, .qlie]

    for engine in engines {
        let preset = engine.preset
        #expect(engine.runtimeProfile.rawValue == "common")
        #expect(preset.components.contains("quartz"))
        #expect(preset.components.contains("amstream"))
        #expect(preset.components.contains("lavfilters"))
        #expect(preset.dllOverrides["quartz"] == "native,builtin")
        #expect(preset.dllOverrides["*quartz"] == "native,builtin")
        #expect(preset.dllOverrides["amstream"] == "native,builtin")
        #expect(preset.dllOverrides["*amstream"] == "native,builtin")
    }
}

@Test func commonPresetEnablesLAVWMAAudioFormats() {
    let lavAudioFormatsKey = "HKCU\\Software\\LAV\\Audio\\Formats"
    let preset = Engine.unknown.preset
    let values = Dictionary(uniqueKeysWithValues: preset.registryValues
        .filter { $0.key == lavAudioFormatsKey }
        .map { ($0.valueName, $0.data) })

    #expect(values["wma"] == "1")
    #expect(values["wmapro"] == "1")
    #expect(values["wmalossless"] == "1")
}

@Test func commonPresetCoversDirectShowBasedEngines() {
    let engines: [Engine] = [.bgi, .artemis, .nscripter, .yuris, .realLive]

    for engine in engines {
        let preset = engine.preset
        #expect(engine.runtimeProfile.rawValue == "common")
        #expect(preset.components.contains("quartz"))
        #expect(preset.components.contains("amstream"))
        #expect(preset.components.contains("lavfilters"))
        #expect(preset.dllOverrides["quartz"] == "native,builtin")
        #expect(preset.dllOverrides["*quartz"] == "native,builtin")
        #expect(preset.dllOverrides["amstream"] == "native,builtin")
        #expect(preset.dllOverrides["*amstream"] == "native,builtin")
    }
}

@Test func artemisD3D11PresetUsesDedicatedDXMTProfile() {
    let preset = Engine.artemisD3D11.preset

    #expect(Engine.artemisD3D11.displayName == "Artemis Engine (D3D11)")
    #expect(Engine.artemisD3D11.runtimeProfile.rawValue == "artemis-d3d11")
    #expect(preset.components == ["d3dcompiler_47"])
    #expect(preset.managedComponents == [.dxmt])
    #expect(preset.dllOverrides["d3dcompiler_47"] == "native,builtin")
    #expect(preset.dllOverrides["d3d11"] == nil)
    #expect(preset.dllOverrides["dxgi"] == nil)
}

@Test func ikuraGDLFamilyProjectPresetUsesSeparateBuiltinQuartzProfile() {
    let preset = Engine.ikuraGDLFamilyProject.preset

    #expect(Engine.ikuraGDLFamilyProject.displayName == "Ikura GDL / Family Project")
    #expect(Engine.ikuraGDLFamilyProject.runtimeProfile.rawValue == "do-kizunar")
    #expect(preset.components.contains("quartz"))
    #expect(preset.components.contains("amstream"))
    #expect(preset.components.contains("lavfilters"))
    #expect(preset.dllOverrides["quartz"] == "builtin")
    #expect(preset.dllOverrides["*quartz"] == "builtin")
    #expect(preset.dllOverrides["amstream"] == nil)
    #expect(preset.dllOverrides["wmvdecod"] == nil)
    #expect(preset.dllOverrides["wmadmod"] == nil)
    #expect(preset.dllOverrides["winegstreamer"] == nil)
}

@Test func ikuraGDLFamilyProjectRegistryValuesUseMappedGameDrive() {
    let game = Game(
        title: "Family Project",
        executablePath: "/Games/Kizunar/kzn_sc.exe",
        engine: .ikuraGDLFamilyProject,
        bottleConfig: BottleConfig(prefixPath: "/tmp/Gala/Bottles/Profiles/do-kizunar")
    )

    let values = Dictionary(uniqueKeysWithValues: Engine.ikuraGDLFamilyProject.gameSpecificRegistryValues(for: game)
        .map { ($0.valueName, $0.data) })

    #expect(values["InstallDir"] == "G:\\")
    #expect(values["SaveDir"] == "G:\\")
    #expect(values["DataDir"] == "G:\\")
    #expect(values["MusicDir"] == "G:\\")
    #expect(values["VoiceDir"] == "G:\\")
    #expect(values["VideoDir"] == "G:\\")
    #expect(values["InstallType"] == "2")
}

@Test func leafPresetInstallsCommonVideoComponents() {
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

@Test func specializedPresetsIncludeCommonVideoComponents() {
    let engines: [Engine] = [.kirikiri, .catSystem2, .siglusEngine, .leaf]

    for engine in engines {
        let preset = engine.preset
        #expect(preset.components.contains("quartz"))
        #expect(preset.components.contains("amstream"))
        #expect(preset.components.contains("lavfilters"))
    }
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

@Test func leafPresetEnablesLAVWMAAudioFormats() {
    let lavAudioFormatsKey = "HKCU\\Software\\LAV\\Audio\\Formats"
    let preset = Engine.leaf.preset
    let values = Dictionary(uniqueKeysWithValues: preset.registryValues
        .filter { $0.key == lavAudioFormatsKey }
        .map { ($0.valueName, $0.data) })

    #expect(values["wma"] == "1")
    #expect(values["wmapro"] == "1")
    #expect(values["wmalossless"] == "1")
}

@Test func bottleConfigDefaults() {
    let config = BottleConfig(prefixPath: "/tmp/test")
    #expect(config.locale == "zh_CN.UTF-8")
    #expect(config.windowsVersion == .win10)
    #expect(config.dllOverrides.isEmpty)
}
