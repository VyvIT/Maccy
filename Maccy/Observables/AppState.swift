import AppKit
import Defaults
import Foundation
import Settings
import SwiftUI

@Observable
class AppState: Sendable {
  static let shared = AppState(history: History.shared, footer: Footer())

  let multiSelectionEnabled = false

  var appDelegate: AppDelegate?
  var popup: Popup
  var history: History
  var footer: Footer
  var navigator: NavigationManager
  var preview: SlideoutController

  var isEditingItem: Bool = false
  // Hidden passwords show while the reveal key is held in the popup.
  var isPasswordRevealKeyHeld = false
  @ObservationIgnored private var passwordRevealMonitor: Any?
  @ObservationIgnored private var passwordRevealReleaseTimer: Timer?
  var suppressPopupAutoClose: Bool {
    return navigator.isDragAndDropInProgress || isEditingItem
  }

  var searchVisible: Bool {
    if !Defaults[.showSearch] || popup.mode == .snippets { return false }
    switch Defaults[.searchVisibility] {
    case .always: return true
    case .duringSearch: return !history.searchQuery.isEmpty
    }
  }

  var menuIconText: String {
    var title = history.firstUnpinnedItem?.safeTitle.shortened(to: 100)
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    title.unicodeScalars.removeAll(where: CharacterSet.newlines.contains)
    return title.shortened(to: 20)
  }

  private let about = About()
  private var settingsWindowController: SettingsWindowController?

