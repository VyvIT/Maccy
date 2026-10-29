import AppKit

nonisolated private let blockedAccessibilityAttributes: Set<NSAccessibility.Attribute> = [
  .size, .position, .minimized,
  NSAccessibility.Attribute(rawValue: "AXFrame"),
  NSAccessibility.Attribute(rawValue: "AXFullScreen")
]

// Window managers such as Loop move and resize windows via accessibility,
// e.g. maximize the popup. Reports the panel as a floating window whose frame
// can't be changed that way, while Maccy and the user can still move and resize it.
class WindowManagerProofPanel: NSPanel {
  override func accessibilitySubrole() -> NSAccessibility.Subrole? {
    return .floatingWindow
  }

  nonisolated override func accessibilityIsAttributeSettable(_ attribute: NSAccessibility.Attribute) -> Bool {
    if blockedAccessibilityAttributes.contains(attribute) {
      return false
    }
    return super.accessibilityIsAttributeSettable(attribute)
  }

  nonisolated override func accessibilitySetValue(_ value: Any?, forAttribute attribute: NSAccessibility.Attribute) {
    guard !blockedAccessibilityAttributes.contains(attribute) else { return }
    super.accessibilitySetValue(value, forAttribute: attribute)
  }

  override func setAccessibilityFrame(_ accessibilityFrame: NSRect) {}
}
