import SwiftUI
import GalaKit

struct WelcomeView: View {
    let wineManager: WineManager
    let onComplete: () -> Void

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
                }
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("正在准备环境...\n下载 Wine Staging 11.6")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(width: 500, height: 400)
        .onAppear {
            if wineManager.isWineInstalled {
                // Wine already present (e.g. manually installed) — ensure font is downloaded
                Task {
                    try? await wineManager.downloadFont()
                    await MainActor.run { onComplete() }
                }
            } else {
                startDownload()
            }
        }
    }

    private func startDownload() {
        Task {
            do {
                try await wineManager.downloadWine(
                    from: WineManager.wineDownloadURL,
                    versionName: WineManager.wineVersionName
                )
                // Download font independently — failure doesn't block setup
                try? await wineManager.downloadFont()
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
