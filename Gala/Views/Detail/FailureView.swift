import SwiftUI

/// Why the last launch or setup failed, with the two ways forward.
struct FailureView: View {
    let title: String
    let message: String
    let onChangeSettings: () -> Void
    let onCopyHelp: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("没能启动")
                    .font(.title2.weight(.semibold))
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)

            ScrollView {
                Text(message)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 70, maxHeight: 220)
            .fixedSize(horizontal: false, vertical: true)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            HStack {
                Button("换个运行环境试试", action: onChangeSettings)
                Button("复制求助信息…", action: onCopyHelp)
                Spacer()
                Button("好") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 520)
    }
}
