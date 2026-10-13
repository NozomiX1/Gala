import Foundation

/// Everything needed to judge why a game does not run, without having the game.
public struct Diagnostics: Codable, Equatable, Sendable {
    public struct Candidate: Codable, Equatable, Sendable {
        public var engine: String
        public var score: Int
        public var reasons: [String]
    }

    public var appVersion: String
    public var system: String
    public var wineVersion: String
    public var title: String
    public var executablePath: String
    public var engine: String?
    /// True when nothing in the game folder identifies the engine, so the stored one came from VNDB's release list.
    public var isEngineFromVNDB: Bool
    /// True when the launch file's section table looks like a protector's. A hint for reading a crash, never a reason to refuse a launch.
    public var looksPacked: Bool
    public var runtimeProfile: String?
    public var isProfileChosenByHand: Bool
    public var profileProblems: [String]
    public var prefixPath: String
    public var isRuntimeConfigured: Bool
    public var isBottleReady: Bool
    public var runtimeMarker: String
    public var locale: String
    public var launchSwitches: [String: String]
    public var dllOverrides: [String: String]
    public var environment: [String: String]
    public var launchArguments: [String]
    public var detectionThreshold: Int
    public var candidates: [Candidate]
    public var files: [String]
    public var fileCount: Int
    public var logPath: String?
    public var logExcerpt: String?

    static let fileLimit = 200

    /// Gathers the report for one game. Paths under `home` are shortened to `~` so the user name does not leak.
    public static func collect(
        game: Game,
        appVersion: String,
        wineManager: WineManager,
        home: String = NSHomeDirectory()
    ) -> Diagnostics {
        let scrub: (String) -> String = { $0.replacingOccurrences(of: home, with: "~") }
        let gameDirectory = URL(fileURLWithPath: game.executablePath).deletingLastPathComponent()
        let bottleManager = BottleManager(bottlesDirectory: wineManager.bottlesDirectory, wineManager: wineManager)
        let recipe = wineManager.profiles.recipe(for: game)
        let usesDXMT = wineManager.usesDXMTWine(for: game)

        let entries = (try? FileManager.default.contentsOfDirectory(
            at: gameDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        let names = entries
            .map { $0.lastPathComponent + ($0.hasDirectoryPath ? "/" : "") }
            .sorted()

        let marker: String
        switch try? bottleManager.runtimeMarkerStatus(for: game) {
        case .current: marker = "current"
        case .outdated: marker = "outdated"
        case .missing: marker = "missing"
        case nil: marker = "unreadable"
        }

        let logURL = LaunchLog.latest(gameID: game.id, logsDirectory: wineManager.logsDirectory)
        let log = logURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }

        return Diagnostics(
            appVersion: appVersion,
            system: systemDescription(),
            wineVersion: usesDXMT ? WineManager.dxmtWineVersionName : WineManager.wineVersionName,
            title: game.title,
            executablePath: scrub(game.executablePath),
            engine: game.engine?.displayName,
            isEngineFromVNDB: game.engine != nil && game.engine != .unknown && EngineDetector.detect(in: gameDirectory) == nil,
            looksPacked: EngineDetector.looksPacked(URL(fileURLWithPath: game.executablePath)),
            runtimeProfile: recipe?.id,
            isProfileChosenByHand: game.profileID != nil && recipe?.id == game.profileID,
            profileProblems: wineManager.profileProblems.map(\.localizedDescription)
                + (game.profileID != nil && recipe?.id != game.profileID ? ["这个游戏选的运行环境 \(game.profileID!) 已经不存在，改用了引擎的默认环境。"] : []),
            prefixPath: scrub(game.bottleConfig.prefixPath),
            isRuntimeConfigured: game.isRuntimeConfigured,
            isBottleReady: bottleManager.isBottleReady(for: game),
            runtimeMarker: marker,
            locale: game.bottleConfig.locale,
            launchSwitches: game.launchSwitches,
            dllOverrides: game.bottleConfig.dllOverrides,
            environment: game.bottleConfig.environment.mapValues(scrub),
            launchArguments: game.bottleConfig.launchArguments.map(scrub),
            detectionThreshold: EngineDetector.detectionThreshold,
            candidates: EngineDetector.candidates(in: gameDirectory).map {
                Candidate(engine: $0.engine.displayName, score: $0.score, reasons: $0.reasons)
            },
            files: Array(names.prefix(fileLimit)),
            fileCount: names.count,
            logPath: logURL.map { scrub($0.path) },
            logExcerpt: log.map { scrub(LogExcerpt.make($0)) }
        )
    }

    /// The report as text for an issue or a chat message.
    public var text: String {
        func pairs(_ dictionary: [String: String]) -> String {
            dictionary.isEmpty ? "无" : dictionary.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        }

        var lines = [
            "【游戏】\(title)",
            "【启动文件】\(executablePath)" + (looksPacked ? "\n  这个 exe 像是加了保护壳。加壳的程序有的能正常运行，有的一启动就崩溃；崩溃地址不属于任何模块时先怀疑它。" : ""),
            "【版本】Gala \(appVersion) · \(system) · \(wineVersion)",
            "【引擎】\(engine ?? "未识别")" + (isEngineFromVNDB ? "（游戏目录里没有认出来，取自 VNDB 的登记，可能是这部作品的另一个版本）" : ""),
            "【运行环境】\(runtimeProfile ?? "无")\(isProfileChosenByHand ? "（手动选择）" : "") · \(prefixPath.isEmpty ? "未指定位置" : prefixPath)",
            "【环境状态】已配置=\(isRuntimeConfigured ? "是" : "否") · bottle 就绪=\(isBottleReady ? "是" : "否") · 配置标记=\(runtimeMarker)",
            "【区域】\(locale)",
            "【开关】\(pairs(launchSwitches))",
            "【DLL 设置】\(pairs(dllOverrides))",
            "【环境变量】\(pairs(environment))",
            "【启动参数】\(launchArguments.isEmpty ? "无" : launchArguments.joined(separator: " "))",
            "",
            "【引擎识别】达到 \(detectionThreshold) 分才会被采纳",
        ]
        lines += candidates.isEmpty
            ? ["  没有匹配到任何已知特征"]
            : candidates.map { "  \($0.engine)：\($0.score) 分（\($0.reasons.joined(separator: "；"))）" }
        if !profileProblems.isEmpty {
            lines += ["", "【运行环境文件的问题】"] + profileProblems.map { "  \($0)" }
        }
        lines += ["", "【游戏目录】共 \(fileCount) 项" + (fileCount > files.count ? "，只列出前 \(files.count) 项" : "")]
        lines += files.map { "  \($0)" }
        lines += ["", "【最近一次启动的日志】\(logPath ?? "没有日志")"]
        if let logExcerpt {
            lines.append(logExcerpt.isEmpty ? "  （日志是空的：这次启动 Wine 没有报错。用 gala-cli launch 再运行一次，能得到更详细的输出。）" : logExcerpt)
        }
        return lines.joined(separator: "\n")
    }

    private static func systemDescription() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        let chip = String(cString: buffer)
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)" + (chip.isEmpty ? "" : " · \(chip)")
    }
}

