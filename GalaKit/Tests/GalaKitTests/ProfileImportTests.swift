import Testing
import Foundation
@testable import GalaKit

private func emptyUserDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func aProfilePastedFromAChatIsFoundCheckedAndGivenAnID() throws {
    let dir = try emptyUserDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let pasted = """
    可以试试这个：

    ```json
    {
      "name": "Summer Pockets 试验",
      "base": "siglus-engine",
      "components": ["wmp11"],
      "dllOverrides": { "wmvdecod": "native" },
      "notes": "花括号 } 在字符串里不算结束 {"
    }
    ```
    装好之后告诉我结果。
    """

    let imported = try ProfileImport.parse(pasted, userDirectory: dir)
    #expect(imported.file.id == "my-summer-pockets")
    #expect(imported.file.base == "siglus-engine")
    #expect(imported.replaces == nil)
    // It installs something, so it gets a prefix of its own, cloned from the one it is built on.
    #expect(imported.needsOwnPrefix)
    #expect(imported.recipe.cloneCandidates == ["siglus-engine", "common"])
    #expect(imported.recipe.preset.dllOverrides["quartz"] == "builtin")
    #expect(imported.recipe.isUserProvided)

    let url = try imported.save(to: dir)
    #expect(url.lastPathComponent == "my-summer-pockets.json")
    let store = ProfileStore.loading(userDirectory: dir)
    #expect(store.problems.isEmpty)
    #expect(store.store.recipe(id: "my-summer-pockets")?.name == "Summer Pockets 试验")

    // The same name again takes the next free id; the same id again is an update of the user's own.
    #expect(try ProfileImport.parse(pasted, userDirectory: dir).file.id == "my-summer-pockets-2")
    let update = try ProfileImport.parse(#"{"id":"my-summer-pockets","name":"第二版","base":"common","locale":"ja_JP.UTF-8"}"#, userDirectory: dir)
    #expect(update.replaces == "Summer Pockets 试验")
    #expect(!update.needsOwnPrefix)
    // Written over the file it replaces, not beside it.
    #expect(try update.save(to: dir).lastPathComponent == url.lastPathComponent)
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["my-summer-pockets.json"])
    #expect(ProfileStore.loading(userDirectory: dir).store.recipe(id: "my-summer-pockets")?.name == "第二版")
}

@Test func aPastedProfileIsRefusedWithTheReason() throws {
    let dir = try emptyUserDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    func failure(_ text: String) -> ProfileImportError? {
        do { _ = try ProfileImport.parse(text, userDirectory: dir); return nil } catch { return error as? ProfileImportError }
    }

    #expect(failure("把视频播放方式改成 Wine 自带") == .noJSON)
    #expect(failure(#"{"name":"x","dllOverride":{"quartz":"builtin"},"winver":"xp"}"#) == .unknownFields(["dllOverride", "winver"]))
    #expect(failure(#"{"base":"common"}"#) == .missingName)
    #expect(failure(#"{"id":"common","name":"我的通用"}"#) == .bundledID("common"))
    #expect(failure(#"{"id":"我的","name":"x"}"#) == .badID("我的"))
    #expect(failure(#"{"name":"x","base":"no-such"}"#) == .invalid(ProfileError.unknownBase(id: "my-profile", base: "no-such").localizedDescription))
    #expect(failure(#"{"name":"x","environment":{"WINEPREFIX":"/tmp/elsewhere"}}"#) == .invalid(ProfileError.reservedEnvironment(id: "my-profile", name: "WINEPREFIX").localizedDescription))
    #expect(failure(#"{"name":"x","components":"quartz"}"#) == .unreadable("components 的写法不对。"))
    #expect(failure(#"{"name":"x","registry":[{"key":"HKCU\\Software\\X","name":"a","data":"1"}]}"#) == .unreadable("registry → 第 1 项 里缺少 type。"))
    // Nothing was written by any of them.
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)

    // A name without Latin letters still gets a usable id.
    #expect(try ProfileImport.parse(#"{"name":"白色相簿 试验"}"#, userDirectory: dir).file.id == "my-profile")
}

