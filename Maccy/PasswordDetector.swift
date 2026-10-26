import Defaults
import Foundation

// Guesses whether copied text is a password, so that it can be hidden in the history.
nonisolated enum PasswordDetector {
  static let lengthRange = 8...64
  // Unless configured otherwise, masked passwords show the same number
  // of hidden characters, so that their length isn't revealed either.
  static let hiddenCharacterCount = 8
  static let hiddenCharacter = "•"

  private static let excludedPatterns = [
    "^[a-zA-Z][a-zA-Z0-9+.-]*://", // URL
    "^www\\.",
    "^[^@]+@[^@]+\\.[a-zA-Z]{2,}$", // Email
    "^[~/.]", // Path
    "^#?[0-9a-fA-F]{3,8}$", // Hex color
    "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", // UUID
    "^[+-]?[0-9.,]+$" // Number
  ].map { try! NSRegularExpression(pattern: $0) } // swiftlint:disable:this force_try

  // Single word mixing at least three kinds of characters
  // out of lowercase and uppercase letters, digits and symbols.
  static func isLikelyPassword(_ text: String) -> Bool {
    guard lengthRange.contains(text.count),
          !text.contains(where: { $0.isWhitespace }) else { return false }

    let range = NSRange(text.startIndex..., in: text)
    guard !excludedPatterns.contains(where: { $0.firstMatch(in: text, range: range) != nil }) else { return false }

    let kinds = [
      text.contains(where: { $0.isLowercase }),
      text.contains(where: { $0.isUppercase }),
      text.contains(where: { $0.isNumber }),
      text.contains(where: { !$0.isLetter && !$0.isNumber })
    ]
    return kinds.filter { $0 }.count >= 3
  }

  // First and last characters of the password with hidden characters in between.
  static func maskedParts(
    _ text: String,
    showLength: Bool = Defaults[.maskPasswordsShowLength]
  ) -> (first: String, hidden: String, last: String) {
    let hiddenCount = showLength ? max(text.count - 2, 0) : hiddenCharacterCount
    return (String(text.prefix(1)), String(repeating: hiddenCharacter, count: hiddenCount), String(text.suffix(1)))
  }

  static func masked(_ text: String, showLength: Bool = Defaults[.maskPasswordsShowLength]) -> String {
    let parts = maskedParts(text, showLength: showLength)
    return parts.first + parts.hidden + parts.last
  }
}

extension HistoryItem {
  var isLikelyPassword: Bool {
    // Check the text first, as images are expensive to decode.
    guard let text, PasswordDetector.isLikelyPassword(text) else { return false }
    return imageData == nil && fileURLs.isEmpty
  }

  // Title safe to show outside the list, e.g. in notifications.
  var safeTitle: String {
    Defaults[.maskPasswords] && isLikelyPassword ? PasswordDetector.masked(title) : title
  }
}
