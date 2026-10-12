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
    public var runtimeProfile: String?
    public var isProfileChosenByHand: Bool
    public var profileProblems: [String]
    public var prefixPath: String
    public var isRuntimeConfigured: Bool
    public var isBottleReady: Bool
    public var runtimeMarker: String
    public var locale: String
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
        let usesDXMT = recipe?.usesDXMTWine == true

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
            runtimeProfile: recipe?.id,
            isProfileChosenByHand: game.profileID != nil && recipe?.id == game.profileID,
            profileProblems: wineManager.profileProblems.map(\.localizedDescription)
                + (game.profileID != nil && recipe?.id != game.profileID ? ["这个游戏选的运行环境 \(game.profileID!) 已经不存在，改用了引擎的默认环境。"] : []),
            prefixPath: scrub(game.bottleConfig.prefixPath),
            isRuntimeConfigured: game.isRuntimeConfigured,
            isBottleReady: bottleManager.isBottleReady(for: game),
            runtimeMarker: marker,
            locale: game.bottleConfig.locale,
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
            "【启动文件】\(executablePath)",
            "【版本】Gala \(appVersion) · \(system) · \(wineVersion)",
            "【引擎】\(engine ?? "未识别")",
            "【运行环境】\(runtimeProfile ?? "无")\(isProfileChosenByHand ? "（手动选择）" : "") · \(prefixPath.isEmpty ? "未指定位置" : prefixPath)",
            "【环境状态】已配置=\(isRuntimeConfigured ? "是" : "否") · bottle 就绪=\(isBottleReady ? "是" : "否") · 配置标记=\(runtimeMarker)",
            "【区域】\(locale)",
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
            lines.append(logExcerpt.isEmpty ? "  （日志是空的。用调试启动再运行一次，才会有输出。）" : logExcerpt)
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