@Test func aPastedProfileCanTakeAwayLaunchSettingsOfItsBase() throws {
    let dir = try emptyUserDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data(#"{"id":"first","name":"第一次","base":"siglus-engine","environment":{"A":"1","B":"2"},"launchArguments":["-windowed"]}"#.utf8)
        .write(to: dir.appendingPathComponent("first.json"))

    // One spelling is enough: siglus-engine sets both "quartz" and "*quartz", and both go.
    let pasted = #"{ "name": "第二次", "base": "first", "dllOverrides": { "quartz": null, "amstream": "native" }, "environment": { "A": null }, "launchArguments": [] }"#
    let imported = try ProfileImport.parse(pasted, userDirectory: dir)

    // Gone from what is passed at launch; the prefix's own setting for the DLL applies again.
    #expect(imported.recipe.preset.dllOverrides["quartz"] == nil)
    #expect(imported.recipe.preset.dllOverrides["*quartz"] == nil)
    #expect(imported.recipe.preset.dllOverrides["amstream"] == "native")
    #expect(imported.recipe.preset.dllOverrides["*amstream"] == "native")
    #expect(imported.recipe.environment == ["B": "2"])
    #expect(imported.recipe.launchArguments.isEmpty)
    // "first" is the user's own, so it was folded in: what the paste took away from it is simply not there any more.
    // Only the removal that reaches a bundled profile's setting is left as one.
    #expect(imported.absorbed.map(\.id) == ["first"])
    #expect(imported.file.environment == ["B": "2"])
    #expect(imported.file.launchArguments == nil)
    #expect(imported.removals == ["DLL 设置 quartz"])
    // Nothing of it goes into a prefix, so it runs in the one its base runs in.
    #expect(!imported.needsOwnPrefix)
    #expect(imported.recipe.bottleID == "siglus-engine")

    // The removals survive being saved and read back.
    try imported.save(to: dir)
    let reread = ProfileStore.loading(userDirectory: dir).store.recipe(id: imported.file.id)
    #expect(reread?.preset.dllOverrides["quartz"] == nil)
    #expect(reread?.environment == ["B": "2"])
}

@Test func whatAPastedProfileCopiesFromItsBaseIsLeftOut() throws {
    let dir = try emptyUserDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    // Everything siglus-engine already has, written out again, plus one real change and one removal.
    let pasted = """
    { "name": "抄了一遍", "base": "siglus-engine", "wine": "default",
      "components": ["quartz", "amstream", "lavfilters", "xact", "xinput", "vcrun2019", "d3dx9"],
      "dllOverrides": { "quartz": "builtin", "*quartz": "builtin", "amstream": "builtin", "xaudio2_7": null, "wmvdecod": "native" } }
    """
    let imported = try ProfileImport.parse(pasted, userDirectory: dir)

    #expect(imported.file.components == ["d3dx9"])
    #expect(imported.file.dllOverrides == ["xaudio2_7": nil, "wmvdecod": "native"])
    #expect(imported.file.wine == nil)
    #expect(imported.removals == ["DLL 设置 xaudio2_7"])
    // The result is the same as if it had all been kept.
    #expect(imported.recipe.preset.dllOverrides["quartz"] == "builtin")
    #expect(imported.recipe.preset.dllOverrides["xaudio2_7"] == nil)
    #expect(imported.recipe.preset.components.last == "d3dx9")

    // Removing something the base never had is no change either.
    #expect(try ProfileImport.parse(#"{"name":"x","base":"common","dllOverrides":{"nothing":null}}"#, userDirectory: dir).file.dllOverrides == nil)
}

@Test func aProfileWrittenOnAnEarlierImportIsSavedFlat() throws {
    let dir = try emptyUserDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let first = try ProfileImport.parse(#"{"name":"trial one","base":"siglus-engine","components":["d3dx9"],"dllOverrides":{"wmvdecod":"native"},"environment":{"A":"1"}}"#, userDirectory: dir)
    try first.save(to: dir)
    #expect(first.absorbed.isEmpty)

    // Written the way an assistant continues: on top of what it gave last time, only the change.
    let second = try ProfileImport.parse(#"{"name":"trial two","base":"my-trial-one","components":["xinput","wmp11"],"dllOverrides":{"wmvdecod":null,"quartz":"native"},"locale":"ja_JP.UTF-8"}"#, userDirectory: dir)

    #expect(second.absorbed.map(\.id) == ["my-trial-one"])
    #expect(second.file.base == "siglus-engine")
    // Both attempts' additions, without what siglus-engine installs anyway.
    #expect(second.file.components == ["d3dx9", "wmp11"])
    // The first attempt's override was taken back, so nothing of it is left to say; the change to quartz covers both spellings.
    #expect(second.file.dllOverrides == ["quartz": "native"])
    #expect(second.recipe.preset.dllOverrides["*quartz"] == "native")
    #expect(second.recipe.preset.dllOverrides["wmvdecod"] == nil)
    #expect(second.file.environment == ["A": "1"])
    #expect(second.file.locale == "ja_JP.UTF-8")
    #expect(second.recipe.cloneCandidates == ["siglus-engine", "common"])
    #expect(second.recipe.preset.components.suffix(2) == ["d3dx9", "wmp11"])

    // Saved, the second stands without the first.
    try second.save(to: dir)
    #expect(ProfileStore.userProfiles(basedOn: "my-trial-one", in: dir).isEmpty)
    try ProfileStore.deleteUserProfile(id: "my-trial-one", in: dir)
    let store = ProfileStore.loading(userDirectory: dir)
    #expect(store.problems.isEmpty)
    #expect(store.store.recipe(id: "my-trial-two")?.preset.components.suffix(2) == ["d3dx9", "wmp11"])
    #expect(store.store.recipe(id: "my-trial-one") == nil)

    // A bundled base is not folded, and a bundled profile cannot be deleted this way.
    try ProfileStore.deleteUserProfile(id: "common", in: dir)
    #expect(ProfileStore.loading(userDirectory: dir).store.recipe(id: "common") != nil)
}

// Both shapes came back from a real assistant given the help request.
@Test func aWholeChatReplyIsReadPastItsOtherBraces() throws {
    let dir = try emptyUserDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let profile = #"{ "name": "WA2 试验", "base": "leaf", "dllOverrides": { "wmvdecod": null } }"#

    // The prose quotes a GUID from the log, and an unfinished brace, before the profile.
    let quoted = "日志里的 `no class object {82d353df-90bd-4382-8bc2-3f6192b76e34}` 说明解码器没有加载，{ 之后：\n\(profile)"
    #expect(try ProfileImport.parse(quoted, userDirectory: dir).removals == ["DLL 设置 wmvdecod"])

    // The same profile twice is one profile; a first attempt next to its correction is not guessed between.
    #expect(try ProfileImport.parse("\(profile)\n再贴一次：\n\(profile)", userDirectory: dir).file.name == "WA2 试验")
    let corrected = #"{ "name": "漏了一项", "base": "leaf" }"# + "\n上面漏写了，请用这个：\n\(profile)"
    #expect(throws: ProfileImportError.several(2)) { try ProfileImport.parse(corrected, userDirectory: dir) }
    #expect(throws: ProfileImportError.self) { try ProfileImport.parse("只有 {82d353df-90bd} 没有环境", userDirectory: dir) }
}
