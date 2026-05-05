import SwiftUI
import GalaKit

struct WelcomeView: View {
    @ObservedObject var wineManager: WineManager
    let onComplete: () -> Void
    var onOpenEnvironment: (() -> Void)?

    @State private var errorMessage: String?
    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("欢迎使用 Gala")
                .font(.largeTitle.bold())

            if let error = errorMessage {
                VStack(spacing: 12) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: 400)

                    Button("重试") {
                        errorMessage = nil
                        isRetrying = true
                        startDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRetrying)

                    if let onOpenEnvironment {
                        Button("环境检查") {
                            onOpenEnvironment()
                        }
                        .disabled(isRetrying)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    if wineManager.isDownloading && !wineManager.isDownloadProgressIndeterminate {
                        ProgressView(value: wineManager.downloadProgress)
                            .frame(width: 260)
                    } else {
                        ProgressView()
                    }
                    Text(wineManager.currentDownloadDescription.isEmpty ? "正在准备运行环境..." : wineManager.currentDownloadDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if wineManager.isDownloading && !wineManager.isDownloadProgressIndeterminate {
                        Text("\(Int(wineManager.downloadProgress * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
        .onAppear {
            if wineManager.runtimeEnvironmentStatus().isReady {
                onComplete()
            } else {
                startDownload()
            }
        }
    }

    private func startDownload() {
        Task {
            do {
                try await wineManager.repairMissingDependencies()
                await MainActor.run { onComplete() }
            } catch {
                await MainActor.run {
                    errorMessage = "下载失败：\(error.localizedDescription)"
                    isRetrying = false
                }
            }
        }
    }
}

struct ResetCompleteView: View {
    let onInstallRuntime: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("本地数据已清除")
                    .font(.largeTitle.bold())
                Text("Gala 的本地数据和运行环境已移除。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("退出 Gala") {
                    onQuit()
                }
                .controlSize(.large)

                Button("重新安装运行环境") {
                    onInstallRuntime()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 500, height: 400)
    }
}
