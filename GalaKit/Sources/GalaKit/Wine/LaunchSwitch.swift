import Foundation

/// A named per-game setting that takes effect at the next launch, with no change to the prefix.
/// A switch is only listed here once a real game has shown that launch-time is enough; see `docs/runtime-lessons.md`.
public struct LaunchSwitch: Identifiable, Sendable {
    public struct Option: Identifiable, Sendable {
        public let id: String
        public let label: String
    }

    public let id: String
    public let name: String
    /// The symptom that makes it worth trying.
    public let hint: String
    /// Leaving a switch unset ("自动") follows the runtime profile.
    public let options: [Option]

    public static let video = LaunchSwitch(
        id: "video",
        name: "视频播放方式",
        hint: "片头或过场动画黑屏、被跳过时试试",
        options: [Option(id: "native", label: "Windows 原版"), Option(id: "builtin", label: "Wine 自带")]
    )

    public static let graphics = LaunchSwitch(
        id: "graphics",
        name: "图形渲染",
        hint: "有声音但画面全黑时试试",
        options: [Option(id: "dxmt", label: "DXMT"), Option(id: "builtin", label: "Wine 自带")]
    )

    public static let locale = LaunchSwitch(
        id: "locale",
        name: "文字区域",
        hint: "想玩日文原版时选日文，其他情况不用改",
        options: [Option(id: "zh", label: "中文"), Option(id: "ja", label: "日文")]
    )

    public static let all = [video, graphics, locale]
}

extension Game {
    /// The DLL overrides for a launch: what the switches ask for, with the hand-written ones on top.
    public var launchDLLOverrides: [String: String] {
        let mode: String? = switch launchSwitches[LaunchSwitch.video.id] {
        // Falls back to builtin where the prefix has no native DLL, instead of failing to load.
        case "native": "native,builtin"
        case "builtin": "builtin"
        default: nil
        }
        var overrides: [String: String] = [:]
        if let mode {
            overrides["quartz"] = mode
            overrides["amstream"] = mode
        }
        return overrides.merging(bottleConfig.dllOverrides) { _, custom in custom }
    }

    /// Whether the graphics switch picks the Wine build; nil leaves it to the profile.
    public var forcesDXMTWine: Bool? {
        switch launchSwitches[LaunchSwitch.graphics.id] {
        case "dxmt": true
        case "builtin": false
        default: nil
        }
    }

    /// The locale Wine starts in, which decides the Windows code page for that run:
    /// the game's switch, else what its profile asks for, else the one its prefix was built with.
    public func launchLocale(recipe: RuntimeRecipe?) -> String {
        switch launchSwitches[LaunchSwitch.locale.id] {
        case "ja": "ja_JP.UTF-8"
        case "zh": "zh_CN.UTF-8"
        default: recipe?.locale ?? bottleConfig.locale
        }
    }

    public var launchLocale: String { launchLocale(recipe: nil) }

    /// Arguments for the game: its own when it has any, else its profile's.
    public func launchArguments(recipe: RuntimeRecipe?) -> [String] {
        bottleConfig.launchArguments.isEmpty ? (recipe?.launchArguments ?? []) : bottleConfig.launchArguments
    }

    /// The game's own settings written as a profile file, so a combination that works can be handed to someone else.
    /// Only what differs from `recipe` is written; the rest comes with `base`.
    public func exportedProfile(base recipe: RuntimeRecipe) -> ProfileFile {
        let overrides = launchDLLOverrides
        let locale = launchLocale(recipe: recipe)
        return ProfileFile(
            id: "\(recipe.id)-\(id.uuidString.prefix(8).lowercased())",
            name: "\(title) 的配置",
            base: recipe.id,
            wine: forcesDXMTWine.map { $0 ? .dxmt : .standard },
            dllOverrides: overrides.isEmpty ? nil : overrides.mapValues { Optional($0) },
            environment: bottleConfig.environment.isEmpty ? nil : bottleConfig.environment.mapValues { Optional($0) },
            launchArguments: bottleConfig.launchArguments.isEmpty ? nil : bottleConfig.launchArguments,
            locale: launchSwitches[LaunchSwitch.locale.id] == nil ? nil : locale
        )
    }
}

extension BottleConfig {
    /// Reads `名字=取值` pairs separated by semicolons or line breaks; pieces without a name or an `=` are dropped.
    public static func pairs(from text: String) -> [String: String] {
        var pairs: [String: String] = [:]
        for line in text.split(whereSeparator: { $0.isNewline || $0 == ";" || $0 == "；" }) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard parts.count == 2, !name.isEmpty else { continue }
            pairs[name] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        return pairs
    }

    public static func text(from pairs: [String: String]) -> String {
        pairs.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }
}
