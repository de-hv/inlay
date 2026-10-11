import AppKit
import Combine
import Common
import SwiftUI

/// Shows the diagnostics of the config (see: reloadConfig_nonCancellable) in a window, for as long as `MessageModel` has a message.
///
/// Inlay has no Dock icon and is never the active app on its own, so the window floats and is brought forward by hand
@MainActor
final class MessageWindowController: NSObject, NSWindowDelegate {
    static let shared = MessageWindowController()

    private var window: NSWindow?
    private var subscription: AnyCancellable?

    override private init() {}

    /// It must be called once, after the app has finished launching
    func start() {
        // The publisher fires before the property changes, that's why the new value is passed along
        subscription = MessageModel.shared.$message.sink { [weak self] message in
            Task { @MainActor in self?.sync(message) }
        }
    }

    private func sync(_ message: Message?) {
        guard let message else {
            window?.close()
            return
        }
        let window = window ?? makeWindow()
        self.window = window
        window.title = message.title
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: MessageView(model: MessageModel.shared)))
        // No minimize button, because the window isn't unminimized on a config error
        window.styleMask = [.titled, .closable, .resizable]
        window.identifier = NSUserInterfaceItemIdentifier(messageWindowId)
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 720, height: 420))
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // If the user closes the window and then the error is still the same, the window must appear again
        if MessageModel.shared.message != nil { MessageModel.shared.message = nil }
    }
}

public let messageWindowId = "\(inlayAppName).messageView"

struct MessageView: View {
    @StateObject private var model: MessageModel
    @FocusState var focus: Bool

    init(model: MessageModel) {
        self._model = .init(wrappedValue: model)
    }

    public var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .center) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 48))
                Text("\(model.message?.description ?? "")")
                    .padding(.horizontal)
                    .focusable()
            }
            .padding()
            ScrollView {
                VStack(alignment: .leading) {
                    HStack {
                        let cancelOnEnterBinding: Binding<String> = Binding(
                            get: { model.message?.body ?? "" },
                            set: { newText in
                                if let prev = model.message?.body.count(where: \.isNewline), newText.count(where: \.isNewline) > prev {
                                    model.message = nil
                                }
                            },
                        )
                        TextEditor(text: cancelOnEnterBinding)
                            .font(.system(size: 12).monospaced())
                            .focused($focus)
                        //  .onKeyPress(.return) { return .handled } // enter handling alternative. Only available since macOS 14
                        Spacer()
                    }
                    Spacer()
                }
                .padding()
            }
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal)
            HStack {
                Spacer()
                if let type = model.message?.type {
                    switch type {
                        case .config:
                            reloadConfigButton(showShortcutGroup: true, warningsAsErrors: model.message?.containsWarnings == true)
                            openConfigButton(showShortcutGroup: true)
                    }
                }
                let closeButton = Button("Close") { model.message = nil }.keyboardShortcut(.defaultAction)
                shortcutGroup(label: Image(systemName: "return.left"), content: closeButton)
            }
            .padding()
        }
        .textSelection(.enabled)
        .frame(minWidth: 480, maxWidth: 960, minHeight: 200)
        .onAppear {
            focus = true
        }
    }
}

public final class MessageModel: ObservableObject {
    @MainActor public static let shared = MessageModel()
    @Published public var message: Message? = nil

    private init() {}
}

public enum MessageType {
    case config
}

public struct Message: Hashable, Equatable {
    public let type: MessageType
    public let title: String
    public let description: String
    public let body: String
    public let containsWarnings: Bool

    init(
        type: MessageType = .config,
        title: String = inlayAppName,
        description: String = "Inlay Config Diagnostics",
        body: String,
        containsWarnings: Bool,
    ) {
        self.type = type
        self.title = title
        self.description = description
        self.body = body
        self.containsWarnings = containsWarnings
    }
}

@MainActor @ViewBuilder
func openConfigButton(showShortcutGroup: Bool = false) -> some View {
    let editor = getTextEditorToOpenConfig()
    let button = Button("Open config in '\(editor.lastPathComponent)'") { openConfigInEditor() }
        .keyboardShortcut(",", modifiers: .command)
    switch showShortcutGroup {
        case true: shortcutGroup(label: Text("⌘ ,"), content: button)
        case false: button
    }
}

@MainActor @ViewBuilder
func reloadConfigButton(showShortcutGroup: Bool = false, warningsAsErrors: Bool) -> some View {
    if RunSessionGuard.isServerEnabled != nil {
        let button = Button("Reload config") { reloadConfigFromUi(warningsAsErrors: warningsAsErrors) }
            .keyboardShortcut("R", modifiers: .command)
        switch showShortcutGroup {
            case true: shortcutGroup(label: Text("⌘ R"), content: button)
            case false: button
        }
    }
}

func shortcutGroup(label: some View, content: some View) -> some View {
    GroupBox {
        VStack(alignment: .trailing, spacing: 6) {
            label
                .foregroundStyle(Color.secondary)
            content
        }
    }
}
