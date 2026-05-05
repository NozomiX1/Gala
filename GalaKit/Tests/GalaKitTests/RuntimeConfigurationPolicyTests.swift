import Testing
import Foundation
@testable import GalaKit

@Test func runtimePolicyDeletesLastConfiguredWineUser() {
    let prefix = "/tmp/Gala/Bottles/Profiles/kirikiri"
    let game = configuredGame(id: UUID(), title: "KiriKiri", engine: .kirikiri, prefix: prefix)

    #expect(RuntimeConfigurationPolicy.shouldDeleteRuntimeConfiguration(for: game, in: [game]))
}

@Test func runtimePolicyKeepsSharedConfiguredWinePrefix() {
    let prefix = "/tmp/Gala/Bottles/Profiles/legacy-video"
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
        prefix: "/tmp/Gala/Bottles/Profiles/base"
    )

    #expect(!RuntimeConfigurationPolicy.shouldDeleteRuntimeConfiguration(for: game, in: [game]))
}

@Test func runtimePolicyIgnoresEmptyPrefix() {
    let game = configuredGame(id: UUID(), title: "Empty", engine: .kirikiri, prefix: "")

    #expect(!RuntimeConfigurationPolicy.shouldDeleteRuntimeConfiguration(for: game, in: [game]))
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
