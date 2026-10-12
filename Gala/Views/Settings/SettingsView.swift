import Sparkle
import SwiftUI
import GalaKit

struct SettingsView: View {
    let library: LibraryViewModel
    let updater: SPUUpdater

    // GALA_DEBUG_SETTINGS=runtime opens on that tab, for screenshots.
    @State private var tab = ProcessInfo.processInfo.environment["GALA_DEBUG_SETTINGS"] ?? "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings(updater: updater)
                .frame(height: 150)
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag("general")
            RuntimeSettings(library: library, wineManager: library.wineManagerInstance)
                .frame(height: 385)
                .tabItem { Label("运行环境", systemImage: "wrench.and.screwdriver") }
                .tag("runtime")
            DataSettings(library: library)
                .frame(height: 230)
                .tabItem { Label("数据", systemImage: "externaldrive") }
                .tag("data")
        }
        .frame(width: 500)
    }
}

private struct GeneralSettings: View {
    let updater: SPUUpdater
    @State private var checksAutomatically: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        _checksAutomatically = State(initialValue: updater.automaticallyChecksForUpdates)
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $checksAutomatically) {
                    Text("自动检查更新")
                    Text("有新版本时提示你，不会自动安装。")
                }
                .onChange(of: checksAutomatically) { _, isOn in
                    updater.automaticallyChecksForUpdates = isOn
                }
                LabeledContent("当前版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")") {
                    Button("检查更新…", action: updater.checkForUpdates)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct RuntimeSettings: View {
    let library: LibraryViewModel
    @ObservedObject var wineManager: WineManager

    @State private var status: RuntimeEnvironmentStatus
    @State private var isWorking = false
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var fontStatus: OptionalFontStatus
    @State private var isInstallingFonts = false
    @State private var fontError: String?

    init(library: LibraryViewModel, wineManager: WineManager) {
        self.library = library
        self.wineManager = wineManager
        _status = State(initialValue: wineManager.runtimeEnvironmentStatus())
        _fontStatus = State(initialValue: library.bottleManager.optionalFontStatus())
    }

    var body: some View {
        Form {
            Section {
                row("Wine 运行时", detail: WineManager.wineVersionName, installed: status.isWineInstalled)
                row("中文字体", detail: "思源黑体", installed: status.isFontInstalled)
                row("辅助工具", detail: "winetricks、cabextract", installed: status.isHelperToolInstalled)
            }

            Section {
                optionalFonts
            }

            Section {
                if isWorking && wineManager.isDownloading {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(wineManager.currentDownloadDescription)
                        if wineManager.isDownloadProgressIndeterminate {
                            ProgressView().progressViewStyle(.linear)
                        } else {
                            ProgressView(value: wineManager.downloadProgress)
                        }
                    }
                }
                LabeledContent {
                    Button("修复缺失项", action: repair)
                        .disabled(isWorking || status.isReady)
                } label: {
                    Text(status.isReady ? "一切正常" : "运行环境不完整")
                    Text(errorMessage ?? message ?? "缺少某一项时，可以在这里重新下载。")
                        .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            status = wineManager.runtimeEnvironmentStatus()
            fontStatus = library.bottleManager.optionalFontStatus()
        }
    }

    /// Kept apart from the rows above: games run without these fonts, they only decide how one kind of game draws its text.
    private var optionalFonts: some View {
        LabeledContent {
            if isInstallingFonts {
                ProgressView()
                    .controlSize(.small)
            } else if fontStatus.isSettled {
                Text("已安装")
                    .foregroundStyle(.secondary)
            } else {
                Button(fontStatus.areFontsInstalled ? "应用到现有环境" : "下载", action: installFonts)
                    .disabled(isWorking || !status.isWineInstalled)
            }
        } label: {
            Label {
                Text("可选字体")
                Text(fontDetail)
                    .foregroundStyle(fontError == nil ? Color.secondary : Color.red)
            } icon: {
                Image(systemName: fontStatus.isSettled ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(fontStatus.isSettled ? Color.green : Color.secondary)
            }
        }
    }

    private var fontDetail: String {
        if let fontError { return fontError }
        let about = "简宋、华文黑体。日本引擎游戏的宋体和黑体用它们显示，由 macOS 下载。"
        if fontStatus.areFontsInstalled, fontStatus.outdatedPrefixCount > 0 {
            return about + "有 \(fontStatus.outdatedPrefixCount) 个运行环境还没有用上。"
        }
        return about
    }

    private func installFonts() {
        isInstallingFonts = true
        fontError = nil
        let bottleManager = library.bottleManager
        Task { @MainActor in
            do {
                try await bottleManager.installOptionalFonts()
            } catch {
                fontError = "没能完成：\(error.localizedDescription)"
            }
            fontStatus = bottleManager.optionalFontStatus()
            if fontError == nil, !fontStatus.areFontsInstalled {
                fontError = "macOS 没能下载这两个字体，请检查网络后再试。游戏仍然可以运行。"
            }
            isInstallingFonts = false
        }
    }

    private func row(_ title: String, detail: String, installed: Bool) -> some View {
        LabeledContent {
            Text(installed ? "已安装" : "未安装")
                .foregroundStyle(.secondary)
        } label: {
            Label {
                Text(title)
                Text(detail)
            } icon: {
                Image(systemName: installed ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(installed ? Color.green : Color.secondary)
            }
        }
    }

    private func repair() {
        isWorking = true
        message = nil
        errorMessage = nil
        Task { @MainActor in
            do {
                try await wineManager.repairMissingDependencies()
                message = "缺失项已修复。"
                library.apply(.dependenciesRepaired)
            } catch {
                errorMessage = "修复失败：\(error.localizedDescription)"
            }
            isWorking = false
            status = wineManager.runtimeEnvironmentStatus()
        }
    }
}

private struct DataSettings: View {
    let library: LibraryViewModel

    @State private var confirmingWineReset = false
    @State private var confirmingFullReset = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button("清理…", role: .destructive) { confirmingWineReset = true }
                        .disabled(!library.wineManagerInstance.runtimeEnvironmentStatus().hasWineConfiguration)
                } label: {
                    Text("清理 Wine 配置")
                    Text("删除所有运行环境，游戏需要重新配置。游戏库、游玩时间和游戏文件都会保留。")
                }
                LabeledContent {
                    Button("清除…", role: .destructive) { confirmingFullReset = true }
                } label: {
                    Text("清除所有数据")
                    Text("删除游戏库、封面、游玩时间和 Wine。不会动你的游戏文件。无法撤销。")
                }
            } footer: {
                if let text = errorMessage ?? message {
                    Text(text)
                        .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
        .alert("清理 Wine 配置？", isPresented: $confirmingWineReset) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) {
                reset(.wineConfigurationReset, done: "Wine 配置已清理。") { try $0.resetWineConfiguration() }
            }
        } message: {
            Text("这会删除所有 Wine 配置和组件安装结果。不会删除 Wine 运行时、字体、辅助工具、游戏库、封面、游玩时间，也不会删除你的游戏文件。")
        }
        .alert("清除所有 Gala 数据？", isPresented: $confirmingFullReset) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                reset(.allApplicationDataReset, done: "所有 Gala 本地数据已清除。") { try $0.resetAllApplicationData() }
            }
        } message: {
            Text("这会删除 Gala 的所有本地数据，包括游戏库、封面、游玩时间、Wine 运行时和 Wine 配置。不会删除你的原始游戏文件。此操作无法撤销。")
        }
    }

    private func reset(_ change: RuntimeEnvironmentChange, done: String, _ action: (WineManager) throws -> Void) {
        do {
            try action(library.wineManagerInstance)
            message = done
            errorMessage = nil
            library.apply(change)
        } catch {
            errorMessage = "操作失败：\(error.localizedDescription)"
        }
    }
}
