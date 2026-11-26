import Foundation

/// One actionable or informational suggestion shown for a game.
/// Applying an action only edits the user's draft in run settings; advice never changes a game silently.
public struct RuntimeAdvice: Equatable, Sendable, Identifiable {
    public struct Action: Equatable, Sendable {
        public var profileID: String?
        public var launchSwitches: [String: String]
        public var dllOverrides: [String: String]

        public init(
            profileID: String? = nil,
            launchSwitches: [String: String] = [:],
            dllOverrides: [String: String] = [:]
        ) {
            self.profileID = profileID
            self.launchSwitches = launchSwitches
            self.dllOverrides = dllOverrides
        }
    }

    public var id: String { message }
    public let message: String
    public let action: Action?

    public init(message: String, action: Action? = nil) {
        self.message = message
        self.action = action
    }
}

/// What a launch log shows the game really used, read from Wine's `loaddll` lines.
/// The files in a game folder can mislead: a packer hides the imports, a launcher has none, VNDB names another release.
/// What Wine loaded for the running game cannot.
public struct LaunchObservation: Equatable, Sendable {
    /// Lower-cased module name to how it was loaded last, "native" or "builtin".
    public let modules: [String: String]
    /// Original casing of each module name as logged by Wine, keyed by lower-cased name.
    private let originalNames: [String: String]

    public init(log: String) {
        var modules: [String: String] = [:]
        var originalNames: [String: String] = [:]
        for line in log.split(separator: "\n") where line.contains("trace:loaddll") {
            // ...Loaded L"C:\\windows\\system32\\quartz.dll" at 6FFFF9E90000: native
            guard let open = line.range(of: "Loaded L\""), let close = line.range(of: "\" at ", range: open.upperBound..<line.endIndex),
                  let kind = line.split(separator: " ").last, kind == "native" || kind == "builtin" else { continue }
            let path = line[open.upperBound..<close.lowerBound]
            let name = path.components(separatedBy: "\\").last ?? String(path)
            let key = name.lowercased()
            modules[key] = String(kind)
            originalNames[key] = name
        }
        self.modules = modules
        self.originalNames = originalNames
    }

    public var isEmpty: Bool { modules.isEmpty }

    private func loaded(_ names: String...) -> Bool { names.contains { modules[$0] != nil } }

    public var usesD3D11: Bool { loaded("d3d11.dll", "d3d10core.dll") }
    public var usesD2D1: Bool { loaded("d2d1.dll") }
    /// KiriKiri Z Direct2D draw-device plugin stem (e.g. `DrawDeviceD2Dv2`), when one was loaded.
    public var direct2DDrawPlugin: String? {
        guard let key = modules.keys
            .filter({ $0.hasPrefix("drawdeviced2d") && $0.hasSuffix(".dll") })
            .sorted()
            .first else { return nil }
        let name = originalNames[key] ?? key
        return String(name.dropLast(4))
    }
    /// The Windows Media Player control. Wine's own is a shell that plays nothing.
    public var usesStubMediaPlayer: Bool { modules["wmp.dll"] == "builtin" }
    public var usesMediaFoundation: Bool { loaded("mf.dll", "mfreadwrite.dll") }

    /// One line for a report: which graphics and video paths the game took.
    public var summary: String {
        var graphics: [String] = []
        if loaded("ddraw.dll") { graphics.append("DirectDraw") }
        if loaded("d3d8.dll") { graphics.append("D3D8") }
        if loaded("d3d9.dll") { graphics.append("D3D9") }
        if usesD3D11 { graphics.append("D3D11") }
        if usesD2D1 { graphics.append("Direct2D") }
        if loaded("opengl32.dll") && graphics.isEmpty { graphics.append("OpenGL") }

        var video: [String] = []
        if let quartz = modules["quartz.dll"] { video.append("DirectShow（\(quartz == "native" ? "Windows 原版" : "Wine 自带")）") }
        if modules.keys.contains(where: { $0.hasPrefix("lav") && $0.hasSuffix(".ax") }) { video.append("LAV 解码器") }
        if loaded("mciqtz32.dll") { video.append("MCI") }
        if let player = modules["wmp.dll"] { video.append("Windows Media Player 控件（\(player == "native" ? "Windows 原版" : "Wine 的空壳")）") }
        if usesMediaFoundation { video.append("Media Foundation") }

        return "图形：\(graphics.isEmpty ? "没有记录到" : graphics.joined(separator: "、")) · 视频：\(video.isEmpty ? "这次运行没有用到" : video.joined(separator: "、"))"
    }