  init(history: History, footer: Footer) {
    self.history = history
    self.footer = footer
    popup = Popup()
    navigator = NavigationManager(history: history, footer: footer)
    preview = SlideoutController(
      onContentResize: { contentWidth in
        Defaults[.windowSize].width = contentWidth
      },
      onSlideoutResize: { previewWidth in
        Defaults[.previewWidth] = previewWidth
      })
    preview.contentWidth = Defaults[.windowSize].width
    preview.slideoutWidth = Defaults[.previewWidth]
    passwordRevealMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      self?.updatePasswordReveal(AppState.currentModifierFlags)
      return event
    }
  }

  // Keys physically held down. The session state can keep fn held when the system
  // takes its release, e.g. after holding fn long enough for dictation or the emoji picker.
  private static var currentModifierFlags: NSEvent.ModifierFlags {
    NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.hidSystemState).rawValue))
  }

  func updatePasswordReveal(_ modifierFlags: NSEvent.ModifierFlags) {
    let isHeld = Defaults[.passwordRevealKey].isHeld(in: modifierFlags)
    if isHeld != isPasswordRevealKeyHeld {
      isPasswordRevealKeyHeld = isHeld
    }
    watchPasswordRevealKeyRelease()
  }

  func endPasswordReveal() {
    passwordRevealReleaseTimer?.invalidate()
    passwordRevealReleaseTimer = nil
    isPasswordRevealKeyHeld = false
  }

  // Releasing fn doesn't always send an event, so the key is checked while it's held.
  private func watchPasswordRevealKeyRelease() {
    guard isPasswordRevealKeyHeld else {
      passwordRevealReleaseTimer?.invalidate()
      passwordRevealReleaseTimer = nil
      return
    }
    guard passwordRevealReleaseTimer == nil else { return }

    passwordRevealReleaseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        if !Defaults[.passwordRevealKey].isHeld(in: Self.currentModifierFlags) {
          self.endPasswordReveal()
        }
      }
    }
  }

  @MainActor
  func select(flags modifierFlags: NSEvent.ModifierFlags) {
    if !navigator.selection.isEmpty {
      if navigator.isMultiSelectInProgress {
        navigator.isManualMultiSelect = false
        history.startPasteStack(selection: &navigator.selection, flags: modifierFlags)
      } else {
        history.select(navigator.selection.first, flags: modifierFlags)
      }
    } else if let item = footer.selectedItem {
      // TODO: Use item.suppressConfirmation, but it's not updated!
      if item.confirmation != nil, Defaults[.suppressClearAlert] == false {
        item.showConfirmation = true
      } else {
        item.action()
      }
    } else {
      Clipboard.shared.copyInMaccy(history.searchQuery)
      history.searchQuery = ""
    }
  }

  @MainActor
  func togglePin() {
    withTransaction(Transaction()) {
      navigator.selection.forEach { _, item in
        history.togglePin(item)
      }
    }
  }

  @MainActor
  func removePasteStack() {
    history.interruptPasteStack()
    navigator.highlightFirst()
  }

  @MainActor
  func deleteSelection() {
    guard let leadItem = navigator.leadHistoryItem else { return }
    let nextUnselectedItem = history.nearestVisible(to: leadItem) { !$0.isSelected }

    withTransaction(Transaction()) {
      navigator.selection.forEach { _, item in
        history.delete(item)
      }
      navigator.select(item: nextUnselectedItem)
    }
  }

  func openAbout() {
    about.openAbout(nil)
  }

  @MainActor
  func pasteSnippet(_ content: String, modifierFlags: NSEvent.ModifierFlags) {
    popup.close()
    Clipboard.shared.copyInMaccy(content)
    if SnippetsSubmenu.shouldPaste(modifierFlags) {
      Clipboard.shared.paste()
    }
  }

  @MainActor
  func screenFrame(of item: FooterItem, in window: NSWindow) -> NSRect? {
    guard let contentView = window.contentView, item.windowFrame != .zero else { return nil }

    // SwiftUI global frames are flipped relative to the window.
    let origin = window.convertPoint(toScreen: NSPoint(
      x: item.windowFrame.minX,
      y: contentView.bounds.height - item.windowFrame.maxY
    ))
    return NSRect(origin: origin, size: item.windowFrame.size)
  }

  @MainActor
  func openSnippetsEditor() {
    popup.close()
    SnippetsEditorWindowController.shared.show()
  }

  @MainActor
  func openPreferences() { // swiftlint:disable:this function_body_length
    if settingsWindowController == nil {
      let generalTitle = NSLocalizedString("Title", tableName: "GeneralSettings", comment: "")
      let storageTitle = NSLocalizedString("Title", tableName: "StorageSettings", comment: "")
      let appearanceTitle = NSLocalizedString("Title", tableName: "AppearanceSettings", comment: "")
      let ignoreTitle = NSLocalizedString("Title", tableName: "IgnoreSettings", comment: "")
      let advancedTitle = NSLocalizedString("Title", tableName: "AdvancedSettings", comment: "")
      let toolbarTitles = [generalTitle, storageTitle, appearanceTitle, ignoreTitle, advancedTitle]
      let titleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
      let titleWidth = toolbarTitles.reduce(CGFloat.zero) {
        $0 + ($1 as NSString).size(withAttributes: titleAttributes).width
      }
      let toolbarItemSpacing: CGFloat = 24
      let toolbarEdgeSpacing: CGFloat = 40
      let toolbarWidth = titleWidth + CGFloat(toolbarTitles.count) * toolbarItemSpacing + toolbarEdgeSpacing
      let minimumWidth = max(500, ceil(toolbarWidth))
      settingsWindowController = SettingsWindowController(
        panes: [
          Settings.Pane(
            identifier: Settings.PaneIdentifier.general,
            title: generalTitle,
            toolbarIcon: NSImage.gearshape!
          ) {
            GeneralSettingsPane()
              .frame(minWidth: minimumWidth)
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.storage,
            title: storageTitle,
            toolbarIcon: NSImage.externaldrive!
          ) {
            StorageSettingsPane()
              .frame(minWidth: minimumWidth)
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.appearance,
            title: appearanceTitle,
            toolbarIcon: NSImage.paintpalette!
          ) {
            AppearanceSettingsPane()
              .frame(minWidth: minimumWidth)
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.ignore,
            title: ignoreTitle,
            toolbarIcon: NSImage.nosign!
          ) {
            IgnoreSettingsPane()
              .frame(minWidth: minimumWidth)
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.advanced,
            title: advancedTitle,
            toolbarIcon: NSImage.gearshape2!
          ) {
            AdvancedSettingsPane()
              .frame(minWidth: minimumWidth)
          }
        ]
      )
    }
    settingsWindowController?.show()
    settingsWindowController?.window?.orderFrontRegardless()
  }

  func quit() {
    NSApp.terminate(self)
  }
}
