import Testing
import Foundation
@testable import GalaKit

// The bundled JSON profiles must describe exactly what the Swift presets did.
@Test(arguments: Engine.allCases)
func bundledProfileMatchesTheEnginePreset(engine: Engine) throws {
    let recipe = try #require(ProfileStore.bundled.recipe(id: engine.runtimeProfile.rawValue))

    #expect(recipe.preset == engine.preset)
    #expect(recipe.version == engine.runtimeConfigVersion)
    #expect(recipe.usesDXMTWine == engine.usesDXMTWineVariant)
}

private func file(_ id: String, base: String? = nil, version: Int? = nil, components: [String]? = nil,
                  managed: [String]? = nil, dll: [String: String?]? = nil) -> ProfileFile {
    ProfileFile(id: id, name: id, base: base, version: version, components: components, managedComponents: managed, dllOverrides: dll)
}

@Test func derivedProfileAddsOverridesAndRemovesWhatItNullsOut() throws {
    let store = try ProfileStore(files: [
        file("base", components: ["quartz"], dll: ["quartz": "native", "amstream": "native"]),
        file("child", base: "base", components: ["d3dx9", "quartz"], dll: ["quartz": "builtin", "amstream": String?.none]),
    ])
    let child = try #require(store.recipe(id: "child"))

    #expect(child.preset.components == ["quartz", "d3dx9"])
    #expect(child.preset.dllOverrides == ["quartz": "builtin"])
}

@Test func bumpingABaseVersionRaisesEveryProfileBuiltOnIt() throws {
    let before = try ProfileStore(files: [file("base"), file("child", base: "base", version: 3)])
    let after = try ProfileStore(files: [file("base", version: 2), file("child", base: "base", version: 3)])

    #expect(before.recipe(id: "child")?.version == 3)
    #expect(after.recipe(id: "child")?.version == 4)
}

@Test func fingerprintFollowsThePrefixContentsNotTheLabels() throws {
    let a = try #require(try ProfileStore(files: [file("a", dll: ["quartz": "native"])]).recipe(id: "a"))
    let renamed = try #require(try ProfileStore(files: [ProfileFile(id: "b", name: "别的名字", notes: "说明", dllOverrides: ["quartz": "native"])]).recipe(id: "b"))
    let changed = try #require(try ProfileStore(files: [file("a", dll: ["quartz": "builtin"])]).recipe(id: "a"))

    #expect(a.fingerprint == renamed.fingerprint)
    #expect(a.fingerprint != changed.fingerprint)
}

@Test func brokenProfileSetsAreRejectedWithTheReason() {
    #expect(throws: ProfileError.duplicate(id: "a")) { try ProfileStore(files: [file("a"), file("a")]) }
    #expect(throws: ProfileError.unknownBase(id: "a", base: "missing")) { try ProfileStore(files: [file("a", base: "missing")]) }
    #expect(throws: ProfileError.cycle(id: "a")) { try ProfileStore(files: [file("a", base: "b"), file("b", base: "a")]) }
    #expect(throws: ProfileError.unknownManagedComponent(id: "a", component: "nope")) { try ProfileStore(files: [file("a", managed: ["nope"])]) }
}

@Test func nullInAProfileFileDecodesAsARemoval() throws {
    let json = #"{"id":"x","name":"x","base":"common","dllOverrides":{"amstream":null,"quartz":"builtin"}}"#
    let decoded = try JSONDecoder().decode(ProfileFile.self, from: Data(json.utf8))

    #expect(decoded.dllOverrides?["quartz"] == .some("builtin"))
    #expect(decoded.dllOverrides?["amstream"] == .some(nil))
}
