import SwiftUI
import GalaKit

/// How one game is run: its runtime profile, the named switches, and free-form overrides.
/// Edits a copy; nothing is saved until 完成.
struct RunSettingsView: View {
    let game: Game
    let library: LibraryViewModel
    /// What the profile's author and the last launch suggest; listed first, and marked as seen when the panel closes.
    let advice: [RuntimeAdvice]
    @Environment(\.dismiss) private var dismiss

    @State private var profileID: String?
    @State private var switches: [String: String]
    @State private var dllText: String
    @State private var environmentText: String
    @State private var argumentsText: String
    @State private var showsAdvanced: Bool
    @State private var exportError: String?
    @State private var showsDetail: Bool
    @State private var scrollContentHeight: CGFloat = 0

    private static let maxScrollHeight: CGFloat = 530

    private var profiles: ProfileStore { library.wineManagerInstance.profiles }

    init(game: Game, library: LibraryViewModel, advice: [RuntimeAdvice] = [], showsAdvanced: Bool = false, showsDetail: Bool = false) {
        self.game = game
        self.library = library
        self.advice = advice
        _showsDetail = State(initialValue: showsDetail)
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
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !advice.isEmpty {
                        section("建议") {
                            GalaSheetCard(tint: Color.orange.opacity(0.08)) {
                                ForEach(Array(advice.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 { GalaSheetDivider().padding(.leading, 16) }
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack(alignment: .top, spacing: 10) {
                                            Image(systemName: "lightbulb.fill")
                                                .font(.callout)
                                                .foregroundStyle(.orange)
                                                .padding(.top, 1)
                                            Text(item.message)
                                                .font(.callout)
                                                .textSelection(.enabled)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }

                                        if let action = item.action, canApply(action) {
                                            let applied = isApplied(action)
                                            HStack {
                                                Spacer()
                                                Button(applied ? "已应用" : "采纳") {
                                                    apply(action)
                                                }
                                                .galaButtonStyle()
                                                .controlSize(.small)
                                                .disabled(applied)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                            }
                        }
                    }

                    section("运行环境") {
                        GalaSheetCard {
                            HStack(spacing: 12) {
                                Text("运行环境")
                                Spacer(minLength: 12)
                                Picker("运行环境", selection: $profileID) {
                                    Text("自动（\(defaultProfileName)）").tag(String?.none)
                                    Divider()
                                    ForEach(profiles.recipes, id: \.id) { recipe in
                                        Text(recipe.isUserProvided ? "\(recipe.name) · 我的" : recipe.name).tag(Optional(recipe.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .fixedSize()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)

                            if let detail = selectedDetail {
                                GalaSheetDivider().padding(.leading, 16)
                                HStack(spacing: 12) {
                                    Text(detail.summary)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button { showsDetail = true } label: {
                                        HStack(spacing: 3) {
                                            Text("详情")
                                            Image(systemName: "chevron.right")
                                                .font(.caption2.weight(.semibold))
                                        }
                                        .font(.callout)
                                    }
                                    .galaSubtleButtonStyle()
                                    .popover(isPresented: $showsDetail, arrowEdge: .trailing) {
                                            ScrollView {
                                                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 7) {
                                                    ForEach(detail.compactRows) { row in
                                                        GridRow {
                                                            Text(row.label)
                                                                .foregroundStyle(.secondary)
                                                                .gridColumnAlignment(.trailing)
                                                            Text(row.value)
                                                                .textSelection(.enabled)
                                                                .fixedSize(horizontal: false, vertical: true)
                                                            Text(row.source.map { "来自\($0)" } ?? "")
                                                                .foregroundStyle(.tertiary)
                                                        }
                                                    }
                                                }
                                                .font(.callout)
                                                .padding(18)
                                            }
                                            .galaOverlayScrollbars()
                                            .frame(width: 400)
                                            .frame(maxHeight: 360)
                                            .fixedSize(horizontal: false, vertical: true)
                                        }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                        }
                    }

                    section("只对这个游戏生效的开关") {
                        GalaSheetCard {
                            ForEach(Array(LaunchSwitch.all.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { GalaSheetDivider().padding(.leading, 16) }
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                        Text(item.hint)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 12)
                                    Picker(item.name, selection: binding(for: item)) {
                                        Text("自动").tag(String?.none)
                                        ForEach(item.options) { option in
                                            Text(option.label).tag(Optional(option.id))
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                    .fixedSize()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        GalaSheetCard {
                            Button {
                                withAnimation(.easeOut(duration: 0.16)) { showsAdvanced.toggle() }
                            } label: {
                                HStack {
                                    Text("高级")
                                        .fontWeight(.medium)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .rotationEffect(.degrees(showsAdvanced ? 90 : 0))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if showsAdvanced {
                                GalaSheetDivider().padding(.leading, 16)
                                advancedField("自定义 DLL 设置", text: $dllText, prompt: "quartz=builtin; d3dx9_43=native")
                                GalaSheetDivider().padding(.leading, 16)
                                advancedField("环境变量", text: $environmentText, prompt: "NAME=value; OTHER=value")
                                GalaSheetDivider().padding(.leading, 16)
                                advancedField("启动参数", text: $argumentsText, prompt: "-windowed -nosound")
                            }
                        }

                        if showsAdvanced {
                            Text("DLL 设置和环境变量可以写多条，用分号隔开；启动参数用空格隔开。这里写的 DLL 设置会盖过上面的开关。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 2)
                .padding(.bottom, 18)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: ScrollContentHeightKey.self, value: proxy.size.height)
                    }
                }
            }
            .galaOverlayScrollbars()
            .scrollDisabled(scrollContentHeight > 0 && scrollContentHeight <= Self.maxScrollHeight)
            .defaultScrollAnchor(.top)
            .frame(height: min(scrollContentHeight > 0 ? ceil(scrollContentHeight) : 440, Self.maxScrollHeight))
            .onPreferenceChange(ScrollContentHeightKey.self) { scrollContentHeight = $0 }

            GalaSheetDivider()

            HStack(spacing: 10) {
                Button("恢复默认", action: restoreDefaults)
                    .galaButtonStyle()
                    .disabled(isDefault)
                Button("导出为文件…", action: export)
                    .galaSubtleButtonStyle()
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
                .galaButtonStyle()
                .keyboardShortcut(.cancelAction)
                Button("完成") {
                    library.updateGame(edited)
                    dismiss()
                }
                .galaButtonStyle(prominent: true)
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

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            content()
        }
    }

    private func advancedField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 108, alignment: .leading)
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(.tertiary))
                .textFieldStyle(.plain)
                .font(.system(.callout, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    /// The environment the panel currently points at, laid out line by line.
    private var selectedDetail: ProfileDetail? {
        var picked = game
        picked.profileID = profileID
        return profiles.recipe(for: picked).map(profiles.detail(of:))
    }

    private var defaultProfileName: String {
        var plain = game
        plain.profileID = nil
        return profiles.recipe(for: plain)?.name ?? "通用"
    }

    private var seenAdvice: [String] {
        game.acknowledgedAdvice + advice.map(\.message).filter { !game.acknowledgedAdvice.contains($0) }
    }

    private func canApply(_ action: RuntimeAdvice.Action) -> Bool {
        action.profileID.map { profiles.recipe(id: $0) != nil } ?? true
    }

    private func isApplied(_ action: RuntimeAdvice.Action) -> Bool {
        if let targetProfile = action.profileID, profileID != targetProfile {
            return false
        }
        for (key, value) in action.launchSwitches where switches[key] != value {
            return false
        }
        if !action.dllOverrides.isEmpty {
            let current = BottleConfig.pairs(from: dllText)
            for (dll, mode) in action.dllOverrides {
                let matched = current.first { $0.key.caseInsensitiveCompare(dll) == .orderedSame }?.value
                if matched != mode { return false }
            }
        }
        return true
    }

    private func apply(_ action: RuntimeAdvice.Action) {
        if let targetProfile = action.profileID, profiles.recipe(id: targetProfile) != nil {
            profileID = targetProfile
        }
        for (key, value) in action.launchSwitches {
            switches[key] = value
        }
        if !action.dllOverrides.isEmpty {
            var pairs = BottleConfig.pairs(from: dllText)
            for (dll, mode) in action.dllOverrides {
                for existing in pairs.keys where existing.caseInsensitiveCompare(dll) == .orderedSame {
                    pairs.removeValue(forKey: existing)
                }
                pairs[dll] = mode
            }
            dllText = BottleConfig.text(from: pairs)
            showsAdvanced = true
        }
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

private struct ScrollContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