    /// What the user could try, given what the game used and what it was run with.
    public func adviceItems(usesDXMTWine: Bool, usesMediaFoundationRuntime: Bool) -> [RuntimeAdvice] {
        var items: [RuntimeAdvice] = []
        if let plugin = direct2DDrawPlugin {
            if usesDXMTWine {
                items.append(RuntimeAdvice(
                    message: "这个游戏通过 \(plugin) 用 Direct2D 绘制画面，和 DXMT 不兼容，容易白屏或闪烁。可以把「图形渲染」改回「自动」或「Wine 自带」，并在「高级 → 自定义 DLL 设置」里填入 \(plugin)=disabled，让游戏退回传统的 D3D9 渲染（启动时若弹出加载失败提示，点确定即可）。",
                    action: .init(
                        launchSwitches: [LaunchSwitch.graphics.id: "builtin"],
                        dllOverrides: [plugin: "disabled"]
                    )
                ))
            } else {
                items.append(RuntimeAdvice(
                    message: "这个游戏通过 \(plugin) 用 Direct2D 绘制画面，在 macOS 上容易白屏或闪烁。可以在「高级 → 自定义 DLL 设置」里填入 \(plugin)=disabled，让游戏退回传统的 D3D9 渲染（启动时若弹出加载失败提示，点确定即可）。",
                    action: .init(dllOverrides: [plugin: "disabled"])
                ))
            }
        } else if usesD3D11, usesD2D1 {
            if usesDXMTWine {
                items.append(RuntimeAdvice(
                    message: "这个游戏用 Direct2D 叠加在 D3D11 上绘制画面，DXMT 目前不兼容 Direct2D。如果画面白屏或闪烁，把「图形渲染」改回「Wine 自带」。",
                    action: .init(launchSwitches: [LaunchSwitch.graphics.id: "builtin"])
                ))
            }
        } else if usesD3D11, !usesDXMTWine {
            items.append(RuntimeAdvice(
                message: "这个游戏用 D3D11 绘制画面。如果画面全黑、花屏或者闪烁，把「图形渲染」换成 DXMT。",
                action: .init(launchSwitches: [LaunchSwitch.graphics.id: "dxmt"])
            ))
        }
        if usesStubMediaPlayer {
            items.append(RuntimeAdvice(
                message: "这个游戏调用 Windows Media Player 来放视频，这里放不出来，视频会被直接跳过。如果游戏自己的设置里可以选别的播放方式（比如 MCI），请换掉它。"
            ))
        }
        if usesMediaFoundation, !usesMediaFoundationRuntime {
            items.append(RuntimeAdvice(
                message: "这个游戏用 Media Foundation 放视频。如果视频黑屏或者被跳过，可以试试「Artemis（D3D11 · 新式视频）」这个运行环境。",
                action: .init(profileID: RuntimeProfile.artemisMFD3D11.rawValue)
            ))
        }
        return items
    }

    /// Plain-text form of `adviceItems`, for diagnostics and acknowledged-advice tracking.
    public func advice(usesDXMTWine: Bool, usesMediaFoundationRuntime: Bool) -> [String] {
        adviceItems(usesDXMTWine: usesDXMTWine, usesMediaFoundationRuntime: usesMediaFoundationRuntime)
            .map(\.message)
    }
}