extension Diagnostics {
    /// The report wrapped so that someone who has never seen Gala, or an AI assistant, can answer with a setting to change.
    public func helpRequest(profiles: [RuntimeRecipe]) -> String {
        var lines = [
            "我在用 Gala 玩一个 Windows 视觉小说，遇到了问题。Gala 是 macOS 上的启动器，用 Wine 运行游戏。",
            "请根据下面的信息判断原因，并告诉我该改哪个设置。",
            "",
            "【我遇到的问题】",
            "（在这里写：什么时候出的问题，看到了什么）",
            "",
            "【我能改的设置】都在游戏页面的“运行设置”里",
            "运行环境：" + profiles.map { "\($0.name)（\($0.id)）" }.joined(separator: "、"),
        ]
        lines += LaunchSwitch.all.map { item in
            "\(item.name)：自动、\(item.options.map(\.label).joined(separator: "、"))。\(item.hint)"
        }
        lines += [
            "高级：自定义 DLL 设置（例如 quartz=builtin）、环境变量、启动参数",
            "",
            "请用「设置名 → 选项」的形式回答，例如：视频播放方式 → Wine 自带。",
            "一次只建议改一处，我试完会告诉你结果。",
            "不要建议修改游戏目录里的文件，也不要建议从别的网站下载 DLL。",
            "",
            "—— 以下是 Gala 生成的诊断信息 ——",
            text,
        ]
        return lines.joined(separator: "\n")
    }
}
