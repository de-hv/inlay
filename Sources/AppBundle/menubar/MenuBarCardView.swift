import AppKit
import Common
import SwiftUI

/// The button under the mouse, in the card of the menu. An observable object rather than @State: the macro of
/// @State only ships with Xcode, and Inlay builds with the Command Line Tools alone
@MainActor
@Observable
final class MenuBarCardHover {
    var action: MenuBarCardAction? = nil
}

/// The card of the menu: the state of Inlay, the windows of the focused workspace, the switch of the focused window,
/// a row of buttons, the version and Quit. The menu draws the material behind it, so it follows light and dark by itself
struct MenuBarCardView: View {
    let card: MenuBarCard
    let select: (MenuBarCardAction) -> Void
    let hover = MenuBarCardHover()

    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    static let width: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if card.configProblems != nil { warning(.showConfigProblems, symbol: "exclamationmark.triangle.fill") }
            switch card.status {
                case .needsAccessibility: warning(.promptForAccessibility, symbol: "exclamationmark.triangle")
                case .paused: EmptyView()
                case .running:
                    windows
                    floating
            }
            if !card.buttons.isEmpty { buttons }
            footer
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: Self.width, alignment: .leading)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            Text(inlayAppName).font(.system(size: 14, weight: .bold))
            Spacer(minLength: 8)
            status
        }
    }

    private var status: some View {
        let (title, color): (String, NSColor) = switch card.status {
            case .running: (Strings.Menu.Status.running, .systemGreen)
            case .paused: (Strings.Menu.Status.paused, .systemGray)
            case .needsAccessibility: (Strings.Menu.Status.needsAccessibility, .systemOrange)
        }
        return HStack(spacing: 6) {
            Circle().fill(Color(nsColor: color)).frame(width: 6, height: 6)
            Text(title).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color(nsColor: color))
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color(nsColor: color).opacity(0.16)))
        .accessibilityElement(children: .combine)
    }

    /// The windows, by the name of their app. Not buttons: the menu doesn't focus windows
    private var windows: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Strings.Menu.workspace(card.workspace))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            if card.windows.isEmpty {
                Text(Strings.Menu.noWindows)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            ForEach(Array(card.windows.enumerated()), id: \.offset) { _, window in
                HStack(spacing: 8) {
                    Circle()
                        .fill(window.isFocused ? accent : .clear)
                        .frame(width: 6, height: 6)
                    Text(window.app)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(window.isFocused ? .isSelected : [])
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(blockFill))
    }

    private var floating: some View {
        let isOn = card.isFloating == true
        return Button { select(.toggleFloating) } label: {
            HStack(spacing: 10) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 14))
                    .frame(width: 18)
                Text(Strings.Menu.floating).font(.system(size: 13))
                Spacer(minLength: 8)
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule().fill(isOn ? accent : Color.primary.opacity(0.14))
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                        .padding(2)
                }
                .frame(width: 34, height: 20)
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!card.isEnabled(.toggleFloating))
        .accessibilityLabel(Strings.Menu.floating)
        .accessibilityValue(isOn ? Strings.Menu.on : Strings.Menu.off)
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            ForEach(card.buttons, id: \.self) { action in
                tile(action)
            }
        }
    }

    private func tile(_ action: MenuBarCardAction) -> some View {
        let isHovered = hover.action == action && card.isEnabled(action)
        return Button { select(action) } label: {
            VStack(spacing: 4) {
                // One height for all the symbols, so the labels line up
                Image(systemName: symbol(action)).font(.system(size: 15, weight: .medium)).frame(height: 18)
                Text(label(action)).font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 9)
            .padding(.bottom, 7)
            .background(RoundedRectangle(cornerRadius: 12).fill(isHovered ? hoverFill : blockFill))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!card.isEnabled(action))
        .onHover { hover.action = $0 ? action : nil }
        .help(action.title(card))
        .accessibilityLabel(action.title(card))
    }

    private var footer: some View {
        HStack {
            Button(Strings.Menu.version) { select(.copyVersion) }
                .help(Strings.Menu.copyVersionToolTip)
            Spacer(minLength: 8)
            Button { select(.quit) } label: {
                Text("\(Strings.Menu.Tile.quit)  ⌘Q")
            }
            .accessibilityLabel(Strings.Menu.quit)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    /// A row that stands out, for what needs to be dealt with first
    private func warning(_ action: MenuBarCardAction, symbol: String) -> some View {
        Button { select(action) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol).foregroundStyle(Color(nsColor: .systemOrange))
                Text(action.title(card))
                    .font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .systemOrange).opacity(0.14)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Looks

    private var accent: Color { Color(nsColor: card.accent.nsColor) }

    /// The blocks over the material of the menu: lighter than it, in light and in dark
    private var blockFill: Color { colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.6) }

    private var hoverFill: Color { colorScheme == .dark ? .white.opacity(0.16) : .white.opacity(0.95) }

    private func symbol(_ action: MenuBarCardAction) -> String {
        switch action {
            case .reloadConfig: "arrow.clockwise"
            case .openConfig: "doc.text"
            case .togglePause: card.status == .paused ? "play" : "pause"
            case .openSettings: "slider.horizontal.3"
            default: ""
        }
    }

    private func label(_ action: MenuBarCardAction) -> String {
        switch action {
            case .reloadConfig: Strings.Menu.Tile.reload
            case .openConfig: Strings.Menu.Tile.config
            case .togglePause: card.status == .paused ? Strings.Menu.Tile.resume : Strings.Menu.Tile.pause
            case .openSettings: Strings.Menu.Tile.settings
            default: action.title(card)
        }
    }
}
