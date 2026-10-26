import AppKit
import Sauce
import SwiftUI

enum SnippetsEditorCommand {
  case copy
  case paste
  case duplicate
}

extension Notification.Name {
  static let snippetsEditorCommand = Notification.Name("SnippetsEditorCommand")
}

// Separate window for managing snippets.
// Based on snippets editor in https://github.com/Clipy/Clipy.
@MainActor
class SnippetsEditorWindowController: NSObject {
  static let shared = SnippetsEditorWindowController()

  private var window: NSWindow?
  private var keyMonitor: Any?

  func show() {
    let window = window ?? makeWindow()
    self.window = window
    installKeyMonitor()

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 780, height: 500),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = NSLocalizedString("snippets_editor_title", comment: "")
    window.titlebarAppearsTransparent = true
    window.titlebarSeparatorStyle = .none
    // Let the glass background show through like in the popup.
    window.isOpaque = false
    window.backgroundColor = .clear
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: 620, height: 380)
    window.contentView = NSHostingView(rootView: SnippetsEditorView().environment(AppState.shared))
    window.center()
    window.setFrameAutosaveName("SnippetsEditor")

    return window
  }

  // Maccy has no Edit menu, so ⌘C, ⌘V and ⌘D never reach the snippets list on their own.
  // Text fields keep handling them to copy and paste text.
  private func installKeyMonitor() {
    guard keyMonitor == nil else { return }

    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handleKeyDown)
  }

  private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    guard let command = command(for: event) else { return event }

    NotificationCenter.default.post(name: .snippetsEditorCommand, object: command)
    return nil
  }

  private func command(for event: NSEvent) -> SnippetsEditorCommand? {
    guard let window, event.window === window, !(window.firstResponder is NSText),
          event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else { return nil }

    switch Sauce.shared.key(for: Int(event.keyCode)) {
    case .c:
      return .copy
    case .v:
      return .paste
    case .d:
      return .duplicate
    default:
      return nil
    }
  }
}
