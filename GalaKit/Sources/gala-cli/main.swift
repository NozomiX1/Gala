import Foundation
import GalaKit

// Command-line access to a Gala library, for diagnosing games without the app window.
// Ships inside Gala.app as Contents/MacOS/gala-cli; `swift run gala-cli` works during development.

let usage = """
用法：gala-cli <命令> [选项]

命令：
  list                 列出游戏库里的游戏
  diagnose <游戏>      输出一个游戏的诊断信息
  profiles             列出可用的运行环境，以及读取你自己的文件时遇到的问题
  use <游戏> <环境>    让这个游戏改用另一个运行环境并保存；写 default 回到引擎的默认环境
  configure <游戏>     创建运行环境并安装需要的组件
  launch <游戏>        启动游戏，等它退出，然后报告退出状态和日志位置
  guide                输出排查游戏无法运行时的指南
  compat               输出已验证游戏的列表（Markdown），用来更新 docs/compatibility.md

<游戏> 可以是标题的一部分，也可以是 list 显示的编号开头。
运行 use 和 configure 之前请先退出 Gala，两边同时写游戏库会互相覆盖。

选项：
  --json               用 JSON 输出（list、diagnose、profiles、launch）
  --home <目录>        使用这个数据目录，默认是 ~/Library/Application Support/Gala

只对这一次 configure 或 launch 生效、不会保存的选项：
  --profile <环境>     临时换用另一个运行环境
  --switch <开关=取值>  设置一个开关，例如 --switch video=builtin。可以写多次。开关的清单见 guide
  --dll <名字=模式>    追加一条 DLL 设置，例如 --dll quartz=builtin。可以写多次
  --env <名字=取值>    追加一个环境变量。可以写多次
  --locale <区域>      例如 ja_JP.UTF-8
  --no-debug           launch 默认记录 Wine 的报错和 DLL 加载情况，加上它就不记录
"""

let switchGuide = LaunchSwitch.all.map { item in
    let options = item.options.map { "\($0.id)（\($0.label)）" }.joined(separator: "、")
    return "  \(item.id)  \(item.name)：auto（自动）、\(options)。\(item.hint)"
}.joined(separator: "\n")

