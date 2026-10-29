import AppKit
import Defaults

// Modifier key that shows hidden passwords in the popup while held.
enum PasswordRevealKey: String, CustomStringConvertible, Defaults.Serializable {
  case none
  case function
  case control
  case option
  case command
  case shift

  var modifierFlag: NSEvent.ModifierFlags? {
    switch self {
    case .none: return nil
    case .function: return .function
    case .control: return .control
    case .option: return .option
    case .command: return .command
    case .shift: return .shift
    }
  }

  var description: String {
    switch self {
    case .none: return ""
    case .function: return "fn"
    case .control: return "⌃"
    case .option: return "⌥"
    case .command: return "⌘"
    case .shift: return "⇧"
    }
  }

  func isHeld(in modifierFlags: NSEvent.ModifierFlags) -> Bool {
    guard let modifierFlag else { return false }
    return modifierFlags.contains(modifierFlag)
  }
}
