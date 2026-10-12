import Foundation
import GalaKit

// Command-line access to a Gala library, for diagnosing games without the app window.
// Ships inside Gala.app as Contents/MacOS/gala-cli; `swift run gala-cli` works during development.

let usage = """
用法：gala-cli <命令> [选项]

命令：
  list                 列出游戏库里的游戏
  diagnose <游戏>      输出一个游戏的诊断信息
  guide                输出排查游戏无法运行时的指南

<游戏> 可以是标题的一部分，也可以是 list 显示的编号开头。

选项：
  --json               用 JSON 输出（list、diagnose）
  --home <目录>        使用这个数据目录，默认是 ~/Library/Application Support/Gala
"""

let guide = """
Gala 排查指南（给人和 AI 助手）

规则
  1. 不要修改、替换或删除游戏目录里的任何文件。
  2. Windows 组件只通过 Gala 的运行环境配置获取，不要从其他网站下载 DLL 放进去。
  3. 一次只改一处，改完启动一次，记下结果，再改下一处。

先做
  gala-cli list
  gala-cli diagnose <游戏>
  诊断信息里依次是：版本、识别出的引擎和依据、当前运行环境和设置、游戏目录的文件名、最近一次启动的日志。

按症状判断
  启动就退出、弹出报错    看日志里的 err: 行。提到找不到某个 DLL 时，多半是运行环境缺组件。
  有声音但画面全黑        图形渲染的问题，和视频播放无关。较新的 Artemis 引擎游戏需要带 DXMT 的运行环境。
  片头或过场动画黑屏、被跳过  视频播放的问题，游戏本体通常还能运行。与 quartz、amstream、LAV 这几个组件用谁的实现有关。
  文字是方框              字体的问题。
  文字是乱码、或因此报错  区域的问题。日文原版游戏需要日文区域。

日志是空的
  普通启动不记录 Wine 的输出。让用户用调试启动再运行一次。

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

struct ListEntry: Encodable {
    let id: String
    let title: String
    let engine: String?
    let runtimeProfile: String?
    let isRuntimeConfigured: Bool
    let executablePath: String
}

func run() throws {
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
        let games = try LibraryStore(baseURL: home).load()
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
        let game = try findGame(query, in: try LibraryStore(baseURL: home).load())
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版"
        let report = Diagnostics.collect(game: game, appVersion: appVersion, wineManager: WineManager(baseURL: home))
        if json { try printJSON(report) } else { print(report.text) }
    default:
        throw Failure(message: "不认识的命令：\(command)\n\n\(usage)")
    }
}

do {
    try run()
} catch let failure as Failure {
    FileHandle.standardError.write(Data((failure.message + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("出错了：\(error.localizedDescription)\n".utf8))
    exit(1)
}