let guide = """
Gala 排查指南（给人和 AI 助手）

规则
  1. 不要修改、替换或删除游戏目录里的任何文件。
  2. Windows 组件只通过 Gala 的运行环境配置获取，不要从其他网站下载 DLL 放进去。
  3. 一次只改一处，改完启动一次，记下结果，再改下一处。

先做
  gala-cli list
  gala-cli diagnose <游戏>
  gala-cli launch <游戏>        启动一次，结束后再 diagnose 就能看到日志
  诊断信息里依次是：版本、识别出的引擎和依据、当前运行环境和设置、游戏目录的文件名、最近一次启动的日志。

按症状判断
  启动就退出、弹出报错    看日志里的 err: 行。提到找不到某个 DLL 时，多半是运行环境缺组件。
  有声音但画面全黑        图形渲染的问题，和视频播放无关。先试 --switch graphics=dxmt。
  片头或过场动画黑屏、被跳过  视频播放的问题，游戏本体通常还能运行。与 quartz、amstream、LAV 这几个组件用谁的实现有关。先试 --switch video=builtin 或 video=native。
  文字是方框              字体的问题。
  文字是乱码、或因此报错  区域的问题。日文原版游戏需要日文区域。

日志是空的或太少
  从 Gala 界面启动时只记录 Wine 的报错行。用 gala-cli launch 再运行一次，会多出 fixme 行和每个 DLL 的加载情况。

先试开关
  gala-cli launch <游戏> --switch video=builtin
\(switchGuide)
  开关只影响启动的这一次，不改动运行环境，换完直接启动就行。auto 表示跟随运行环境。
  在界面里，它们在游戏页面的"运行设置"里，选了就会保存。

再试别的改动
  gala-cli launch <游戏> --dll quartz=builtin
  gala-cli launch <游戏> --locale ja_JP.UTF-8
  gala-cli configure <游戏> --profile common ，然后 gala-cli launch <游戏> --profile common
  这些选项只对这一次生效，不会改动游戏库。启动时带上的 DLL 设置会盖过运行环境里原有的设置。
  先用这些选项把有效的组合试出来，再写成文件。

写一个自己的运行环境
  把一个 .json 文件放进数据目录下的 Profiles 文件夹（默认是 ~/Library/Application Support/Gala/Profiles）：
    { "id": "my-test", "name": "我的试验", "base": "common", "dllOverrides": { "quartz": "builtin" } }
  写了 base 就是继承它的全部，再加上或覆盖这里写的。可用的字段：
    启动时带上、不写进环境的：dllOverrides（值写 null 表示去掉继承来的那一条）、wine（default 或 dxmt）、
      environment（环境变量）、launchArguments（给游戏的启动参数）、locale（例如 ja_JP.UTF-8）。
    装进环境的：components（要装的 Windows 组件，winetricks 的名字）、registry（key、name、type、data）、registryDelete。
    只写了前一类的文件不建新环境，直接用 base 的；写了后一类的，会克隆 base 的环境再加上这些，通常十几秒。
    其余：notes、advice（需要用户自己动手的一件事，会显示在游戏页面和运行设置里）。
  gala-cli profiles              确认它被读到了，没有报错
  gala-cli use <游戏> my-test     让这个游戏用它
  gala-cli configure <游戏>       建好环境
  gala-cli launch <游戏>
  改了文件以后再运行一次 configure，Gala 会发现内容变了并重新应用。
  注意：重新应用只会添加和覆盖。从文件里删掉的 DLL 设置或注册表项，不会从已经建好的环境里消失；
  要彻底重来，先删掉 Bottles/Profiles/<id> 这个文件夹。

引擎识别错了
  看诊断信息里各候选的分数和依据。本地文件特征优先于 VNDB 的标注。
"""

struct Failure: Error { let message: String }

var arguments = Array(CommandLine.arguments.dropFirst())

func takeFlag(_ name: String) -> Bool {
    guard let index = arguments.firstIndex(of: name) else { return false }
    arguments.remove(at: index)
    return true
}

func takeValue(_ name: String) throws -> String? {
    guard let index = arguments.firstIndex(of: name) else { return nil }
    guard index + 1 < arguments.count else { throw Failure(message: "\(name) 后面需要一个值") }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...index + 1)
    return value
}

func takeValues(_ name: String) throws -> [String] {
    var values: [String] = []
    while let value = try takeValue(name) { values.append(value) }
    return values
}

func keyValue(_ text: String, flag: String) throws -> (String, String) {
    guard let equals = text.firstIndex(of: "="), equals != text.startIndex else {
        throw Failure(message: "\(flag) 要写成 名字=取值，收到的是「\(text)」")
    }
    return (String(text[..<equals]), String(text[text.index(after: equals)...]))
}

