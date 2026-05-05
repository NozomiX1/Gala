import SwiftUI
import GalaKit

enum RuntimeEnvironmentChange {
    case dependenciesRepaired
    case wineConfigurationReset
    case allApplicationDataReset
}

struct RuntimeEnvironmentView: View {
    let wineManager: WineManager
    let onEnvironmentChanged: (RuntimeEnvironmentChange) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var status: RuntimeEnvironmentStatus
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var resultMessage: String?
    @State private var showingWineConfigurationResetConfirmation = false
    @State private var showingAllDataResetConfirmation = false

    init(wineManager: WineManager, onEnvironmentChanged: @escaping (RuntimeEnvironmentChange) -> Void) {
        self.wineManager = wineManager
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

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

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
        .frame(width: 520, height: 360)
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
