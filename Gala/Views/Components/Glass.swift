import SwiftUI

/// The numbers behind the artwork-derived backdrops, in one place so they are easy to tune.
enum Ambient {
    // Cover wall, dark appearance: the artwork stays recognisable under a dark veil.
    static let wallDarkBlur: CGFloat = 60
    static let wallDarkSaturation = 1.5
    static let wallDarkVeil = Color.black.opacity(0.62)
    // Cover wall, light appearance: hues are merged and muted so they never compete with the covers.
    static let wallLightBlur: CGFloat = 110
    static let wallLightSaturation = 0.5
    static let wallLightBase = Color(red: 238 / 255, green: 239 / 255, blue: 243 / 255)
    static let wallLightVeilOpacity = 0.8
    // Detail page: always dark and immersive, whatever the system appearance.
    static let detailBlur: CGFloat = 50
    static let detailSaturation = 1.25
    static let detailVeil = LinearGradient(
        colors: [.black.opacity(0.4), .black.opacity(0.6)],
        startPoint: .top,
        endPoint: .bottom
    )
}

/// A blurred piece of cover art filling the window behind the content.
struct AmbientBackground: View {
    enum Style { case wall, detail }

    let image: NSImage?
    let style: Style

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = style == .detail || colorScheme == .dark
        ZStack {
            dark ? Color(white: 0.12) : Ambient.wallLightBase
            if let image {
                Color.clear
                    .overlay {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .saturation(saturation(dark: dark))
                            .blur(radius: blur(dark: dark), opaque: true)
                    }
                    .clipped()
            }
            veil(dark: dark)
        }
        .ignoresSafeArea()
    }

    private func blur(dark: Bool) -> CGFloat {
        switch style {
        case .detail: return Ambient.detailBlur
        case .wall: return dark ? Ambient.wallDarkBlur : Ambient.wallLightBlur
        }
    }

    private func saturation(dark: Bool) -> Double {
        switch style {
        case .detail: return Ambient.detailSaturation
        case .wall: return dark ? Ambient.wallDarkSaturation : Ambient.wallLightSaturation
        }
    }

    @ViewBuilder
    private func veil(dark: Bool) -> some View {
        switch style {
        case .detail: Ambient.detailVeil
        case .wall: dark ? Ambient.wallDarkVeil : Ambient.wallLightBase.opacity(Ambient.wallLightVeilOpacity)
        }
    }
}

extension View {
    /// System glass on macOS 26 and later, an ordinary material on older systems.
    @ViewBuilder
    func galaGlass(in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    /// Glass buttons on macOS 26 and later; bordered buttons on older systems where prominent keeps the accent fill.
    @ViewBuilder
    func galaButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glass)
                    .fontWeight(.semibold)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
    }

    /// Quiet inline text action that gains a soft capsule highlight on hover, without bright hyperlink blue.
    func galaSubtleButtonStyle() -> some View {
        buttonStyle(GalaSubtleButtonStyle())
    }

    /// Hides the window title so only toolbar controls sit above the content.
    @ViewBuilder
    func hidingWindowTitle() -> some View {
        if #available(macOS 15.0, *) {
            toolbar(removing: .title)
        } else {
            self
        }
    }

    /// Forces macOS's slim floating overlay scrollbars even when an external mouse selects legacy bars.
    func galaOverlayScrollbars() -> some View {
        background(OverlayScrollbarEnforcer())
    }
}

private struct OverlayScrollbarEnforcer: NSViewRepresentable {
    func makeNSView(context: Context) -> EnforcerView { EnforcerView() }
    func updateNSView(_ view: EnforcerView, context: Context) { view.applySoon() }

    final class EnforcerView: NSView {
        private var observer: NSObjectProtocol?

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            apply()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if observer == nil {
                observer = NotificationCenter.default.addObserver(
                    forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.applySoon()
                }
            }
            applySoon()
        }

        override func viewWillDraw() {
            super.viewWillDraw()
            apply()
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        func applySoon() {
            apply()
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        private func apply() {
            if let scrollView = enclosingScrollView, scrollView.scrollerStyle != .overlay {
                scrollView.scrollerStyle = .overlay
            }
            if let root = window?.contentView {
                applyRecursively(to: root)
            }
        }

        private func applyRecursively(to view: NSView) {
            if let scrollView = view as? NSScrollView, scrollView.scrollerStyle != .overlay {
                scrollView.scrollerStyle = .overlay
            }
            for subview in view.subviews {
                applyRecursively(to: subview)
            }
        }
    }
}

/// Subtle translucent card for sheet sections, matching the detail page's glass language without harsh form chrome.
struct GalaSheetCard<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape.fill(tint ?? Color.primary.opacity(0.055))
        }
        .overlay {
            shape.strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
        }
    }
}

/// Hairline separator used inside and around glass sheet sections.
struct GalaSheetDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.09))
            .frame(height: 0.5)
    }
}

private struct GalaSubtleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SubtleButtonLabel(configuration: configuration)
    }

    private struct SubtleButtonLabel: View {
        let configuration: Configuration
        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(isHovering || configuration.isPressed ? Color.primary : Color.primary.opacity(0.72))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Color.primary.opacity(configuration.isPressed ? 0.14 : (isHovering ? 0.08 : 0)),
                    in: Capsule()
                )
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.14), value: isHovering)
        }
    }
}

/// A game's cover, or a tinted placeholder carrying its title when there is none.
struct CoverArt: View {
    let title: String
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Color.clear.overlay {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                }
            } else {
                LinearGradient(
                    colors: [.purple.opacity(0.55), .blue.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(alignment: .bottomLeading) {
                    Text(title)
                        .font(.system(.callout, design: .serif).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .padding(12)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

enum PlayTime {
    static func text(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        if minutes > 0 { return "\(minutes) 分钟" }
        return "未游玩"
    }
}
