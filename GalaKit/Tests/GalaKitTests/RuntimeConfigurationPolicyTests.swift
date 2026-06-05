import Testing
import Foundation
@testable import GalaKit

@Test func runtimePolicyDeletesLastConfiguredWineUser() {
    let prefix = "/tmp/Gala/Bottles/Profiles/kirikiri"
    let game = configuredGame(id: UUID(), title: "KiriKiri", engine: .kirikiri, prefix: prefix)

    #expect(RuntimeConfigurationPolicy.shouldDeleteRuntimeConfiguration(for: game, in: [game]))
}

@Test func runtimePolicyKeepsSharedConfiguredWinePrefix() {
    let prefix = "/tmp/Gala/Bottles/Profiles/common"
    let game = configuredGame(id: UUID(), title: "BGI", engine: .bgi, prefix: prefix)
    let other = configuredGame(id: UUID(), title: "Artemis", engine: .artemis, prefix: prefix)

    #expect(!RuntimeConfigurationPolicy.shouldDeleteRuntimeConfiguration(for: game, in: [game, other]))
}

@Test func runtimePolicyIgnoresUnconfiguredGame() {
    let game = Game(
        title: "Unconfigured",
        executablePath: "/game.exe",
        engine: .kirikiri,
        isRuntimeConfigured: false,
        bottleConfig: BottleConfig(prefixPath: "/tmp/Gala/Bottles/Profiles/kirikiri")
    )

    #expect(!RuntimeConfigurationPolicy.shouldDeleteRuntimeConfiguration(for: game, in: [game]))
}

@Test func runtimePolicyIgnoresNativeEngine() {
    let game = configuredGame(
        id: UUID(),
        title: "RenPy",
        engine: .renpy,
        prefix: "/tmp/Gala/Bottles/Profiles/common"
    )

    #expect(!RuntimeConfigurationPolicy.shouldDeleteRuntimeConfiguration(for: game, in: [game]))
}

@Test func runtimePolicyIgnoresEmptyPrefix() {
    let game = configuredGame(id: UUID(), title: "Empty", engine: .kirikiri, prefix: "")

    #expect(!RuntimeConfigurationPolicy.shouldDeleteRuntimeConfiguration(for: game, in: [game]))
}

@Test func runtimePolicySkipsConfigurationWhenBottleIsAlreadyReady() {
    let game = Game(
        title: "Shared Prefix Game",
        executablePath: "/game.exe",
        engine: .bgi,
        isRuntimeConfigured: false,
        bottleConfig: BottleConfig(prefixPath: "/tmp/Gala/Bottles/Profiles/common")
    )

    #expect(!RuntimeConfigurationPolicy.needsRuntimeConfiguration(for: game, bottleReady: true))
}

@Test func runtimePolicyNeedsConfigurationWhenBottleIsMissing() {
    let game = Game(
        title: "New Prefix Game",
        executablePath: "/game.exe",
        engine: .bgi,
        isRuntimeConfigured: false,
        bottleConfig: BottleConfig(prefixPath: "/tmp/Gala/Bottles/Profiles/common")
    )

    #expect(RuntimeConfigurationPolicy.needsRuntimeConfiguration(for: game, bottleReady: false))
}

@Test func runtimePolicySkipsConfigurationForNativeEngine() {
    let game = Game(
        title: "Native Game",
        executablePath: "/game.exe",
        engine: .renpy,
        isRuntimeConfigured: false,
        bottleConfig: BottleConfig(prefixPath: "")
    )

    #expect(!RuntimeConfigurationPolicy.needsRuntimeConfiguration(for: game, bottleReady: false))
}

@Test func runtimePolicySkipsPresetForUnconfiguredGameWhenSharedProfileMarkerIsCurrent() {
    let game = Game(
        title: "Shared Artemis Game",
        executablePath: "/game.exe",
        engine: .artemisD3D11,
        isRuntimeConfigured: false,
        bottleConfig: BottleConfig(prefixPath: "/tmp/Gala/Bottles/Profiles/artemis-d3d11")
    )

    #expect(!RuntimeConfigurationPolicy.needsEnginePreset(
        for: game,
        bottleReady: true,
        runtimeMarkerStatus: .current,
        managedRuntimeReady: true
    ))
}

@Test func runtimePolicyReappliesPresetForOutdatedSharedProfileMarker() {
    let game = configuredGame(
        id: UUID(),
        title: "Configured Artemis Game",
        engine: .artemisD3D11,
        prefix: "/tmp/Gala/Bottles/Profiles/artemis-d3d11"
    )

    #expect(RuntimeConfigurationPolicy.needsEnginePreset(
        for: game,
        bottleReady: true,
        runtimeMarkerStatus: .outdated,
        managedRuntimeReady: true
    ))
}

@Test func runtimePolicyKeepsLegacyMarkerlessConfiguredBottle() {
    let game = configuredGame(
        id: UUID(),
        title: "Legacy Configured Game",
        engine: .bgi,
        prefix: "/tmp/Gala/Bottles/Profiles/common"
    )

    #expect(!RuntimeConfigurationPolicy.needsEnginePreset(
        for: game,
        bottleReady: true,
        runtimeMarkerStatus: .missing,
        managedRuntimeReady: true
    ))
}

@Test func runtimePolicyReappliesPresetWhenManagedRuntimeIsMissing() {
    let game = configuredGame(
        id: UUID(),
        title: "Configured Artemis Game",
        engine: .artemisD3D11,
        prefix: "/tmp/Gala/Bottles/Profiles/artemis-d3d11"
    )

    #expect(RuntimeConfigurationPolicy.needsEnginePreset(
        for: game,
        bottleReady: true,
        runtimeMarkerStatus: .current,
        managedRuntimeReady: false
    ))
}

private func configuredGame(id: UUID, title: String, engine: Engine, prefix: String) -> Game {
    Game(
        id: id,
        title: title,
        executablePath: "/game.exe",
        engine: engine,
        isRuntimeConfigured: true,
        bottleConfig: BottleConfig(prefixPath: prefix)
    )
}
