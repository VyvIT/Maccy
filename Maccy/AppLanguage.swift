import AppKit
import KeyboardShortcuts

// macOS picks the language of an app from AppleLanguages in its own defaults,
// the same setting that System Settings › Language & Region › Applications changes.
// It is only read at launch, so changing it needs a restart.
struct AppLanguage: Identifiable, Hashable {
  static let system = AppLanguage(code: nil)

  static var available: [AppLanguage] {
    let languages = Bundle.main.localizations
      .filter { $0 != "Base" }
      .map { AppLanguage(code: $0) }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    return [.system] + languages
  }

  let code: String?
  var id: String { code ?? "" }

  // Languages are listed by their own names, so they can be found without
  // understanding the current one.
  var name: String {
    guard let code else {
      return NSLocalizedString("LanguageSystem", tableName: "GeneralSettings", comment: "")
    }

    let locale = Locale(identifier: code)
    return locale.localizedString(forIdentifier: code)?.capitalized(with: locale) ?? code
  }
}

extension AppLanguage {
  private static let key = "AppleLanguages"

  // UserDefaults falls back to the system languages for this key,
  // so only the app's own domain tells whether one was chosen.
  static func selected(
    in defaults: UserDefaults = .standard,
    domain: String = Bundle.main.bundleIdentifier ?? ""
  ) -> AppLanguage {
    let languages = defaults.persistentDomain(forName: domain)?[key] as? [String]
    return AppLanguage(code: languages?.first)
  }

  static func select(_ language: AppLanguage, in defaults: UserDefaults = .standard) {
    if let code = language.code {
      defaults.set([code], forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
  }

  @MainActor
  static func restart() {
    // Let the new instance register the global shortcut.
    KeyboardShortcuts.disable(.popup)

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
      Task { @MainActor in
        if error == nil {
          NSApp.terminate(nil)
        } else {
          KeyboardShortcuts.enable(.popup)
        }
      }
    }
  }
}
