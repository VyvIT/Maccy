import Foundation
import Testing
@testable import Maccy

@MainActor
final class AppLanguageTests {
  let domain = "AppLanguageTests-\(UUID().uuidString)"
  let defaults: UserDefaults

  init() throws {
    defaults = try #require(UserDefaults(suiteName: domain))
  }

  deinit {
    UserDefaults.standard.removePersistentDomain(forName: domain)
  }

  @Test("Follows the system until a language is chosen")
  func followsSystem() {
    // Unlike the app's own domain, the global one always has languages.
    #expect(defaults.array(forKey: "AppleLanguages") != nil)
    #expect(AppLanguage.selected(in: defaults, domain: domain) == .system)
  }

  @Test("Remembers the chosen language")
  func selectsLanguage() {
    AppLanguage.select(AppLanguage(code: "lt"), in: defaults)

    #expect(AppLanguage.selected(in: defaults, domain: domain) == AppLanguage(code: "lt"))
    #expect(defaults.persistentDomain(forName: domain)?["AppleLanguages"] as? [String] == ["lt"])
  }

  @Test("Choosing System goes back to the system languages")
  func selectsSystem() {
    AppLanguage.select(AppLanguage(code: "lt"), in: defaults)

    AppLanguage.select(.system, in: defaults)

    #expect(AppLanguage.selected(in: defaults, domain: domain) == .system)
  }

  @Test("Lists System first and the translations by their own names")
  func listsLanguages() {
    let languages = AppLanguage.available

    #expect(languages.first == .system)
    #expect(languages.contains(AppLanguage(code: "en")))
    #expect(!languages.contains(AppLanguage(code: "Base")))
    #expect(AppLanguage(code: "lt").name == "Lietuvių")
    #expect(AppLanguage(code: "de").name == "Deutsch")
  }
}
