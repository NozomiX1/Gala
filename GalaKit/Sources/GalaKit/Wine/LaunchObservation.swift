import Foundation

/// What a launch log shows the game really used, read from Wine's `loaddll` lines.
/// The files in a game folder can mislead: a packer hides the imports, a launcher has none, VNDB names another release.
/// What Wine loaded for the running game cannot.
public struct LaunchObservation: Equatable, Sendable {
    /// Lower-cased module name to how it was loaded last, "native" or "builtin".
    public let modules: [String: String]

    public init(log: String) {
        var modules: [String: String] = [:]
        for line in log.split(separator: "\n") where line.contains("trace:loaddll") {
            // ...Loaded L"C:\\windows\\system32\\quartz.dll" at 6FFFF9E90000: native
            guard let open = line.range(of: "Loaded L\""), let close = line.range(of: "\" at ", range: open.upperBound..<line.endIndex),
                  let kind = line.split(separator: " ").last, kind == "native" || kind == "builtin" else { continue }
            let path = line[open.upperBound..<close.lowerBound]
            let name = path.components(separatedBy: "\\").last ?? String(path)
            modules[name.lowercased()] = String(kind)
        }
        self.modules = modules
    }

    public var isEmpty: Bool { modules.isEmpty }

    private func loaded(_ names: String...) -> Bool { names.contains { modules[$0] != nil } }

    public var usesD3D11: Bool { loaded("d3d11.dll", "d3d10core.dll") }
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
    public func advice(usesDXMTWine: Bool, usesMediaFoundationRuntime: Bool) -> [String] {
        var advice: [String] = []
        if usesD3D11, !usesDXMTWine {
            advice.append("这个游戏用 D3D11 绘制画面。如果画面全黑、花屏或者闪烁，把「图形渲染」换成 DXMT。")
        }
        if usesStubMediaPlayer {
            advice.append("这个游戏调用 Windows Media Player 来放视频，这里放不出来，视频会被直接跳过。如果游戏自己的设置里可以选别的播放方式（比如 MCI），请换掉它。")
        }
        if usesMediaFoundation, !usesMediaFoundationRuntime {
            advice.append("这个游戏用 Media Foundation 放视频。如果视频黑屏或者被跳过，可以试试「Artemis（D3D11 · 新式视频）」这个运行环境。")
        }
        return advice
    }
}
