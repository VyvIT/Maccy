import Carbon.HIToolbox
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  static let popup = Self("popup", initial: Shortcut(.c, modifiers: [.command, .shift]))
  static let popupSnippets = Self(
    "popupSnippets",
    initial: Shortcut(.init(rawValue: kVK_ISO_Section), modifiers: [.command, .option])
  )
  static let popupHistory = Self(
    "popupHistory",
    initial: Shortcut(.init(rawValue: kVK_ISO_Section), modifiers: [.command, .shift])
  )
  static let pin = Self("pin", initial: Shortcut(.p, modifiers: [.option]))
  static let delete = Self("delete", initial: Shortcut(.delete, modifiers: [.option]))
  static let togglePreview = Self("togglePreview", initial: Shortcut(.space, modifiers: [.control]))

  // Global shortcuts that open the popup, each in its own mode.
  static let popupNames: [Self] = [.popup, .popupSnippets, .popupHistory]
}
