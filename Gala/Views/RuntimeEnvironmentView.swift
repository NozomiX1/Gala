import SwiftUI
import GalaKit
import AppKit

enum RuntimeEnvironmentChange {
    case dependenciesRepaired
    case wineConfigurationReset
    case allApplicationDataReset
}

struct RuntimeEnvironmentView: View {
    @ObservedObject var wineManager: WineManager
    let onEnvironmentChanged: (RuntimeEnvironmentChange) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var status: RuntimeEnvironmentStatus
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var resultMessage: String?
    @State private var isCheckingForUpdates = false
    @State private var updateResult: AppUpdateCheckResult?
    @State private var updateErrorMessage: String?
    @State private var showingWineConfigurationResetConfirmation = false
    @State private var showingAllDataResetConfirmation = false

    private let updateClient = GitHubReleaseClient()

    init(wineManager: WineManager, onEnvironmentChanged: @escaping (RuntimeEnvironmentChange) -> Void) {
        _wineManager = ObservedObject(wrappedValue: wineManager)
        self.onEnvironmentChanged = onEnvironmentChanged
        _status = State(initialValue: wineManager.runtimeEnvironmentStatus())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: status.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(status.isReady ? .green : .orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.isReady ? "运行环境已就绪" : "运行环境不完整")
                        .font(.title3.bold())
                    Text(status.isReady ? "Gala 已准备好运行 Windows 游戏。" : "可以修复缺失项，或清理后重新准备。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                componentRow("Wine 运行时", installed: status.isWineInstalled)
                componentRow("中文字体", installed: status.isFontInstalled)
                componentRow("辅助工具", installed: status.isHelperToolInstalled)
                componentRow(
                    "Wine 配置",
                    installed: status.hasWineConfiguration,
                    installedText: "已创建",
                    missingText: "未创建"
                )
            }

            if let resultMessage {
                Text(resultMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if isWorking && wineManager.isDownloading {
                VStack(alignment: .leading, spacing: 6) {
                    Text(wineManager.currentDownloadDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if wineManager.isDownloadProgressIndeterminate {
                        ProgressView()
                    } else {
                        ProgressView(value: wineManager.downloadProgress)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            updateStatusView

            Spacer()

            HStack {
                Button("关闭") {
                    dismiss()
                }
                Spacer()
                Button {
                    repairMissingDependencies()
                } label: {
                    Label("修复缺失项", systemImage: "arrow.clockwise")
                }
                .disabled(isWorking || status.isReady)

                Button {
                    checkForUpdates()
                } label: {
                    Label("检查更新", systemImage: "arrow.down.circle")
                }
                .disabled(isWorking || isCheckingForUpdates)

                Button(role: .destructive) {
                    showingWineConfigurationResetConfirmation = true
                } label: {
                    Label("清理 Wine 配置", systemImage: "trash")
                }
                .disabled(isWorking || !status.hasWineConfiguration)

                Button(role: .destructive) {
                    showingAllDataResetConfirmation = true
                } label: {
                    Label("清除所有数据", systemImage: "trash.fill")
                }
                .disabled(isWorking)
            }
        }
        .padding(24)
        .frame(width: 560, height: 460)
        .onAppear(perform: refreshStatus)
        .alert("清理 Wine 配置？", isPresented: $showingWineConfigurationResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) {
                resetWineConfiguration()
            }
        } message: {
            Text("这会删除所有 Wine 配置和组件安装结果。不会删除 Wine 运行时、字体、辅助工具、游戏库、封面、游玩时间，也不会删除你的游戏文件。")
        }
        .alert("清除所有 Gala 数据？", isPresented: $showingAllDataResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                resetAllApplicationData()
            }
        } message: {
            Text("这会删除 Gala 的所有本地数据，包括游戏库、封面、游玩时间、Wine 运行时和 Wine 配置。不会删除你的原始游戏文件。此操作无法撤销。")
        }
    }

    @ViewBuilder
    private var updateStatusView: some View {
        if isCheckingForUpdates {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在检查更新...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }

        if let updateErrorMessage {
            Text(updateErrorMessage)
                .font(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }

        if let updateResult {
            switch updateResult {
            case .upToDate(let currentVersion):
                Text("当前已是最新版本：\(currentVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .updateAvailable(let update):
                VStack(alignment: .leading, spacing: 8) {
                    Text("发现新版本：\(update.latestVersion)")
                        .font(.callout.bold())
                    if !update.releaseNotes.isEmpty {
                        Text(update.releaseNotes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .textSelection(.enabled)
                    }
                    Text("下载后请退出 Gala，并将新版 Gala.app 拖入 Applications 覆盖旧版。游戏库、游玩时间和运行环境会保留。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        if let downloadURL = update.downloadURL {
                            Button("下载 DMG") {
                                NSWorkspace.shared.open(downloadURL)
                            }
                        }
                        Button("打开发布页") {
                            NSWorkspace.shared.open(update.releasePageURL)
                        }
                    }
                }
            case .missingInstaller(let latestVersion, let releasePageURL, let releaseNotes):
                VStack(alignment: .leading, spacing: 8) {
                    Text("发现新版本：\(latestVersion)")
                        .font(.callout.bold())
                    if !releaseNotes.isEmpty {
                        Text(releaseNotes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .textSelection(.enabled)
                    }
                    Text("这个 release 没有找到 Gala.dmg，请打开发布页手动确认。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("打开发布页") {
                        NSWorkspace.shared.open(releasePageURL)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func componentRow(
        _ title: String,
        installed: Bool,
        installedText: String = "已安装",
        missingText: String = "未安装"
    ) -> some View {
        GridRow {
            Text(title)
            Label(
                installed ? installedText : missingText,
                systemImage: installed ? "checkmark.circle.fill" : "xmark.circle"
            )
            .foregroundStyle(installed ? .green : .secondary)
        }
    }

    private func refreshStatus() {
        status = wineManager.runtimeEnvironmentStatus()
    }

    private func repairMissingDependencies() {
        isWorking = true
        errorMessage = nil
        resultMessage = nil
        Task {
            do {
                try await wineManager.repairMissingDependencies()
                await MainActor.run {
                    isWorking = false
                    resultMessage = "缺失项已修复。"
                    refreshStatus()
                    onEnvironmentChanged(.dependenciesRepaired)
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    errorMessage = "修复失败：\(error.localizedDescription)"
                    refreshStatus()
                }
            }
        }
    }

    private func checkForUpdates() {
        isCheckingForUpdates = true
        updateResult = nil
        updateErrorMessage = nil

        Task {
            do {
                let releases = try await updateClient.releases(owner: "NozomiX1", repo: "Gala")
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
                let result = AppUpdateEvaluator.evaluate(currentVersion: currentVersion, releases: releases)
                await MainActor.run {
                    isCheckingForUpdates = false
                    updateResult = result
                }
            } catch {
                await MainActor.run {
                    isCheckingForUpdates = false
                    updateErrorMessage = "检查更新失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func resetWineConfiguration() {
        isWorking = true
        errorMessage = nil
        resultMessage = nil
        do {
            try wineManager.resetWineConfiguration()
            resultMessage = "Wine 配置已清理。"
            isWorking = false
            refreshStatus()
            onEnvironmentChanged(.wineConfigurationReset)
        } catch {
            errorMessage = "清理失败：\(error.localizedDescription)"
            isWorking = false
            refreshStatus()
        }
    }

    private func resetAllApplicationData() {
        isWorking = true
        errorMessage = nil
        resultMessage = nil
        do {
            try wineManager.resetAllApplicationData()
            resultMessage = "所有 Gala 本地数据已清除。"
            isWorking = false
            refreshStatus()
            onEnvironmentChanged(.allApplicationDataReset)
        } catch {
            errorMessage = "清除失败：\(error.localizedDescription)"
            isWorking = false
            refreshStatus()
        }
    }
}
