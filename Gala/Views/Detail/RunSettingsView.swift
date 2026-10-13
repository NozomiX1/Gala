import SwiftUI
import GalaKit

/// How one game is run: its runtime profile, the named switches, and free-form overrides.
/// Edits a copy; nothing is saved until 完成.
struct RunSettingsView: View {
    let game: Game
    let library: LibraryViewModel
    /// What the profile's author and the last launch suggest; listed first, and marked as seen when the panel closes.
    let advice: [String]
    @Environment(\.dismiss) private var dismiss

    @State private var profileID: String?
    @State private var switches: [String: String]
    @State private var dllText: String
    @State private var environmentText: String
    @State private var argumentsText: String
    @State private var showsAdvanced: Bool
    @State private var exportError: String?

    private var profiles: ProfileStore { library.wineManagerInstance.profiles }

    init(game: Game, library: LibraryViewModel, advice: [String] = [], showsAdvanced: Bool = false) {
        self.game = game
        self.library = library
        self.advice = advice
        let config = game.bottleConfig
        // A hand-picked profile whose file is gone already runs as the default; show it that way.
        let known = game.profileID.flatMap { library.wineManagerInstance.profiles.recipe(id: $0) }
        _profileID = State(initialValue: known?.id)
        _switches = State(initialValue: game.launchSwitches)
        _dllText = State(initialValue: BottleConfig.text(from: config.dllOverrides))
        _environmentText = State(initialValue: BottleConfig.text(from: config.environment))
        _argumentsText = State(initialValue: config.launchArguments.joined(separator: " "))
        let hasAdvanced = !config.dllOverrides.isEmpty || !config.environment.isEmpty || !config.launchArguments.isEmpty
        _showsAdvanced = State(initialValue: showsAdvanced || hasAdvanced)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("运行设置")
                    .font(.title2.weight(.semibold))
                Text(game.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)

            Form {
                if !advice.isEmpty {
                    Section("建议") {
                        ForEach(advice, id: \.self) { item in
                            Label(item, systemImage: "lightbulb")
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Section {
                    Picker("运行环境", selection: $profileID) {
                        Text("自动（\(defaultProfileName)）").tag(String?.none)
                        Divider()
                        ForEach(profiles.recipes, id: \.id) { recipe in
                            Text(recipe.isUserProvided ? "\(recipe.name) · 我的" : recipe.name).tag(Optional(recipe.id))
                        }
                    }
                }

                Section("只对这个游戏生效的开关") {
                    ForEach(LaunchSwitch.all) { item in
                        // The control gets its own line: beside the label, the wider one wraps and the two rows no longer match.
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                Text(item.hint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Picker(item.name, selection: binding(for: item)) {
                                Text("自动").tag(String?.none)
                                ForEach(item.options) { option in
                                    Text(option.label).tag(Optional(option.id))
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: $showsAdvanced) {
                        TextField("自定义 DLL 设置", text: $dllText, prompt: Text("quartz=builtin; d3dx9_43=native"))
                        TextField("环境变量", text: $environmentText, prompt: Text("NAME=value; OTHER=value"))
                        TextField("启动参数", text: $argumentsText, prompt: Text("-windowed -nosound"))
                    } label: {
                        // The whole row unfolds it, not only the arrow.
                        Text("高级")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation { showsAdvanced.toggle() } }
                    }
                } footer: {
                    if showsAdvanced {
                        Text("DLL 设置和环境变量可以写多条，用分号隔开；启动参数用空格隔开。这里写的 DLL 设置会盖过上面的开关。")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 14) {
                Button("恢复默认", action: restoreDefaults)
                    .disabled(isDefault)
                Button("把当前配置导出为文件…", action: export)
                    .buttonStyle(.link)
                Spacer()
                Button("取消", role: .cancel) {
                    // Closing without saving still counts as having read the advice.
                    if seenAdvice != game.acknowledgedAdvice {
                        var seen = game
                        seen.acknowledgedAdvice = seenAdvice
                        library.updateGame(seen)
                    }
                    dismiss()
                }
                    .keyboardShortcut(.cancelAction)
                Button("完成") {
                    library.updateGame(edited)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 520)
        .alert("没能导出", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("好") {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private var defaultProfileName: String {
        var plain = game
        plain.profileID = nil
        return profiles.recipe(for: plain)?.name ?? "通用"
    }

    private var seenAdvice: [String] {
        game.acknowledgedAdvice + advice.filter { !game.acknowledgedAdvice.contains($0) }
    }

    private func binding(for item: LaunchSwitch) -> Binding<String?> {
        Binding(get: { switches[item.id] }, set: { switches[item.id] = $0 })
    }

    private var isDefault: Bool {
        profileID == nil && switches.isEmpty && [dllText, environmentText, argumentsText].allSatisfy {
            $0.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// Clears the panel only; like every other edit it is saved by 完成 and dropped by 取消.
    private func restoreDefaults() {
        profileID = nil
        switches = [:]
        dllText = ""
        environmentText = ""
        argumentsText = ""
    }

    /// The game with what the panel currently shows applied.
    private var edited: Game {
        var updated = game
        // Moving to another profile's prefix means configuring again; leave a game alone when it did not move.
        if profileID != updated.profileID {
            updated.useProfile(profileID, bottlesDirectory: library.wineManagerInstance.bottlesDirectory, profiles: profiles)
        }
        updated.launchSwitches = switches
        updated.acknowledgedAdvice = seenAdvice
        updated.bottleConfig.dllOverrides = BottleConfig.pairs(from: dllText)
        updated.bottleConfig.environment = BottleConfig.pairs(from: environmentText)
        updated.bottleConfig.launchArguments = argumentsText.split(separator: " ").map(String.init)
        return updated
    }

    private func export() {
        let edited = edited
        guard let recipe = profiles.recipe(for: edited) else { return }
        let file = edited.exportedProfile(base: recipe)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(file.id).json"
        panel.message = "放进 Gala 数据目录的 Profiles 文件夹，就会成为一个可选的运行环境。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(file).write(to: url)
        } catch {
            exportError = error.localizedDescription
        }
    }
}
