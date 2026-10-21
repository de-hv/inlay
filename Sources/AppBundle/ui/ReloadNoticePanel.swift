import AppKit
import Common
import SwiftUI

/// What the notice of a reload of the config says. Pure. See: ReloadNoticePanel, 'notifications.on-reload'
struct ReloadNotice: Equatable {
    var fileName: String
    /// The keys that changed, with the 'diff' style. Empty: only comments or formatting changed.
    /// nil: the style is 'simple', or there is nothing to compare with
    var changes: [ConfigChange]?
    var warningCount: Int

    static let maxShownChanges = 4

    /// nil: no notice, with the 'off' style
    /// - Parameter oldText: the text of the config that was applied before this one
    init?(style: ReloadNoticeStyle, fileName: String, oldText: String?, newText: String?, warningCount: Int) {
        if style == .off { return nil }
        self.fileName = fileName
        self.warningCount = warningCount
        changes = switch style {
            case .diff: oldText.flatMap { old in newText.flatMap { ConfigDiff.changes(from: old, to: $0) } }
            case .simple, .off: nil
        }
    }

    var shownChanges: [ConfigChange] { Array((changes ?? []).prefix(Self.maxShownChanges)) }
    var hiddenChangeCount: Int { max(0, (changes?.count ?? 0) - Self.maxShownChanges) }
    /// How long it stays on the screen. With warnings, long enough to read that there are some
    var duration: Duration { warningCount > 0 ? .seconds(6) : .milliseconds(2500) }
}

/// The notice in the top right corner of the screen of the focus, for a moment, after the config is reloaded.
/// It never takes the focus. The mouse over it keeps it, and a click dismisses it
@MainActor
final class ReloadNoticePanel: NSPanelHud {
    static let shared = ReloadNoticePanel()

    private var hideTask: Task<Void, Never>?
    private let margin: CGFloat = 12
    /// After the mouse leaves the notice
    private let lingerAfterHover: Duration = .milliseconds(1500)

    override private init() {
        super.init()
    }

    func show(_ notice: ReloadNotice) {
        if isUnitTest { return } // The tests must not open windows
        let view = NSHostingView(rootView: ReloadNoticeView(
            notice: notice,
            onHover: { [weak self] in self?.hover($0) },
            onTap: { [weak self] in self?.dismiss() },
        ))
        contentView = view
        guard let screen = screenOfFocus else { return }
        let size = view.fittingSize
        let visible = screen.visibleFrame
        setFrame(
            NSRect(x: visible.maxX - size.width - margin, y: visible.maxY - size.height - margin, width: size.width, height: size.height),
            display: true,
        )
        if !isVisible { alphaValue = 0 }
        orderFrontRegardless()
        fade(to: 1)
        scheduleHide(after: notice.duration)
    }

    private var screenOfFocus: NSScreen? {
        let screens = NSScreen.screens
        let index = focus.workspace.workspaceMonitor.monitorAppKitNsScreenScreensId - 1
        return screens.indices.contains(index) ? screens[index] : screens.first
    }

    private func hover(_ isInside: Bool) {
        if isInside {
            hideTask?.cancel()
        } else {
            scheduleHide(after: lingerAfterHover)
        }
    }

    private func scheduleHide(after delay: Duration) {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            if Task.isCancelled { return }
            self?.dismiss()
        }
    }

    private func dismiss() {
        hideTask?.cancel()
        fade(to: 0) { [weak self] in
            if self?.alphaValue == 0 { self?.orderOut(nil) }
        }
    }

    private func fade(to alpha: CGFloat, completion: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
            animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }
}

private struct ReloadNoticeView: View {
    let notice: ReloadNotice
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: notice.warningCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(notice.warningCount > 0 ? Color.orange : Color.green)
                Text(Strings.Notice.reloaded(notice.fileName))
                    .font(.system(size: 13, weight: .semibold))
            }
            if let changes = notice.changes {
                if changes.isEmpty {
                    Text(Strings.Notice.noChanges).foregroundStyle(.secondary)
                }
                ForEach(Array(notice.shownChanges.enumerated()), id: \.offset) { _, change in
                    row(change)
                }
                if notice.hiddenChangeCount > 0 {
                    Text(Strings.Notice.more(notice.hiddenChangeCount)).foregroundStyle(.secondary)
                }
            }
            if notice.warningCount > 0 {
                Text(Strings.Notice.warnings(notice.warningCount)).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(width: 340, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .onTapGesture(perform: onTap)
    }

    /// 'borders.width   4 → 8'
    private func row(_ change: ConfigChange) -> some View {
        HStack(spacing: 10) {
            Text(change.key)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text(value(change))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
        }
        .font(.system(size: 11.5, design: .monospaced))
    }

    private func value(_ change: ConfigChange) -> String {
        switch (change.old, change.new) {
            case (let old?, let new?): "\(old) → \(new)"
            case (nil, let new?): "\(Strings.Notice.added): \(new)"
            case (_, nil): Strings.Notice.removed
        }
    }
}
