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
    #expect(decoded.bottleConfig.locale == "ja_JP.UTF-8")
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

@Test func bottleConfigDefaults() {
    let config = BottleConfig(prefixPath: "/tmp/test")
    #expect(config.locale == "ja_JP.UTF-8")
    #expect(config.windowsVersion == .win10)
    #expect(config.dllOverrides.isEmpty)
}
