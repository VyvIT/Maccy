import AppKit
import SwiftUI
import Defaults
import Settings

struct AppearanceSettingsPane: View {
  @Default(.popupPosition) private var popupAt
  @Default(.popupScreen) private var popupScreen
  @Default(.pinTo) private var pinTo
  @Default(.imageMaxHeight) private var imageHeight
  @Default(.visibleItems) private var visibleItems
  @Default(.visibleItemsHistoryOnly) private var visibleItemsHistoryOnly
  @Default(.previewOpening) private var previewOpening
  @Default(.previewDelay) private var previewDelay
  @Default(.snippetPreviewDelay) private var snippetPreviewDelay
  @Default(.highlightMatch) private var highlightMatch
  @Default(.menuIcon) private var menuIcon
  @Default(.showInStatusBar) private var showInStatusBar
  @Default(.showSearch) private var showSearch
  @Default(.searchVisibility) private var searchVisibility
  @Default(.showFooter) private var showFooter
  @Default(.windowPosition) private var windowPosition
  @Default(.showApplicationIcons) private var showApplicationIcons
  @Default(.maskPasswords) private var maskPasswords

  @State private var screens = NSScreen.screens
  @State private var tab: AppearanceTab = .popup

  private let imageHeightFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 1
    formatter.maximum = 200
    return formatter
  }()

  private let visibleItemsFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 3
    formatter.maximum = 999
    return formatter
  }()

  private let numberOfItemsFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 0
    formatter.maximum = 100
    return formatter
  }()

  private let titleLengthFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 30
    formatter.maximum = 200
    return formatter
  }()

  private let previewDelayFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 200
    formatter.maximum = 100_000
    return formatter
  }()

  private let snippetPreviewDelayFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 0
    formatter.maximum = 100_000
    return formatter
  }()

  var body: some View {
    VStack(spacing: 0) {
      Picker("", selection: $tab) {
        ForEach(AppearanceTab.allCases) { tab in
          Text(tab.title, tableName: "AppearanceSettings").tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()
      .padding(.top, 20)
      .accessibilityLabel(Text("Title", tableName: "AppearanceSettings"))

      switch tab {
      case .popup: popupSettings
      case .search: searchSettings
      case .items: itemsSettings
      case .preview: previewSettings
      case .menuBar: menuBarSettings
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
      screens = NSScreen.screens
    }
  }

  private var popupSettings: some View {
    Settings.Container(contentWidth: 650) {
      Settings.Section(label: { Text("PopupAt", tableName: "AppearanceSettings") }) {
        HStack {
          Picker("", selection: $popupAt) {
            ForEach(PopupPosition.allCases) { position in
              if position == .center || position == .lastPosition, screens.count > 1 {
                screenPicker(for: position)
              } else {
                Text(position.description)
              }
            }
          }
          .labelsHidden()
          .frame(width: 141, alignment: .leading)
          .help(Text("PopupAtTooltip", tableName: "AppearanceSettings"))
          .accessibilityLabel(Text("PopupAt", tableName: "AppearanceSettings"))

          if popupAt == .lastPosition {
            Button {
              _windowPosition.reset()
            } label: {
              Image(systemName: "arrow.uturn.backward.circle.fill")
                .imageScale(.large)
            }
            .buttonStyle(.borderless)
            .help(Text("PopupAtLastLocationReset", tableName: "AppearanceSettings"))
            .disabled(windowPosition == _windowPosition.defaultValue)
          }
        }
      }

      Settings.Section(label: { Text("PinTo", tableName: "AppearanceSettings") }) {
        Picker("", selection: $pinTo) {
          ForEach(PinsPosition.allCases) { position in
            Text(position.description)
          }
        }
        .labelsHidden()
        .frame(width: 141, alignment: .leading)
        .help(Text("PinToTooltip", tableName: "AppearanceSettings"))
        .accessibilityLabel(Text("PinTo", tableName: "AppearanceSettings"))
      }

      Settings.Section(label: { Text("VisibleItems", tableName: "AppearanceSettings") }) {
        HStack {
          TextField("", value: $visibleItems, formatter: visibleItemsFormatter)
            .frame(width: 120)
            .help(Text("VisibleItemsTooltip", tableName: "AppearanceSettings"))
            .accessibilityLabel(Text("VisibleItems", tableName: "AppearanceSettings"))
          Stepper("", value: $visibleItems, in: 3...999)
            .labelsHidden()
            .accessibilityLabel(Text("VisibleItems", tableName: "AppearanceSettings"))
        }
      }

      Settings.Section(label: { Text("VisibleItemsHistoryOnly", tableName: "AppearanceSettings") }) {
        HStack {
          TextField("", value: $visibleItemsHistoryOnly, formatter: visibleItemsFormatter)
            .frame(width: 120)
            .help(Text("VisibleItemsHistoryOnlyTooltip", tableName: "AppearanceSettings"))
            .accessibilityLabel(Text("VisibleItemsHistoryOnly", tableName: "AppearanceSettings"))
          Stepper("", value: $visibleItemsHistoryOnly, in: 3...999)
            .labelsHidden()
            .accessibilityLabel(Text("VisibleItemsHistoryOnly", tableName: "AppearanceSettings"))
        }
        hint("VisibleItemsHint")
      }

      Settings.Section(title: "") {
        Defaults.Toggle(key: .showFooter) {
          Text("ShowFooter", tableName: "AppearanceSettings")
        }
        Defaults.Toggle(key: .showSnippets) {
          Text("ShowSnippets", tableName: "AppearanceSettings")
        }
        .help(Text("ShowSnippetsTooltip", tableName: "AppearanceSettings"))
        .disabled(!showFooter)
        .padding(.leading, 20)
        hint("ShowSnippetsTooltip", level: 2)
        if !showFooter {
          hint("OpenPreferencesWarning")
        }
      }
    }
  }

  private var searchSettings: some View {
    Settings.Container(contentWidth: 650) {
      Settings.Section(label: { Text("SearchField", tableName: "AppearanceSettings") }) {
        Picker("", selection: searchField) {
          Text("SearchFieldHidden", tableName: "AppearanceSettings")
            .tag(SearchVisibility?.none)
          ForEach(SearchVisibility.allCases) { visibility in
            Text(visibility.description)
              .tag(SearchVisibility?.some(visibility))
          }
        }
        .labelsHidden()
        .frame(width: 141, alignment: .leading)
        .accessibilityLabel(Text("SearchField", tableName: "AppearanceSettings"))
        hint("SearchVisibilityHint")
      }

      Settings.Section(title: "") {
        Defaults.Toggle(key: .showTitle) {
          Text("ShowTitleBeforeSearchField", tableName: "AppearanceSettings")
        }
        .disabled(!showSearch)
        hint("ShowTitleHint", level: 1)
      }

      Settings.Section(
        label: { Text("HighlightMatches", tableName: "AppearanceSettings") }
      ) {
        Picker("", selection: $highlightMatch) {
          ForEach(HighlightMatch.allCases) { match in
            Text(match.description)
          }
        }
        .labelsHidden()
        .frame(width: 141, alignment: .leading)
        .help(Text("HighlightMatchesTooltip", tableName: "AppearanceSettings"))
        .accessibilityLabel(Text("HighlightMatches", tableName: "AppearanceSettings"))
      }
    }
  }

  private var itemsSettings: some View {
    Settings.Container(contentWidth: 650) {
      Settings.Section(label: { Text("ImageHeight", tableName: "AppearanceSettings") }) {
        HStack {
          TextField("", value: $imageHeight, formatter: imageHeightFormatter)
            .frame(width: 120)
            .help(Text("ImageHeightTooltip", tableName: "AppearanceSettings"))
            .accessibilityLabel(Text("ImageHeight", tableName: "AppearanceSettings"))
          Stepper("", value: $imageHeight, in: 1...200)
            .labelsHidden()
            .accessibilityLabel(Text("ImageHeight", tableName: "AppearanceSettings"))
        }
        hint("ImageHeightHint")
      }

      Settings.Section(title: "") {
        Defaults.Toggle(key: .showApplicationIcons) {
          Text("ShowApplicationIcons", tableName: "AppearanceSettings")
        }
        Defaults.Toggle(key: .showSpecialSymbols) {
          Text("ShowSpecialSymbols", tableName: "AppearanceSettings")
        }
        .help(Text("ShowSpecialSymbolsTooltip", tableName: "AppearanceSettings"))
        hint("ShowSpecialSymbolsTooltip", level: 1)
        Defaults.Toggle(key: .showHexColorSwatch) {
          Text("ShowHexColorSwatch", tableName: "AppearanceSettings")
        }
        .help(Text("ShowHexColorSwatchTooltip", tableName: "AppearanceSettings"))
        hint("ShowHexColorSwatchTooltip", level: 1)
        hint("ShowHexColorSwatchHint", level: 1)
        Defaults.Toggle(key: .maskPasswords) {
          Text("MaskPasswords", tableName: "AppearanceSettings")
        }
        .help(Text("MaskPasswordsTooltip", tableName: "AppearanceSettings"))
        hint("MaskPasswordsTooltip", level: 1)
        Defaults.Toggle(key: .maskPasswordsShowLength) {
          Text("MaskPasswordsShowLength", tableName: "AppearanceSettings")
        }
        .help(Text("MaskPasswordsShowLengthTooltip", tableName: "AppearanceSettings"))
        .disabled(!maskPasswords)
        .padding(.leading, 20)
        hint("MaskPasswordsShowLengthTooltip", level: 2)
      }
    }
  }

  // Delays matter only when previews open automatically.
  @ViewBuilder
  private var previewSettings: some View {
    if previewOpening == .delay {
      Settings.Container(contentWidth: 650) {
        Settings.Section(label: { Text("OpenPreview", tableName: "AppearanceSettings") }) {
          openPreviewPicker
        }
        Settings.Section(label: { Text("PreviewDelay", tableName: "AppearanceSettings") }) {
          previewDelayField
        }
        Settings.Section(label: { Text("SnippetPreviewDelay", tableName: "AppearanceSettings") }) {
          snippetPreviewDelayField
        }
      }
    } else {
      Settings.Container(contentWidth: 650) {
        Settings.Section(label: { Text("OpenPreview", tableName: "AppearanceSettings") }) {
          openPreviewPicker
        }
      }
    }
  }

  @ViewBuilder
  private var openPreviewPicker: some View {
    Picker("", selection: $previewOpening) {
      ForEach(PreviewOpening.allCases) { opening in
        Text(opening.description)
      }
    }
    .labelsHidden()
    .fixedSize()
    .help(Text("OpenPreviewTooltip", tableName: "AppearanceSettings"))
    .accessibilityLabel(Text("OpenPreview", tableName: "AppearanceSettings"))
    hint("OpenPreviewHint")
  }

  private var previewDelayField: some View {
    HStack {
      TextField("", value: $previewDelay, formatter: previewDelayFormatter)
        .frame(width: 120)
        .help(Text("PreviewDelayTooltip", tableName: "AppearanceSettings"))
        .accessibilityLabel(Text("PreviewDelay", tableName: "AppearanceSettings"))
      Stepper("", value: $previewDelay, in: 200...100_000)
        .labelsHidden()
        .accessibilityLabel(Text("PreviewDelay", tableName: "AppearanceSettings"))
      Text("Milliseconds", tableName: "AppearanceSettings")
        .foregroundStyle(.secondary)
    }
  }

  private var snippetPreviewDelayField: some View {
    HStack {
      TextField("", value: $snippetPreviewDelay, formatter: snippetPreviewDelayFormatter)
        .frame(width: 120)
        .help(Text("SnippetPreviewDelayTooltip", tableName: "AppearanceSettings"))
        .accessibilityLabel(Text("SnippetPreviewDelay", tableName: "AppearanceSettings"))
      Stepper("", value: $snippetPreviewDelay, in: 0...100_000, step: 100)
        .labelsHidden()
        .accessibilityLabel(Text("SnippetPreviewDelay", tableName: "AppearanceSettings"))
      Text("Milliseconds", tableName: "AppearanceSettings")
        .foregroundStyle(.secondary)
    }
  }

  private var menuBarSettings: some View {
    Settings.Container(contentWidth: 650) {
      Settings.Section(title: "") {
        HStack {
          Defaults.Toggle(key: .showInStatusBar) {
            Text("ShowMenuIcon", tableName: "AppearanceSettings")
          }

          Picker("", selection: $menuIcon) {
            ForEach(MenuIcon.allCases) { icon in
              Image(nsImage: icon.image)
            }
          }
          .labelsHidden()
          .scaledToFit()
          .disabled(!showInStatusBar)
          .controlSize(.small)
          .accessibilityLabel(Text("ShowMenuIcon", tableName: "AppearanceSettings"))
        }

        Defaults.Toggle(key: .showRecentCopyInMenuBar) {
          Text("ShowRecentCopyInMenuBar", tableName: "AppearanceSettings")
        }
      }
    }
  }

  // Search field is either hidden or shown with one of the visibility options.
  private var searchField: Binding<SearchVisibility?> {
    Binding {
      showSearch ? searchVisibility : nil
    } set: { visibility in
      showSearch = visibility != nil
      if let visibility {
        searchVisibility = visibility
      }
    }
  }

  // Explains an option below it. Settings.Section offers its content the full container width
  // even though the content starts after the label column, so cap the width to make text wrap.
  // Hints below checkboxes are indented by one level to line up with their text.
  private func hint(_ key: LocalizedStringKey, level: CGFloat = 0) -> some View {
    Text(key, tableName: "AppearanceSettings")
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: 380, alignment: .leading)
      .controlSize(.small)
      .font(.callout)
      .foregroundStyle(.secondary)
      .padding(.leading, level * 20)
  }

  @ViewBuilder
  private func screenPicker(for position: PopupPosition) -> some View {
    let screenBinding: Binding<Int> = Binding {
      return popupScreen
    } set: {
      popupScreen = $0
      popupAt = position
    }

    Picker(selection: screenBinding) {
      Text(labelForScreen(index: 0))
        .tag(0)

      ForEach(screens.indices, id: \.self) { index in
        Text(labelForScreen(index: index + 1))
          .tag(index + 1)
      }
    } label: {
      if popupAt == position {
        Text("\(position.description) (\(labelForScreen(index: popupScreen)))")
      } else {
        Text(position.description)
      }
    }
  }

  private func labelForScreen(index screenIndex: Int) -> String {
    switch screenIndex {
    case 0:
      return String(localized: "ActiveScreen", table: "AppearanceSettings")
    case _:
      return screens[screenIndex - 1].localizedName
    }
  }
}

#Preview {
  AppearanceSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}

// Groups of appearance settings, each shown on its own tab.
private enum AppearanceTab: CaseIterable, Identifiable {
  case popup
  case search
  case items
  case preview
  case menuBar

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .popup: return "SectionPopup"
    case .search: return "SectionSearch"
    case .items: return "SectionItems"
    case .preview: return "SectionPreview"
    case .menuBar: return "SectionMenuBar"
    }
  }
}
