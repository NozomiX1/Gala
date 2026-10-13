import Sparkle
import SwiftUI
import GalaKit

struct SettingsView: View {
    let library: LibraryViewModel
    let updater: SPUUpdater

    // GALA_DEBUG_SETTINGS=runtime opens on that tab, for screenshots; "unused" opens the data tab and runs its search.
    @State private var tab = Self.debugTab == "unused" ? "data" : (Self.debugTab ?? "general")

    fileprivate static let debugTab = ProcessInfo.processInfo.environment["GALA_DEBUG_SETTINGS"]

    private var ownProfileCount: Int { library.wineManagerInstance.profiles.recipes.filter(\.isUserProvided).count }

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings(updater: updater)
                .frame(height: 150)
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag("general")
            RuntimeSettings(library: library, wineManager: library.wineManagerInstance)
                // Room for the user's own environments when there are any; more than three scroll.
                .frame(height: 385 + (ownProfileCount > 0 ? 44 + CGFloat(min(ownProfileCount, 3)) * 54 : 0))
                .tabItem { Label("运行环境", systemImage: "wrench.and.screwdriver") }
                .tag("runtime")
            DataSettings(library: library)
                .frame(height: 280)
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
    /// Nil until the first check comes back; it reads every prefix's registry file, so it runs off the main thread.
    @State private var fontStatus: OptionalFontStatus?
    @State private var isInstallingFonts = false
    @State private var fontError: String?
    /// The user's own environments. Read again after each deletion: the profile list is not observed.
    @State private var ownProfiles: [LibraryViewModel.UserProfileUsage]
    @State private var deleting: LibraryViewModel.UserProfileUsage?

    init(library: LibraryViewModel, wineManager: WineManager) {
        self.library = library
        self.wineManager = wineManager
        _status = State(initialValue: wineManager.runtimeEnvironmentStatus())
        _ownProfiles = State(initialValue: library.userProfileUsage())
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

            if !ownProfiles.isEmpty {
                Section("我的运行环境") {
                    ForEach(ownProfiles) { item in
                        LabeledContent {
                            Button("删除…", role: .destructive) { deleting = item }
                                .disabled(!item.dependents.isEmpty)
                        } label: {
                            Text(item.recipe.name)
                            Text(caption(for: item))
                        }
                    }
                }
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
            ownProfiles = library.userProfileUsage()
        }
        .task { fontStatus = await checkFonts() }
        .alert(
            "删除「\(deleting?.recipe.name ?? "")」？",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { item in
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                library.deleteUserProfile(item.recipe.id)
                ownProfiles = library.userProfileUsage()
            }
        } message: { item in
            Text(deletionWarning(for: item))
        }
    }

    private func caption(for item: LibraryViewModel.UserProfileUsage) -> String {
        let base = item.recipe.baseID.flatMap { wineManager.profiles.recipe(id: $0)?.name }.map { "基于\($0)" } ?? "从零建立"
        if !item.dependents.isEmpty {
            return "\(base) · 「\(item.dependents.joined(separator: "」「"))」基于它，不能删除"
        }
        let users = item.games.isEmpty ? "没有游戏在用" : "在用：" + item.games.map(\.title).joined(separator: "、")
        return "\(base) · \(users)"
    }

    private func deletionWarning(for item: LibraryViewModel.UserProfileUsage) -> String {
        var parts: [String] = []
        if !item.games.isEmpty {
            parts.append("\(item.games.map(\.title).joined(separator: "、"))会改回自动选择的运行环境，需要重新配置。")
        }
        if item.recipe.bottleID == item.recipe.id {
            parts.append("它建出来的环境会一起删除。如果游戏把存档放在环境里，那些存档也会删除。")
        }
        return parts.isEmpty ? "它不占用单独的环境，删除后只是不再出现在列表里。" : parts.joined(separator: "\n\n")
    }

