import AppKit.NSRunningApplication
import Defaults
import KeyboardShortcuts
import Observation
import SwiftUI

enum PopupState {
  // Default; shortcut will toggle the popup
  case toggle
  // In this mode, every additional press of the main key
  // will cycle to the next item in the paste history list.
  // Releasing the modifier keys will accept selection and close the popup
  case cycle
  // Transition state when the shortcut is first pressed and
  // we don't know whether we are in "toggle" or "cycle" mode.
  case opening
}

// Which part of the popup is shown, chosen by the shortcut that opened it.
enum PopupMode {
  // History, snippets and actions
  case all
  // Only snippet folders
  case snippets
  // Only history items, without snippets and actions
  case history

  var shortcutName: KeyboardShortcuts.Name {
    switch self {
    case .all: return .popup
    case .snippets: return .popupSnippets
    case .history: return .popupHistory
    }
  }
}

@Observable
class Popup {
  static let verticalSeparatorPadding = 6.0
  static let horizontalSeparatorPadding = 6.0
  static let verticalPadding: CGFloat = 5
  static let horizontalPadding: CGFloat = 5
  static let minimumPreviewHeight: CGFloat = 150

  // Radius used for items inset by the padding. Ensures they visually have the same curvature
  // as the menu.
  static let cornerRadius: CGFloat = if #available(macOS 26.0, *) {
    7
  } else {
    4
  }

  static let itemHeight: CGFloat = if #available(macOS 26.0, *) {
    24
  } else {
    22
  }

  var needsResize = false {
    didSet {
      if needsResize {
        resizeRequest += 1
      }
    }
  }
  // Changes on every request, so that a repeated request still triggers a resize.
  private(set) var resizeRequest = 0
  var mode: PopupMode = .all {
    didSet {
      if mode != oldValue {
        needsResize = true
      }
    }
  }
  var height: CGFloat = 0
  // Snippets and history modes open hidden until the popup is resized to
  // their items, so that the hidden parts don't visibly collapse.
  private(set) var isRevealPending = false
  private var revealTask: Task<Void, Never>?
  private var animatesResize = true
  private var lastOpenedMode: PopupMode = .all
  var headerHeight: CGFloat = 0
  var extraTopHeight: CGFloat = 0
  var extraBottomHeight: CGFloat = 0
  var footerHeight: CGFloat = 0

  var minimumHeight: CGFloat {
    // Snippets mode has no history list
    guard mode != .snippets else { return suitableHeight(for: 0) }

    // Reserve space for 3 items
    return suitableHeight(for: 3 * Popup.itemHeight)
  }

  private var eventsMonitor: Any?

  private var state: PopupState = .toggle

  init() {
    for mode in [PopupMode.all, .snippets, .history] {
      KeyboardShortcuts.onKeyDown(for: mode.shortcutName) { [weak self] in
        self?.handleFirstKeyDown(mode: mode)
      }
    }
    initEventsMonitor()
  }

  isolated deinit {
      deinitEventsMonitor()
  }

  func initEventsMonitor() {
    guard eventsMonitor == nil else { return }

    self.eventsMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.flagsChanged, .keyDown],
      handler: handleEvent
    )
  }

  func deinitEventsMonitor() {
    guard let eventsMonitor else { return }

    NSEvent.removeMonitor(eventsMonitor)
    self.eventsMonitor = nil
  }

  // Keys monitor is only needed while any popup shortcut is recorded.
  func updateEventsMonitor() {
    if KeyboardShortcuts.Name.popupNames.contains(where: { $0.shortcut != nil }) {
      initEventsMonitor()
    } else {
      deinitEventsMonitor()
    }
  }

  func open(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    AppState.shared.appDelegate?.panel.open(height: height, at: popupPosition)
  }

  func reset() {
    state = .toggle
    revealTask?.cancel()
    isRevealPending = false
    AppState.shared.appDelegate?.panel.alphaValue = 1
    withoutAnimation { mode = .all }
    KeyboardShortcuts.enable(KeyboardShortcuts.Name.popupNames)
  }

  func close() {
    AppState.shared.appDelegate?.panel.close()  // close() calls reset
  }

  func isClosed() -> Bool {
    AppState.shared.appDelegate?.panel.isPresented != true
  }

  func preferredHeight(for newHeight: CGFloat) -> CGFloat {
    var height = newHeight

    var minHeight = self.minimumHeight
    // If the preview is non-empty make sure the window accomodates for it to be visible.
    if AppState.shared.preview.state.isOpen && AppState.shared.navigator.leadSelection != nil {
      minHeight = max(minHeight, Self.minimumPreviewHeight)
    }
    minHeight = max(headerHeight + Self.verticalPadding, minHeight)

    height = max(height, minHeight)
    height = min(height, Defaults[.windowSize].height)
    return height
  }

  private func suitableHeight(for historyListHeight: CGFloat) -> CGFloat {
    return historyListHeight + headerHeight + extraTopHeight + extraBottomHeight + footerHeight
  }

  func resize(height: CGFloat) {
    self.height = suitableHeight(for: height)
    AppState.shared.appDelegate?.panel.verticallyResize(
      to: preferredHeight(for: self.height),
      animated: animatesResize && !isRevealPending
    )
    animatesResize = true
    needsResize = false
    reveal()
  }

  private func openHidden(mode: PopupMode) {
    isRevealPending = true
    withoutAnimation { self.mode = mode }
    needsResize = true
    AppState.shared.appDelegate?.panel.alphaValue = 0
    open(height: height)

    // Show the popup anyway if it isn't resized in time.
    revealTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      self?.reveal()
    }
  }

  private func reveal() {
    guard isRevealPending else { return }

    isRevealPending = false
    revealTask?.cancel()
    AppState.shared.appDelegate?.panel.alphaValue = 1
    // Selection is made once visible, so that the snippets submenu opens next to the resized popup.
    AppState.shared.navigator.highlightInitial()
  }

  private func withoutAnimation(_ body: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, body)
  }

  private func handleFirstKeyDown(mode: PopupMode) {
    guard !AppState.shared.isEditingItem else { return }

    if isClosed() {
      // Full popup after another mode opens hidden as well, to grow without animation.
      if mode == .all && lastOpenedMode == .all {
        self.mode = mode
        open(height: height)
      } else {
        openHidden(mode: mode)
      }
      lastOpenedMode = mode
      state = .opening
      // Handle events via eventsMonitor. Re-enable on popup close
      KeyboardShortcuts.disable(KeyboardShortcuts.Name.popupNames)
      return
    }

    // Maccy was not opened via shortcut. Another mode's shortcut switches to it,
    // otherwise we assume toggle mode and close it.
    if mode != self.mode {
      switchMode(to: mode)
      return
    }

    close()
  }

  private func switchMode(to mode: PopupMode) {
    SnippetsSubmenu.shared.close()
    animatesResize = false
    withoutAnimation { self.mode = mode }
    AppState.shared.navigator.highlightInitial()
  }

  private func handleEvent(_ event: NSEvent) -> NSEvent? {
    guard !AppState.shared.isEditingItem else { return event }

    switch event.type {
    case .keyDown:
      return handleKeyDown(event)
    case .flagsChanged:
      return handleFlagsChanged(event)
    default:
      return event
    }
  }

  private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    if state == .toggle, let mode = otherMode(matching: event) {
      switchMode(to: mode)
      return nil
    }

    if isHotKeyCode(Int(event.keyCode)) {
      if let item = History.shared.pressedShortcutItem {
        AppState.shared.navigator.select(item: item)
        let modifierFlags = NSEvent.ModifierFlags.currentModifierFlags
        Task { @MainActor in
          AppState.shared.history.select(item, flags: modifierFlags)
        }
        return nil
      }

      if state == .opening {
        state = .cycle
        // Next 'if' will highlight next item and then return nil
      }

      if state == .cycle {
        AppState.shared.navigator.highlightNextInCycle()
        return nil
      }

      if state == .toggle && isHotKeyModifiers(event.modifierFlags) {
        close()
        return nil
      }

    }

    return event
  }

  private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
    // If we are in cycle mode, releasing modifiers triggers a selection
    if state == .cycle && allModifiersReleased(event) {
      // Arrow keys can still move the highlight to footer actions while cycling.
      // Releasing the modifiers must not run them, e.g. quit the app.
      if let item = AppState.shared.footer.selectedItem,
         AppState.shared.footer.actionItems.contains(item) {
        state = .toggle
        return event
      }

      let modifierFlags = NSEvent.ModifierFlags.currentModifierFlags
      DispatchQueue.main.async {
        AppState.shared.select(flags: modifierFlags)
      }
      return nil
    }

    // Otherwise if in opening mode, enter toggle mode
    if state == .opening && allModifiersReleased(event) {
      state = .toggle
      return event
    }

    return event
  }

  private func isHotKeyCode(_ keyCode: Int) -> Bool {
    guard let shortcut = mode.shortcutName.shortcut else {
      return false
    }

    return shortcut.key?.rawValue == keyCode
  }

  private func isHotKeyModifiers(_ modifiers: NSEvent.ModifierFlags) -> Bool {
    guard let shortcut = mode.shortcutName.shortcut else {
      return false
    }

    return modifiers.intersection(.deviceIndependentFlagsMask) ==
      shortcut.modifiers.intersection(.deviceIndependentFlagsMask)
  }

  // Global shortcuts are disabled while the popup is open,
  // so shortcuts of other modes are matched here.
  private func otherMode(matching event: NSEvent) -> PopupMode? {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    return [PopupMode.all, .snippets, .history].first { mode in
      guard mode != self.mode, let shortcut = mode.shortcutName.shortcut else { return false }

      return shortcut.key?.rawValue == Int(event.keyCode) &&
        modifiers == shortcut.modifiers.intersection(.deviceIndependentFlagsMask)
    }
  }

  private func allModifiersReleased(_ event: NSEvent) -> Bool {
    return event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask)
  }
}