func note(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func printJSON(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}

func findGame(_ query: String, in games: [Game]) throws -> Game {
    let needle = query.lowercased()
    let matches = games.filter {
        $0.id.uuidString.lowercased().hasPrefix(needle) ||
            $0.title.lowercased().contains(needle) ||
            ($0.originalTitle?.lowercased().contains(needle) ?? false)
    }
    switch matches.count {
    case 1: return matches[0]
    case 0: throw Failure(message: "没有找到匹配「\(query)」的游戏。用 gala-cli list 查看全部。")
    default:
        let list = matches.map { "  \($0.id.uuidString.prefix(8))  \($0.title)" }.joined(separator: "\n")
        throw Failure(message: "「\(query)」匹配到多个游戏，请写得更具体：\n\(list)")
    }
}

struct LaunchResult: Encodable {
    let exitStatus: Int32
    let seconds: Double
    let logPath: String
}

/// Applies the one-off options to a copy of the game; nothing here is saved.
func applyOverrides(to game: inout Game, wineManager: WineManager) throws {
    if let id = try takeValue("--profile") {
        try requireProfile(id, in: wineManager)
        game.useProfile(id, bottlesDirectory: wineManager.bottlesDirectory, profiles: wineManager.profiles)
        // The saved flag describes the game's own runtime, not the one being tried.
        game.isRuntimeConfigured = true
    }
    for item in try takeValues("--dll") {
        let (name, mode) = try keyValue(item, flag: "--dll")
        game.bottleConfig.dllOverrides[name] = mode
    }
    for item in try takeValues("--switch") {
        let (name, option) = try keyValue(item, flag: "--switch")
        guard let known = LaunchSwitch.all.first(where: { $0.id == name }) else {
            throw Failure(message: "没有叫「\(name)」的开关。可用的有：\(LaunchSwitch.all.map(\.id).joined(separator: " "))")
        }
        guard option == "auto" || known.options.contains(where: { $0.id == option }) else {
            throw Failure(message: "开关 \(name) 的取值可以是：auto \(known.options.map(\.id).joined(separator: " "))")
        }
        game.launchSwitches[name] = option == "auto" ? nil : option
    }
    for item in try takeValues("--env") {
        let (name, value) = try keyValue(item, flag: "--env")
        game.bottleConfig.environment[name] = value
    }
    if let locale = try takeValue("--locale") {
        game.bottleConfig.locale = locale
        // Asked for by name, so it outranks a saved switch for this one run.
        game.launchSwitches[LaunchSwitch.locale.id] = nil
    }
}

/// The library as the app sees it: with the profile rules applied. Kept in memory unless the command saves; the app writes them the next time it starts.
func loadGames(_ home: URL) throws -> [Game] {
    RuntimeProfileMigration.migrate(
        games: try LibraryStore(baseURL: home).load(),
        bottlesDirectory: WineManager(baseURL: home).bottlesDirectory
    )
}

func requireProfile(_ id: String, in wineManager: WineManager) throws {
    guard wineManager.profiles.recipe(id: id) == nil else { return }
    let known = wineManager.profiles.recipes.map(\.id).joined(separator: " ")
    throw Failure(message: "没有叫「\(id)」的运行环境。可用的有：\(known)")
}

struct ProfileEntry: Encodable {
    let id: String
    let name: String
    let notes: String?
    let isUserProvided: Bool
    let verifiedGames: [String]
}

struct ListEntry: Encodable {
    let id: String
    let title: String
    let engine: String?
    let runtimeProfile: String?
    let isRuntimeConfigured: Bool
    let executablePath: String
}

@MainActor
func run() async throws {
    let json = takeFlag("--json")
    let home = try takeValue("--home").map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Gala")
    guard let command = arguments.first else { throw Failure(message: usage) }
    arguments.removeFirst()

    switch command {
    case "help", "--help", "-h":
        print(usage)
    case "guide":
        print(guide)
    case "list":
        let games = try loadGames(home)
        if json {
            try printJSON(games.map {
                ListEntry(
                    id: $0.id.uuidString,
                    title: $0.title,
                    engine: $0.engine?.displayName,
                    runtimeProfile: $0.engine?.runtimeProfile.rawValue,
                    isRuntimeConfigured: $0.isRuntimeConfigured,
                    executablePath: $0.executablePath
                )
            })
        } else if games.isEmpty {
            print("游戏库是空的：\(home.path)")
        } else {
            for game in games {
                let state = game.isRuntimeConfigured ? "已配置" : "未配置"
                print("\(game.id.uuidString.prefix(8))  \(game.title)  [\(game.engine?.displayName ?? "未识别") · \(state)]")
            }
        }
    case "diagnose":
        guard let query = arguments.first else { throw Failure(message: "diagnose 需要指定游戏。\n\n\(usage)") }
        let game = try findGame(query, in: try loadGames(home))
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版"
        let report = Diagnostics.collect(game: game, appVersion: appVersion, wineManager: WineManager(baseURL: home))
        if json { try printJSON(report) } else { print(report.text) }
    case "compat":
        print(ProfileStore.bundled.compatibilityMarkdown, terminator: "")
    case "profiles":
        let wineManager = WineManager(baseURL: home)
        let recipes = wineManager.profiles.recipes
        if json {
            try printJSON(recipes.map {
                ProfileEntry(id: $0.id, name: $0.name, notes: $0.notes, isUserProvided: $0.isUserProvided, verifiedGames: $0.verifiedGames)
            })
        } else {
            for recipe in recipes {
                print("\(recipe.id)  \(recipe.name)\(recipe.isUserProvided ? "  [我的]" : "")")
                if let notes = recipe.notes { print("    \(notes)") }
            }
        }
        for problem in wineManager.profileProblems {
            note("有问题的文件：\(problem.localizedDescription)")
        }
    case "use":
        guard arguments.count >= 2 else { throw Failure(message: "use 需要游戏和运行环境两个参数。\n\n\(usage)") }
        let store = LibraryStore(baseURL: home)
        var games = try loadGames(home)
        let game = try findGame(arguments[0], in: games)
        let wineManager = WineManager(baseURL: home)
        let id = arguments[1] == "default" ? nil : arguments[1]
        if let id { try requireProfile(id, in: wineManager) }
        guard let index = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[index].useProfile(id, bottlesDirectory: wineManager.bottlesDirectory, profiles: wineManager.profiles)
        try store.save(games)
        let now = wineManager.profiles.recipe(for: games[index])?.id ?? "无"
        print("\(game.title) 现在使用运行环境 \(now)。接下来运行：gala-cli configure \(arguments[0])")
    case "configure":
        guard let query = arguments.first else { throw Failure(message: "configure 需要指定游戏。\n\n\(usage)") }
        arguments.removeFirst()
        let store = LibraryStore(baseURL: home)
        var games = try loadGames(home)
        let saved = try findGame(query, in: games)
        let wineManager = WineManager(baseURL: home)
        var game = saved
        try applyOverrides(to: &game, wineManager: wineManager)

        try await GameRuntime(wineManager: wineManager).configure(game) { message, fraction in
            note(fraction.map { "\(message) \(Int($0 * 100))%" } ?? message)
        }
        if game.profileID == saved.profileID, let index = games.firstIndex(where: { $0.id == saved.id }) {
            games[index].isRuntimeConfigured = true
            try store.save(games)
        }
        print("运行环境已就绪：\(game.bottleConfig.prefixPath)")
    case "launch":
        guard let query = arguments.first else { throw Failure(message: "launch 需要指定游戏。\n\n\(usage)") }
        arguments.removeFirst()
        let debug = !takeFlag("--no-debug")
        let wineManager = WineManager(baseURL: home)
        var game = try findGame(query, in: try loadGames(home))
        try applyOverrides(to: &game, wineManager: wineManager)

        let runtime = GameRuntime(wineManager: wineManager)
        let wineBinary = try runtime.wineBinaryForLaunch(game)
        let launchGame = try await runtime.prepareMedia(for: game) { note($0.message) }
        let logFile = try LaunchLog.newURL(gameID: game.id, logsDirectory: wineManager.logsDirectory)
        let process = WineProcess()
        note("已启动，等待游戏退出...")
        let (seconds, status): (TimeInterval, Int32) = try await withCheckedThrowingContinuation { continuation in
            do {
                try process.launch(
                    game: launchGame,
                    wineBinary: wineBinary,
                    mediaFoundationRuntime: wineManager.mediaFoundationRuntime,
                    debug: debug,
                    logFile: logFile,
                    recipe: runtime.recipe(for: game)
                ) { duration, status, _ in
                    continuation.resume(returning: (duration, status))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
        if json {
            try printJSON(LaunchResult(exitStatus: status, seconds: seconds, logPath: logFile.path))
        } else {
            print("退出状态 \(status)，运行了 \(Int(seconds)) 秒。日志：\(logFile.path)")
        }
    default:
        throw Failure(message: "不认识的命令：\(command)\n\n\(usage)")
    }
}

do {
    try await run()
} catch let failure as Failure {
    FileHandle.standardError.write(Data((failure.message + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("出错了：\(error.localizedDescription)\n".utf8))
    exit(1)
}
