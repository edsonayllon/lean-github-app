import AppKit
import SwiftUI

extension Color {
    /// A colour that follows the system appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255,
                alpha: 1
            )
        })
    }
}

/// One palette, one radius family and one spacing scale (multiples of 4) for the whole app.
enum Theme {
    static let background = Color(light: 0xffffff, dark: 0x0f1318)
    static let sidebar = Color(light: 0xf6f8fa, dark: 0x151a21)
    static let card = Color(light: 0xf6f8fa, dark: 0x151a21)
    static let border = Color(light: 0xd1d9e0, dark: 0x2a313c)
    static let hover = Color(light: 0xeaeef2, dark: 0x1c222b)
    static let selected = Color(light: 0xdde3ea, dark: 0x262d38)

    static let text = Color(light: 0x1f2328, dark: 0xe6edf3)
    static let secondary = Color(light: 0x59636e, dark: 0x9198a1)
    static let tertiary = Color(light: 0x818b98, dark: 0x656c76)

    static let link = Color(light: 0x0969da, dark: 0x4493f8)
    static let primary = Color(light: 0x0969da, dark: 0x1f6feb)
    static let primaryPressed = Color(light: 0x0757b5, dark: 0x1a5fcc)
    static let attention = Color(light: 0x9a6700, dark: 0xd29922)

    static let radius: CGFloat = 8
    static let cardRadius: CGFloat = 12
}

// MARK: Buttons

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    struct Styled: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background(configuration.isPressed ? Theme.primaryPressed : Theme.primary,
                            in: RoundedRectangle(cornerRadius: Theme.radius))
                .opacity(enabled ? 1 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    struct Styled: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .frame(minWidth: 32, minHeight: 32, maxHeight: 32)
                .background(configuration.isPressed ? Theme.selected : (hovering ? Theme.hover : .clear),
                            in: RoundedRectangle(cornerRadius: Theme.radius))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
                .opacity(enabled ? 1 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
                .onHover { hovering = $0 }
        }
    }
}

/// A borderless icon button, as in the sidebar's section headers and footer.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    struct Styled: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

// MARK: Surfaces

extension View {
    /// A hairline-bordered card.
    func card() -> some View {
        background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
    }

    /// A text field drawn in the app's own style.
    func field() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
    }
}

/// A sidebar row: icon, title, optional trailing text; subtle rounded highlight.
struct SidebarRow: View {
    let icon: String
    var iconColor: Color = .secondary
    let title: String
    var trailing: String?
    var selected = false

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(iconColor)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        // Translucent, so the highlight works on the glass sidebar as well as on flat surfaces.
        .background(Color.primary.opacity(selected ? 0.12 : (hovering ? 0.06 : 0)),
                    in: RoundedRectangle(cornerRadius: Theme.radius))
        .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        .onHover { hovering = $0 }
    }
}

/// Lets the window be dragged from any empty area, not only the thin strip at the top.
struct WindowDragEnabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.isMovableByWindowBackground = true }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.window?.isMovableByWindowBackground = true
    }
}
