import Foundation

public struct BottleConfig: Codable, Sendable {
    public var prefixPath: String
    public var dllOverrides: [String: String]
    public var environment: [String: String]
    public var launchArguments: [String]
    public var locale: String

    public init(
        prefixPath: String,
        dllOverrides: [String: String] = [:],
        environment: [String: String] = [:],
        launchArguments: [String] = [],
        locale: String = "zh_CN.UTF-8"
    ) {
        self.prefixPath = prefixPath
        self.dllOverrides = dllOverrides
        self.environment = environment
        self.launchArguments = launchArguments
        self.locale = locale
    }
}
