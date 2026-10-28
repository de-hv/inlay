import Common
import SwiftUI

/// The content of the menu of the menu bar item. See: MenuBarPanelContent, MenuBarMenu
///
/// The selected layout and the hovered buttons take the accent color of the system: there is nothing to configure
struct MenuBarPanelView: View {
    let content: MenuBarPanelContent
    let run: (MenuBarCardAction) -> Void

    static let width: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let problems = content.problems { problemsBox(problems) }
            if let prompt = content.prompt {
                Button { run(prompt) } label: {
                    Text(Strings.Menu.grantAccessibility).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            if content.showsLayouts {
                section(Strings.Menu.window) {
                    ForEach(MenuBarCard.WindowLayout.allCases, id: \.self) { layout in
                        MenuBarLayoutButton(
                            glyph: .window(layout),
                            title: Strings.Menu.layoutShort(layout),
                            accessibilityLabel: Strings.Menu.layout(layout),
                            isSelected: content.windowLayout == layout,
                            isEnabled: content.canSetLayout,
                        ) { run(.setLayout(layout)) }
                    }
                }
                section(Strings.Menu.arrangeWorkspace) {
                    ForEach(WorkspaceArrangement.allCases, id: \.self) { arrangement in
                        MenuBarLayoutButton(
                            glyph: .arrangement(arrangement),
                            title: Strings.Menu.arrangeShort(arrangement),
                            accessibilityLabel: Strings.Menu.arrange(arrangement),
                            isSelected: false,
                            isEnabled: content.canArrange,
                        ) { run(.arrange(arrangement)) }
                    }
                }
            }
            Divider()
            footer
        }
        .padding(12)
        .frame(width: Self.width)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(content.title).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            ForEach(content.details, id: \.self) { detail in
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func problemsBox(_ problems: MenuBarPanelContent.Problems) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { run(.showConfigProblems) } label: {
                Label(problems.title, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            ForEach(problems.lines, id: \.self) { line in
                Text(line).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    private func section(_ title: String, @ViewBuilder buttons: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) { buttons() }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            ForEach(content.footer, id: \.action) { button in
                MenuBarIconButton(button: button) { run(button.action) }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A layout of the focused window, or an arrangement of its workspace: a drawing of it and its name
private struct MenuBarLayoutButton: View {
    let glyph: MenuBarLayoutGlyph.Kind
    let title: String
    let accessibilityLabel: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void
    @StateObject private var hover = MenuBarHover()
    private var isHovered: Bool { hover.isHovered }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                MenuBarLayoutGlyph(kind: glyph).frame(width: 30, height: 20)
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 9).fill(background))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hover.isHovered = $0 }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected { return .accentColor }
        return isHovered && isEnabled ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)
    }
}

/// One of the buttons at the bottom of the menu: an SF Symbol, with its title and its shortcut as the tooltip
private struct MenuBarIconButton: View {
    let button: MenuBarPanelContent.Button
    let action: () -> Void
    @StateObject private var hover = MenuBarHover()
    private var isHovered: Bool { hover.isHovered }

    var body: some View {
        Button(action: action) {
            Image(systemName: button.symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 44, height: 30)
                .foregroundStyle(isHovered && button.isEnabled ? Color.white : Color.primary)
                .background(RoundedRectangle(cornerRadius: 8).fill(isHovered && button.isEnabled ? Color.accentColor : Color.clear))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!button.isEnabled)
        .opacity(button.isEnabled ? 1 : 0.4)
        .onHover { hover.isHovered = $0 }
        .help(button.action.shortcut.map { "\(button.title)  ⌘\($0.uppercased())" } ?? button.title)
        .accessibilityLabel(button.title)
    }
}

// Used instead of @State: in the macOS 27 SDK @State is a macro whose plugin only ships with Xcode, and Inlay must
// build with the Command Line Tools alone. See: SecureInputViewModel
private final class MenuBarHover: ObservableObject {
    @Published var isHovered = false
}

/// The drawing of a layout: the windows as tiles, in the color of the text
struct MenuBarLayoutGlyph: View {
    enum Kind: Equatable {
        case window(MenuBarCard.WindowLayout)
        case arrangement(WorkspaceArrangement)
    }

    let kind: Kind

    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 2
            let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 0.75, dy: 0.75)
            func tile(_ rect: CGRect) {
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .foreground)
            }
            func columns(_ rect: CGRect, _ count: Int) -> [CGRect] {
                let width = (rect.width - CGFloat(count - 1) * gap) / CGFloat(count)
                return (0 ..< count).map { CGRect(x: rect.minX + CGFloat($0) * (width + gap), y: rect.minY, width: width, height: rect.height) }
            }
            func rows(_ rect: CGRect, _ count: Int) -> [CGRect] {
                let height = (rect.height - CGFloat(count - 1) * gap) / CGFloat(count)
                return (0 ..< count).map { CGRect(x: rect.minX, y: rect.minY + CGFloat($0) * (height + gap), width: rect.width, height: height) }
            }
            switch kind {
                case .window(.tiling):
                    columns(bounds, 2).forEach(tile)
                case .window(.floating):
                    // The screen as an outline, and a window in the middle of it
                    context.stroke(Path(roundedRect: bounds, cornerRadius: 2.5), with: .foreground, style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2]))
                    tile(bounds.insetBy(dx: bounds.width * 0.22, dy: bounds.height * 0.24))
                case .window(.fullscreen):
                    tile(bounds)
                case .arrangement(.dwindle):
                    let halves = columns(bounds, 2)
                    tile(halves[0])
                    let right = rows(halves[1], 2)
                    tile(right[0])
                    columns(right[1], 2).forEach(tile)
                case .arrangement(.grid):
                    rows(bounds, 2).flatMap { columns($0, 2) }.forEach(tile)
                case .arrangement(.row):
                    columns(bounds, 3).forEach(tile)
            }
        }
        .accessibilityHidden(true)
    }
}
