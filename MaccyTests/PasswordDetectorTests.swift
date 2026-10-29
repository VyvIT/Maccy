import AppKit
import Testing
@testable import Maccy

struct PasswordDetectorTests {
  @Test("Detects passwords", arguments: [
    "Tr0ub4dor&3",
    "hunter2!x",
    "Password123",
    "x7#kP9$mQ2",
    "correct-Horse-battery-7",
    "ABCdef!@#$"
  ])
  func detectsPasswords(text: String) {
    #expect(PasswordDetector.isLikelyPassword(text))
  }

  @Test("Ignores other text", arguments: [
    "short1!",
    "hello world 123!",
    "plainlowercaseword",
    "ALLUPPERCASE",
    "lowercase123",
    "https://Example.com/Path1",
    "www.Example1.com",
    "John.Doe1@example.com",
    "/Users/John/Doc1.txt",
    "~/Library/Logs1",
    "#FF00aa",
    "123e4567-E89b-12d3-a456-426614174000",
    "1,234,567.89",
    "Line1\nLine2!",
    String(repeating: "aB1!", count: 17)
  ])
  func ignoresOtherText(text: String) {
    #expect(!PasswordDetector.isLikelyPassword(text))
  }

  @Test("Masks all but first and last characters with fixed length")
  func masksWithFixedLength() {
    #expect(PasswordDetector.masked("Tr0ub4dor&3", showLength: false) == "T••••••••3")
    #expect(PasswordDetector.masked("hunter2!xyz123456789", showLength: false) == "h••••••••9")
  }

  @Test("Masks all but first and last characters with real length")
  func masksWithRealLength() {
    #expect(PasswordDetector.masked("Tr0ub4dor&3", showLength: true) == "T•••••••••3")
    #expect(PasswordDetector.masked("hunter2!x", showLength: true) == "h•••••••x")
  }

  @Test("Reveal key is held while its modifier is down")
  @MainActor
  func revealKeyIsHeld() {
    #expect(PasswordRevealKey.function.isHeld(in: [.function]))
    #expect(PasswordRevealKey.function.isHeld(in: [.function, .shift]))
    #expect(!PasswordRevealKey.function.isHeld(in: [.option]))
    #expect(!PasswordRevealKey.none.isHeld(in: [.function, .option, .command]))
  }
}
