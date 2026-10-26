import Defaults
import SwiftUI

@Observable
class Footer: ItemsContainer {
  // Snippet folders are listed before the actions,
  // so that keyboard navigation goes through them.
  var items: [FooterItem] { snippetItems + actionItems }
  var actionItems: [FooterItem] = []
  var snippetItems: [FooterItem] = []

  var selectedItem: FooterItem? {
    willSet {
      selectedItem?.isSelected = false
      newValue?.isSelected = true
    }
    didSet {
      guard oldValue !== selectedItem else { return }
      MainActor.assumeIsolated {
        SnippetsSubmenu.shared.selectionChanged(to: selectedItem)
      }
    }
  }

  var suppressClearAlert = Binding<Bool>(
    get: { Defaults[.suppressClearAlert] },
    set: { Defaults[.suppressClearAlert] = $0 }
  )

  private var showFooter: Bool {
    return Defaults[.showFooter]
  }
  var containerVisible: Bool {
    return showFooter
  }

  init() { // swiftlint:disable:this function_body_length
    actionItems = [
      FooterItem(
        title: "clear",
        shortcuts: [KeyShortcut(key: .delete, modifierFlags: [.command, .option])],
        help: "clear_tooltip",
        confirmation: .init(
          message: "clear_alert_message",
          comment: "clear_alert_comment",
          confirm: "clear_alert_confirm",
          cancel: "clear_alert_cancel"
        ),
        suppressConfirmation: suppressClearAlert
      ) {
        Task { @MainActor in
          AppState.shared.history.clear()
        }
      },
      FooterItem(
        title: "clear_all",
        shortcuts: [KeyShortcut(key: .delete, modifierFlags: [.command, .option, .shift])],
        help: "clear_all_tooltip",
        confirmation: .init(
          message: "clear_alert_message",
          comment: "clear_alert_comment",
          confirm: "clear_alert_confirm",
          cancel: "clear_alert_cancel"
        ),
        suppressConfirmation: suppressClearAlert
      ) {
        Task { @MainActor in
          AppState.shared.history.clearAll()
        }
      },
      FooterItem(
        title: "edit_snippets",
        help: "edit_snippets_tooltip"
      ) {
        Task { @MainActor in
          AppState.shared.openSnippetsEditor()
        }
      },
      FooterItem(
        title: "preferences",
        shortcuts: [KeyShortcut(key: .comma)]
      ) {
        Task { @MainActor in
          AppState.shared.openPreferences()
        }
      },
      FooterItem(
        title: "about",
        help: "about_tooltip"
      ) {
        AppState.shared.openAbout()
      },
      FooterItem(
        title: "quit",
        shortcuts: [KeyShortcut(key: .q)],
        help: "quit_tooltip"
      ) {
        AppState.shared.quit()
      }
    ]

    Task { @MainActor in
      for await _ in Defaults.updates([.snippetFolders, .showSnippets]) {
        reloadSnippets()
      }
    }
  }

  @MainActor
  private func reloadSnippets() {
    guard Defaults[.showSnippets] else {
      snippetItems = []
      return
    }

    snippetItems = Defaults[.snippetFolders]
      .filter(\.isVisibleInPopup)
      .map { folder in
        let item = FooterItem(title: folder.title) {}
        item.snippetFolderID = folder.id
        item.action = { [weak item] in
          guard let item else { return }
          Task { @MainActor in
            SnippetsSubmenu.shared.activate(item)
          }
        }
        return item
      }
  }
}
