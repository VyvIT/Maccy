import AppKit
import SwiftHEXColors
import Testing
@testable import Maccy

@MainActor
struct ColorImageTests {
  @Test("Color image from hex", arguments: ["fff", "#ff8942"])
  func colorImageFromHex(hex: String) {
    #expect(ColorImage.from(hex) != nil)
  }

  @Test("Color image from non-hex string")
  func colorImageFromNonHexString() {
    #expect(ColorImage.from("foo") == nil)
  }
}

@MainActor
struct HexColorPickerTests {
  @Test(
    "Adjusted color keeps the notation of the original",
    arguments: [
      ("#ff8942", "#ff8942"),
      ("FF8942", "FF8942"),
      ("#fff", "#ffffff"),
      ("#ff894280", "#ff894280"),
      (" #ff8942\n", "#ff8942")
    ]
  )
  func keepsNotation(original: String, expected: String) throws {
    let color = try #require(NSColor(hexString: original.trimmingCharacters(in: .whitespacesAndNewlines)))
    #expect(HexColorPicker.hex(for: color, like: original) == expected)
  }

  @Test("Adjusted color is written in hex")
  func writesAdjustedColor() {
    let color = NSColor(srgbRed: 1, green: 0, blue: 0.5, alpha: 1)
    #expect(HexColorPicker.hex(for: color, like: "#00FF00") == "#FF0080")
  }
}
