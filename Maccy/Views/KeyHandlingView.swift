import Carbon.HIToolbox
import Sauce
import Defaults
import SwiftUI

struct KeyHandlingView<Content: View>: View {
  @Binding var searchQuery: String
  @FocusState.Binding var searchFocused: Bool
  @ViewBuilder let content: () -> Content

  @Environment(AppState.self) private var appState

  var body: some View {
    content()
      .onKeyPress { _ in
        guard !appState.isEditingItem else { return .ignored }

        // Unfortunately, key presses don't allow access to
        // key code and don't properly work with multiple inputs,
        // so pressing ⌘, on non-English layout doesn't open
        // preferences. Stick to NSEvent to fix this behavior.

        if searchFocused {
          // Ignore input when candidate window is open
          // https://stackoverflow.com/questions/73677444/how-to-detect-the-candidate-window-when-using-japanese-keyboard
          if let inputClient = NSApp.keyWindow?.firstResponder as? NSTextInputClient,
             inputClient.hasMarkedText() {
            return .ignored
          }
        }

        if let event = NSApp.currentEvent, handleSnippetsSubmenu(event) {
          return .handled
        }

        if let event = NSApp.currentEvent, handlePreviewArrows(event) {
          return .handled
        }

        switch KeyChord(NSApp.currentEvent) {
        case .clearHistory:
          if let item = appState.footer.items.first(where: { $0.title == "clear" }),
             item.confirmation != nil,
             let suppressConfirmation = item.suppressConfirmation {
            if suppressConfirmation.wrappedValue {
              item.action()
            } else {
              item.showConfirmation = true
            }
            return .handled
          } else {
            return .ignored
          }
        case .clearHistoryAll:
          if let item = appState.footer.items.first(where: { $0.title == "clear_all" }),
             item.confirmation != nil,
             let suppressConfirmation = item.suppressConfirmation {
            if suppressConfirmation.wrappedValue {
              item.action()
            } else {
              item.showConfirmation = true
            }
            return .handled
          } else {
            return .ignored
          }
        case .clearSearch:
          searchQuery = ""
          return .handled
        case .deleteCurrentItem:
          if appState.navigator.pasteStackSelected {
            appState.removePasteStack()
          } else {
            appState.deleteSelection()
          }
          return .handled
        case .deleteOneCharFromSearch:
          searchFocused = true
          _ = searchQuery.popLast()
          return .handled
        case .deleteLastWordFromSearch:
          searchFocused = true
          let newQuery = searchQuery.split(separator: " ").dropLast().joined(separator: " ")
          if newQuery.isEmpty {
            searchQuery = ""
          } else {
            searchQuery = "\(newQuery) "
          }

          return .handled
        case .moveToNext:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          appState.navigator.highlightNext()
          return .handled
        case .moveToLast:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          appState.navigator.highlightLast()
          return .handled
        case .moveToPrevious:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          appState.navigator.highlightPrevious()
          return .handled
        case .moveToFirst:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          appState.navigator.highlightFirst()
          return .handled
        case .extendToNext:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }
          guard AppState.shared.multiSelectionEnabled else {
            return .ignored
          }
          appState.navigator.extendHighlightToNext()
          return .handled
        case .extendToLast:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }
          guard AppState.shared.multiSelectionEnabled else {
            return .ignored
          }
          appState.navigator.extendHighlightToLast()
          return .handled
        case .extendToPrevious:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }
          guard AppState.shared.multiSelectionEnabled else {
            return .ignored
          }
          appState.navigator.extendHighlightToPrevious()
          return .handled
        case .extendToFirst:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }
          guard AppState.shared.multiSelectionEnabled else {
            return .ignored
          }
          appState.navigator.extendHighlightToFirst()
          return .handled
        case .openPreferences:
          appState.openPreferences()
          return .handled
        case .pinOrUnpin:
          appState.togglePin()
          return .handled
        case .selectCurrentItem:
          appState.select(flags: .currentModifierFlags)
          return .handled
        case .close:
          appState.popup.close()
          return .handled
        case .togglePreview:
          appState.preview.togglePreview()
          return .handled
        default:
          ()
        }

        if let item = appState.history.pressedShortcutItem {
          appState.navigator.select(item: item)
          Task {
            try? await Task.sleep(for: .milliseconds(50))
            appState.history.select(item, flags: .currentModifierFlags)
          }
          return .handled
        }

        return .ignored
      }
  }

  // Snippet folder submenu takes arrow keys, Return and number keys once entered with →,
  // and gives them back to the popup when left with ← or Escape.
  @MainActor
  private func handleSnippetsSubmenu(_ event: NSEvent) -> Bool {
    let submenu = SnippetsSubmenu.shared
    let modifierFlags = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.function, .numericPad])

    guard submenu.isActive else {
      guard let item = appState.footer.selectedItem,
            item.snippetFolderID != nil,
            modifierFlags.isEmpty,
            [.rightArrow, .carriageReturn, .enter].contains(event.specialKey) else { return false }

      submenu.activate(item)
      return true
    }

    let arrowKeyPreviews = Defaults[.previewOpening] == .arrowKeys && modifierFlags.isEmpty

    switch event.specialKey {
    case .rightArrow where arrowKeyPreviews:
      submenu.showHighlightedPreview()
      return true
    case .leftArrow where arrowKeyPreviews && submenu.isPreviewVisible:
      submenu.hidePreview()
      return true
    case .upArrow:
      submenu.moveHighlight(by: -1)
      return true
    case .downArrow:
      submenu.moveHighlight(by: 1)
      return true
    case .leftArrow:
      submenu.close()
      return true
    case .carriageReturn, .enter:
      submenu.chooseHighlighted(modifierFlags: modifierFlags)
      return true
    default:
      break
    }

    if Int(event.keyCode) == kVK_Escape {
      submenu.close()
      return true
    }

    if modifierFlags.isEmpty,
       let characters = event.charactersIgnoringModifiers,
       let index = SnippetsSubmenu.numberKeys.firstIndex(of: characters) {
      submenu.choose(index, modifierFlags: modifierFlags)
      return true
    }

    // Any other key, e.g. typing a search, goes back to the popup.
    submenu.close()
    return false
  }

  // With arrow key previews, → opens the preview of the selected history item and ← closes it.
  // While typing a search, → still moves the cursor until it reaches the end.
  @MainActor
  private func handlePreviewArrows(_ event: NSEvent) -> Bool {
    let modifierFlags = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.function, .numericPad])
    guard Defaults[.previewOpening] == .arrowKeys, modifierFlags.isEmpty else { return false }

    let preview = appState.preview
    let navigator = appState.navigator
    switch event.specialKey {
    case .rightArrow:
      guard !preview.state.isOpen,
            navigator.leadHistoryItem != nil || navigator.pasteStackSelected,
            isCursorAtEndOfSearch else { return false }
    case .leftArrow:
      guard preview.state.isOpen else { return false }
    default:
      return false
    }

    preview.togglePreview()
    return true
  }

  private var isCursorAtEndOfSearch: Bool {
    guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return true }

    let selection = textView.selectedRange()
    return selection.length == 0 && selection.location >= (textView.string as NSString).length
  }
}
