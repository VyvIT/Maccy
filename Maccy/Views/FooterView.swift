import Defaults
import SwiftUI

struct FooterView: View {
  @Bindable var footer: Footer

  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags
  @Default(.showFooter) private var showFooter
  @State private var showClear = true
  @State private var showClearAll = false

  var clearAllModifiersPressed: Bool {
    let clearModifiers = footer.actionItems[0].shortcuts.first?.modifierFlags ?? []
    let clearAllModifiers = footer.actionItems[1].shortcuts.first?.modifierFlags ?? []
    return !modifierFlags.flags.isEmpty
      && !modifierFlags.flags.isSubset(of: clearModifiers)
      && modifierFlags.flags.isSubset(of: clearAllModifiers)
  }

  private var isVisible: Bool {
    Footer.isVisible(in: appState.popup.mode, showFooter: showFooter)
  }

  private var snippetsOnly: Bool {
    appState.popup.mode == .snippets
  }

  var body: some View {
    VStack(spacing: 0) {
      if !snippetsOnly {
        Divider()
          .padding(.horizontal, Popup.horizontalSeparatorPadding)
          .padding(.bottom, Popup.verticalSeparatorPadding)
      }

      if !footer.snippetItems.isEmpty || snippetsOnly {
        Text("snippets")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 10)
          .padding(.bottom, 2)
          .accessibilityAddTraits(.isHeader)

        ForEach(footer.snippetItems) { item in
          SnippetFolderItemView(item: item)
        }

        if !snippetsOnly {
          Divider()
            .padding(.horizontal, Popup.horizontalSeparatorPadding)
            .padding(.vertical, Popup.verticalSeparatorPadding)
        }
      }

      if !snippetsOnly {
        actions
      }
    }
    .invisible(!isVisible)
    .frame(maxHeight: isVisible ? nil : 0)
    .padding(.bottom, isVisible ? Popup.verticalPadding : 0)
    .readHeight(appState, into: \.popup.footerHeight)
  }

  @ViewBuilder
  private var actions: some View {
    ZStack {
      FooterItemView(item: footer.actionItems[0])
        .invisible(!showClear)
      FooterItemView(item: footer.actionItems[1])
        .invisible(!showClearAll)
    }
    .onChange(of: modifierFlags.flags) {
      if clearAllModifiersPressed {
        showClear = false
        showClearAll = true
        footer.actionItems[0].isVisible = false
        footer.actionItems[1].isVisible = true
        if appState.footer.selectedItem == footer.actionItems[0] {
          appState.navigator.select(footerItem: footer.actionItems[1])
        }
      } else {
        showClear = true
        showClearAll = false
        footer.actionItems[0].isVisible = true
        footer.actionItems[1].isVisible = false
        if appState.footer.selectedItem == footer.actionItems[1] {
          appState.navigator.select(footerItem: footer.actionItems[0])
        }
      }
    }

    ForEach(footer.actionItems.suffix(from: 2).filter(\.isVisible)) { item in
      FooterItemView(item: item)
    }
  }
}
