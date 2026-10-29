import AppKit
import Carbon.HIToolbox
import SwiftUI

// Records a single modifier key, looking like the shortcut recorders in General settings,
// which can't record a modifier key on its own.
struct ModifierKeyRecorder: NSViewRepresentable {
  @Binding var key: PasswordRevealKey

  func makeNSView(context: Context) -> ModifierKeyRecorderField {
    let field = ModifierKeyRecorderField()
    field.onChange = { key = $0 }
    field.key = key
    return field
  }

  func updateNSView(_ field: ModifierKeyRecorderField, context: Context) {
    field.onChange = { key = $0 }
    field.key = key
  }
}

final class ModifierKeyRecorderField: NSSearchField {
  // Same strings as the shortcut recorders, from the KeyboardShortcuts package.
  private static let recorderBundle = Bundle.main
    .url(forResource: "KeyboardShortcuts_KeyboardShortcuts", withExtension: "bundle")
    .flatMap(Bundle.init(url:))

  private static func localized(_ key: String, _ fallback: String) -> String {
    guard let recorderBundle else { return fallback }
    return recorderBundle.localizedString(forKey: key, value: fallback, table: nil)
  }

  private static let modifierKeys: [Int: PasswordRevealKey] = [
    kVK_Function: .function,
    kVK_Control: .control, kVK_RightControl: .control,
    kVK_Option: .option, kVK_RightOption: .option,
    kVK_Command: .command, kVK_RightCommand: .command,
    kVK_Shift: .shift, kVK_RightShift: .shift
  ]

  var onChange: ((PasswordRevealKey) -> Void)?
  var key: PasswordRevealKey = .none {
    didSet {
      if key != oldValue {
        updateStringValue()
      }
    }
  }

  private var cancelButton: NSButtonCell?
  private var eventMonitor: Any?
  private var resignKeyObserver: NSObjectProtocol?
  private var isRecording: Bool { eventMonitor != nil }

  init() {
    super.init(frame: NSRect(x: 0, y: 0, width: 130, height: 24))
    alignment = .center
    isEditable = false
    isSelectable = false
    placeholderString = Self.localized("record_shortcut", "Record Shortcut")
    (cell as? NSSearchFieldCell)?.searchButtonCell = nil
    cancelButton = (cell as? NSSearchFieldCell)?.cancelButtonCell
    setContentHuggingPriority(.defaultHigh, for: .vertical)
    setContentHuggingPriority(.defaultHigh, for: .horizontal)
    updateStringValue()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var intrinsicContentSize: CGSize {
    var size = super.intrinsicContentSize
    size.width = 130
    return size
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil {
      endRecording()
    }
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if key != .none, !isRecording,
       let searchCell = cell as? NSSearchFieldCell,
       searchCell.cancelButtonRect(forBounds: bounds).contains(point) {
      select(.none)
      return
    }

    isRecording ? endRecording() : startRecording()
  }

  private func startRecording() {
    stringValue = ""
    showsCancelButton = false
    placeholderString = Self.localized("press_shortcut", "Press Shortcut")

    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]) { [weak self] event in
      self?.handle(event) ?? event
    }
    resignKeyObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification,
      object: window,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.endRecording() }
    }
  }

  private func endRecording() {
    if let eventMonitor {
      NSEvent.removeMonitor(eventMonitor)
    }
    eventMonitor = nil
    if let resignKeyObserver {
      NotificationCenter.default.removeObserver(resignKeyObserver)
    }
    resignKeyObserver = nil
    placeholderString = Self.localized("record_shortcut", "Record Shortcut")
    updateStringValue()
  }

  private func handle(_ event: NSEvent) -> NSEvent? {
    switch event.type {
    case .flagsChanged:
      // Only pressing a modifier records it, releasing one doesn't.
      if let key = Self.modifierKeys[Int(event.keyCode)],
         let flag = key.modifierFlag,
         event.modifierFlags.contains(flag) {
        select(key)
      }
      return nil
    case .keyDown:
      switch Int(event.keyCode) {
      case kVK_Escape:
        endRecording()
      case kVK_Delete, kVK_ForwardDelete:
        select(.none)
      default:
        NSSound.beep()
      }
      return nil
    default:
      // Clicking elsewhere stops recording, clicks on the field are handled by mouseDown.
      if event.window != window || !bounds.contains(convert(event.locationInWindow, from: nil)) {
        endRecording()
      }
      return event
    }
  }

  private func select(_ newKey: PasswordRevealKey) {
    key = newKey
    endRecording()
    onChange?(newKey)
  }

  private var showsCancelButton: Bool {
    get { (cell as? NSSearchFieldCell)?.cancelButtonCell != nil }
    set { (cell as? NSSearchFieldCell)?.cancelButtonCell = newValue ? cancelButton : nil }
  }

  private func updateStringValue() {
    guard !isRecording else { return }
    stringValue = key == .none ? "" : key.description
    showsCancelButton = key != .none
    needsDisplay = true
  }
}
