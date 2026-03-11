import Foundation

public enum WinVersion: String, Codable, CaseIterable, Sendable {
    case win7 = "win7"
    case win10 = "win10"
    case win11 = "win11"
}

public struct BottleConfig: Codable, Sendable {
    public var prefixPath: String
    public var windowsVersion: WinVersion
    public var dllOverrides: [String: String]
    public var environment: [String: String]
    public var launchArguments: [String]
    public var locale: String
    public var winetricksComponents: [String]

    public init(
        prefixPath: String,
        windowsVersion: WinVersion = .win10,
        dllOverrides: [String: String] = [:],
        environment: [String: String] = [:],
        launchArguments: [String] = [],
        locale: String = "zh_CN.UTF-8",
        winetricksComponents: [String] = []
    ) {
        self.prefixPath = prefixPath
        self.windowsVersion = windowsVersion
        self.dllOverrides = dllOverrides
        self.environment = environment
        self.launchArguments = launchArguments
        self.locale = locale
        self.winetricksComponents = winetricksComponents
    }
}