    /// Kept apart from the rows above: games run without these fonts, they only decide how one kind of game draws its text.
    private var optionalFonts: some View {
        LabeledContent {
            if isInstallingFonts {
                ProgressView()
                    .controlSize(.small)
            } else if let fontStatus, fontStatus.isSettled {
                Text("已安装")
                    .foregroundStyle(.secondary)
            } else if let fontStatus {
                Button(fontStatus.areFontsInstalled ? "应用到现有环境" : "下载", action: installFonts)
                    .disabled(isWorking || !status.isWineInstalled)
            }
        } label: {
            Label {
                Text("可选字体")
                Text(fontDetail)
                    .foregroundStyle(fontError == nil ? Color.secondary : Color.red)
            } icon: {
                Image(systemName: fontStatus?.isSettled == true ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(fontStatus?.isSettled == true ? Color.green : Color.secondary)
            }
        }
    }

    private var fontDetail: String {
        if let fontError { return fontError }
        let about = "简宋、华文黑体。日本引擎游戏的宋体和黑体用它们显示，由 macOS 下载。"
        if let fontStatus, fontStatus.areFontsInstalled, fontStatus.outdatedPrefixCount > 0 {
            return about + "有 \(fontStatus.outdatedPrefixCount) 个运行环境还没有用上。"
        }
        return about
    }

    private func checkFonts() async -> OptionalFontStatus {
        let wineManager = wineManager
        return await Task.detached {
            BottleManager(bottlesDirectory: wineManager.bottlesDirectory, wineManager: wineManager).optionalFontStatus()
        }.value
    }

    private func installFonts() {
        isInstallingFonts = true
        fontError = nil
        let wineManager = wineManager
        Task { @MainActor in
            do {
                // Off the main thread: it runs Wine once per prefix and waits for each.
                try await Task.detached {
                    try await BottleManager(bottlesDirectory: wineManager.bottlesDirectory, wineManager: wineManager).installOptionalFonts()
                }.value
            } catch {
                fontError = "没能完成：\(error.localizedDescription)"
            }
            let now = await checkFonts()
            fontStatus = now
            if fontError == nil, !now.areFontsInstalled {
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
    /// Nil while nothing has been looked for; the sheet shows what was found.
    @State private var unused: [UnusedPrefix]?
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button("查找…", action: findUnused)
                } label: {
                    Text("清理没有游戏在用的环境")
                    Text("换过运行环境、或者删掉游戏之后，原来的环境会留在磁盘上。这里把它们找出来，由你决定删不删。")
                }
            }

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
        .onAppear { if SettingsView.debugTab == "unused" { findUnused() } }
        .sheet(isPresented: Binding(get: { unused?.isEmpty == false }, set: { if !$0 { unused = nil } })) {
            UnusedPrefixesView(found: unused ?? []) { chosen in
                library.deletePrefixes(chosen.map(\.url))
                message = "已删除 \(chosen.count) 个环境。"
                errorMessage = nil
            }
        }
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

    private func findUnused() {
        let profiles = library.wineManagerInstance.profiles
        let found = library.unusedPrefixes().map { url in
            UnusedPrefix(url: url, name: profiles.recipe(id: url.lastPathComponent)?.name ?? url.lastPathComponent)
        }
        if found.isEmpty {
            message = "没有找到：磁盘上的环境都有游戏在用。"
            errorMessage = nil
        }
        unused = found
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

struct UnusedPrefix: Identifiable, Hashable {
    let url: URL
    let name: String
    var id: URL { url }
}

/// The prefixes no game points at, for the user to pick from. Nothing here is deleted without a choice:
/// a prefix can hold the saves of a game that used to run in it.
private struct UnusedPrefixesView: View {
    let found: [UnusedPrefix]
    let onDelete: ([UnusedPrefix]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<UnusedPrefix>

    init(found: [UnusedPrefix], onDelete: @escaping ([UnusedPrefix]) -> Void) {
        self.found = found
        self.onDelete = onDelete
        // The shared root is what new environments are copied from: left unticked, since without it the next one takes minutes.
        _chosen = State(initialValue: Set(found.filter { $0.url.lastPathComponent != RuntimeProfile.common.rawValue }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("没有游戏在用的环境")
                    .font(.title2.weight(.semibold))
                Text("这些环境现在没有任何游戏在用。有些游戏把存档放在环境里：如果某个游戏以前在其中一个里运行过，删除会连那些存档一起删掉，无法找回。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(found) { item in
                        Toggle(isOn: Binding(
                            get: { chosen.contains(item) },
                            set: { isOn in if isOn { chosen.insert(item) } else { chosen.remove(item) } }
                        )) {
                            Text(item.name)
                            Text(item.url.lastPathComponent == RuntimeProfile.common.rawValue
                                ? "新建环境时要从它复制。删掉的话，下次需要重新安装，要等几分钟。"
                                : item.url.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .frame(maxHeight: 240)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 14) {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("删除选中的 \(chosen.count) 个", role: .destructive) {
                    onDelete(found.filter(chosen.contains))
                    dismiss()
                }
                .disabled(chosen.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 460)
    }
}
