import SwiftUI
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import Settings

struct GeneralSettingsPane: View {
  private let notificationsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.notifications?id=\(Bundle.main.bundleIdentifier ?? "")"
  )

  @Default(.searchMode) private var searchMode

  @State private var copyModifier = HistoryItemAction.copy.modifierFlags.description
  @State private var pasteModifier = HistoryItemAction.paste.modifierFlags.description
  @State private var pasteWithoutFormatting = HistoryItemAction.pasteWithoutFormatting.modifierFlags.description

  @State private var updater = SoftwareUpdater()

  @State private var language = AppLanguage.selected()
  private let launchLanguage = AppLanguage.selected()

  var body: some View {
    Settings.Container(contentWidth: 450) {
      Settings.Section(title: "", bottomDivider: true) {
        LaunchAtLogin.Toggle {
          Text("LaunchAtLogin", tableName: "GeneralSettings")
        }
        Toggle(isOn: $updater.automaticallyChecksForUpdates) {
          Text("CheckForUpdates", tableName: "GeneralSettings")
        }
        Button(
          action: { updater.checkForUpdates() },
          label: { Text("CheckNow", tableName: "GeneralSettings") }
        )
      }

      Settings.Section(
        bottomDivider: true,
        label: { Text("Language", tableName: "GeneralSettings") }
      ) {
        Picker("", selection: $language) {
          ForEach(AppLanguage.available) { language in
            Text(language.name).tag(language)
          }
        }
        .labelsHidden()
        .accessibilityLabel(Text("Language", tableName: "GeneralSettings"))
        .help(Text("LanguageTooltip", tableName: "GeneralSettings"))
        .frame(width: 180, alignment: .leading)
        .onChange(of: language) {
          AppLanguage.select(language)
        }

        if language != launchLanguage {
          HStack {
            Text("LanguageRestartNeeded", tableName: "GeneralSettings")
              .foregroundStyle(.gray)
              .controlSize(.small)
            Button(
              action: { AppLanguage.restart() },
              label: { Text("LanguageRestart", tableName: "GeneralSettings") }
            )
          }
        }
      }

      Settings.Section(label: { Text("Open", tableName: "GeneralSettings") }) {
        KeyboardShortcuts.Recorder(for: .popup, onChange: { _ in
          AppState.shared.popup.updateEventsMonitor()
        })
          .help(Text("OpenTooltip", tableName: "GeneralSettings"))
          .accessibilityLabel(Text("Open", tableName: "GeneralSettings"))
      }
      Settings.Section(label: { Text("OpenSnippets", tableName: "GeneralSettings") }) {
        KeyboardShortcuts.Recorder(for: .popupSnippets, onChange: { _ in
          AppState.shared.popup.updateEventsMonitor()
        })
          .help(Text("OpenSnippetsTooltip", tableName: "GeneralSettings"))
          .accessibilityLabel(Text("OpenSnippets", tableName: "GeneralSettings"))
      }
      Settings.Section(label: { Text("OpenHistory", tableName: "GeneralSettings") }) {
        KeyboardShortcuts.Recorder(for: .popupHistory, onChange: { _ in
          AppState.shared.popup.updateEventsMonitor()
        })
          .help(Text("OpenHistoryTooltip", tableName: "GeneralSettings"))
          .accessibilityLabel(Text("OpenHistory", tableName: "GeneralSettings"))
      }

      Settings.Section(label: { Text("Pin", tableName: "GeneralSettings") }) {
        KeyboardShortcuts.Recorder(for: .pin)
          .help(Text("PinTooltip", tableName: "GeneralSettings"))
          .accessibilityLabel(Text("Pin", tableName: "GeneralSettings"))
      }
      Settings.Section(label: { Text("Delete", tableName: "GeneralSettings") }
      ) {
        KeyboardShortcuts.Recorder(for: .delete)
          .help(Text("DeleteTooltip", tableName: "GeneralSettings"))
          .accessibilityLabel(Text("Delete", tableName: "GeneralSettings"))
      }
      Settings.Section(
        bottomDivider: true,
        label: { Text("ShowPreview", tableName: "GeneralSettings") }
      ) {
        KeyboardShortcuts.Recorder(for: .togglePreview)
          .help(Text("ShowPreviewTooltip", tableName: "GeneralSettings"))
          .accessibilityLabel(Text("ShowPreview", tableName: "GeneralSettings"))
      }

      Settings.Section(
        bottomDivider: true,
        label: { Text("Search", tableName: "GeneralSettings") }
      ) {
        Picker("", selection: $searchMode) {
          ForEach(Search.Mode.allCases) { mode in
            Text(mode.description)
          }
        }
        .labelsHidden()
        .accessibilityLabel(Text("Search", tableName: "GeneralSettings"))
        .frame(width: 180, alignment: .leading)
      }

      Settings.Section(
        bottomDivider: true,
        label: { Text("Behavior", tableName: "GeneralSettings") }
      ) {
        Defaults.Toggle(key: .pasteByDefault) {
          Text("PasteAutomatically", tableName: "GeneralSettings")
        }
        .onChange(refreshModifiers)
        .fixedSize()

        Defaults.Toggle(key: .removeFormattingByDefault) {
          Text("PasteWithoutFormatting", tableName: "GeneralSettings")
        }
        .onChange(refreshModifiers)
        .fixedSize()

        Text(String(
          format: NSLocalizedString("Modifiers", tableName: "GeneralSettings", comment: ""),
          copyModifier, pasteModifier, pasteWithoutFormatting
        ))
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .controlSize(.small)
      }

      Settings.Section(title: "") {
        if let notificationsURL = notificationsURL {
          Link(destination: notificationsURL, label: {
            Text("NotificationsAndSounds", tableName: "GeneralSettings")
          })
        }
      }
    }
  }

  private func refreshModifiers(_ sender: Sendable) {
    copyModifier = HistoryItemAction.copy.modifierFlags.description
    pasteModifier = HistoryItemAction.paste.modifierFlags.description
    pasteWithoutFormatting = HistoryItemAction.pasteWithoutFormatting.modifierFlags.description
  }
}

#Preview {
  GeneralSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
