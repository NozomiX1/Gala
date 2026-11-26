import SwiftUI
import GalaKit

/// Shows the help text before it goes on the clipboard, so nothing is copied unseen.
struct HelpRequestView: View {
    let game: Game
    let library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var text: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("复制求助信息")
                    .font(.title2.weight(.semibold))
                Text("下面这段文字会被复制。可以粘贴给任何 AI 助手，或者贴到 GitHub issue 里。路径里的用户名已经去掉。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)

            GalaSheetCard {
                ScrollView {
                    if let text {
                        Text(text)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(40)
                    }
                }
                .galaOverlayScrollbars()
                .frame(height: 340)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            GalaSheetDivider()

            HStack(spacing: 12) {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .galaButtonStyle()
                    .keyboardShortcut(.cancelAction)
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text ?? "", forType: .string)
                    dismiss()
                }
                .galaButtonStyle(prominent: true)
                .keyboardShortcut(.defaultAction)
                .disabled(text == nil)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 580)
        .task {
            let profiles = library.wineManagerInstance.profiles.recipes
            text = await library.diagnostics(for: game).helpRequest(profiles: profiles)
        }
    }
}
