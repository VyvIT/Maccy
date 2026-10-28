import AppKit
import SwiftHEXColors

// Adjusts a copied hex color in the system color panel. Adjusting doesn't touch
// the clipboard, Copy adds the adjusted color as a new item in the same notation,
// and closing the panel discards it.
@MainActor
final class HexColorPicker: NSObject {
  static let shared = HexColorPicker()

  private var original = ""

  private lazy var accessoryView: NSView = {
    let button = NSButton(
      title: NSLocalizedString("color_picker_copy", comment: ""),
      target: self,
      action: #selector(copyColor)
    )
    button.bezelStyle = .push
    button.keyEquivalent = "\r"

    let stack = NSStackView(views: [button])
    stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    return stack
  }()

  func open(hex: String) {
    guard let color = NSColor(hexString: hex.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }

    original = hex
    let mouseLocation = NSEvent.mouseLocation
    AppState.shared.popup.close()

    let panel = NSColorPanel.shared
    // Panel is shared app-wide, so don't let anything else receive its changes.
    panel.setTarget(nil)
    panel.setAction(nil)
    panel.showsAlpha = Self.hasAlpha(hex)
    panel.color = color
    panel.accessoryView = accessoryView
    // Maccy is rarely the active app, and the panel hides itself whenever it isn't.
    panel.hidesOnDeactivate = false
    NSApp.activate(ignoringOtherApps: true)
    place(panel, at: mouseLocation)
    panel.makeKeyAndOrderFront(nil)
  }

  // Centers the panel on the point, keeping it on the point's screen.
  private func place(_ panel: NSPanel, at point: NSPoint) {
    guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main
    else { return }

    let visible = screen.visibleFrame
    let size = panel.frame.size
    let origin = NSPoint(
      x: min(max(point.x - size.width / 2, visible.minX), visible.maxX - size.width),
      y: min(max(point.y - size.height / 2, visible.minY), visible.maxY - size.height)
    )
    panel.setFrameOrigin(origin)
  }

  @objc private func copyColor() {
    let panel = NSColorPanel.shared
    Clipboard.shared.copyInMaccy(Self.hex(for: panel.color, like: original))
    panel.close()
  }

  // Hex string of the color in the notation of the original: with or without "#",
  // with alpha for 4 and 8 digits, and in upper case if the original used it.
  static func hex(for color: NSColor, like original: String) -> String {
    let original = original.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasHash = original.hasPrefix("#")
    guard let rgb = color.usingColorSpace(.sRGB) else { return original }

    var components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
    if hasAlpha(original) {
      components.append(rgb.alphaComponent)
    }
    var hex = components
      .map { String(format: "%02x", Int((min(max($0, 0), 1) * 255).rounded())) }
      .joined()
    if original.contains(where: \.isUppercase) {
      hex = hex.uppercased()
    }

    return (hasHash ? "#" : "") + hex
  }

  private static func hasAlpha(_ hex: String) -> Bool {
    let digits = hex.trimmingCharacters(in: .whitespacesAndNewlines).drop { $0 == "#" }
    return digits.count == 4 || digits.count == 8
  }
}
