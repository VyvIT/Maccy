import AppKit
import Defaults
import SwiftUI

// Submenu with snippets of the selected folder, shown next to the popup.
// Unlike a native menu, it doesn't take over the keyboard, so arrow keys
// keep moving through the popup until the submenu is entered with →.
// Based on snippets menu in https://github.com/Clipy/Clipy.
@MainActor
@Observable
class SnippetsSubmenu {
  static let shared = SnippetsSubmenu()

  // Keys 1-9 and 0 choose the first ten snippets like in Clipy.
  static let numberKeys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

  private static let width: CGFloat = 260
  private static let spacing: CGFloat = 4
  private static let previewSpacing: CGFloat = 6
  // Short delays so that the submenu doesn't flicker while the pointer passes by
  // and stays open while the pointer moves from the folder to the submenu.
  private static let hoverOpenDelay: Duration = .milliseconds(150)
  private static let hoverCloseDelay: Duration = .milliseconds(250)

  private(set) var folder: SnippetFolder?
  // Highlighted snippet, set once the submenu is entered with the keyboard or the pointer.
  var highlightedIndex: Int? {
    didSet { highlightChanged() }
  }

  var snippets: [Snippet] { folder?.snippets.filter(\.isEnabled) ?? [] }
  var isOpen: Bool { folder != nil }
  var isActive: Bool { highlightedIndex != nil }

  @ObservationIgnored private weak var folderItem: FooterItem?
  @ObservationIgnored private var opensToRight = true
  @ObservationIgnored private var panel: NSPanel?
  @ObservationIgnored private var previewPanel: NSPanel?
  @ObservationIgnored private var previewView: NSHostingView<SnippetPreviewView>?
  @ObservationIgnored private var openTask: Task<Void, Never>?
  @ObservationIgnored private var closeTask: Task<Void, Never>?
  @ObservationIgnored private var previewTask: Task<Void, Never>?
  @ObservationIgnored private var popupObservers: [NSObjectProtocol] = []

  private var isKeyboardNavigating: Bool { AppState.shared.navigator.isKeyboardNavigating }

  // MARK: - Opening and closing

  // Follows the popup selection: selected folder shows its snippets.
  func selectionChanged(to item: FooterItem?) {
    openTask?.cancel()

    guard let item, item.snippetFolderID != nil else {
      guard isOpen else { return }
      if isKeyboardNavigating {
        close()
      } else {
        closeTask = Task {
          try? await Task.sleep(for: Self.hoverCloseDelay)
          guard !Task.isCancelled, !isPointerInPanel else { return }
          close()
        }
      }
      return
    }

    closeTask?.cancel()
    guard item !== folderItem else { return }

    if isKeyboardNavigating {
      open(item)
    } else {
      openTask = Task {
        try? await Task.sleep(for: Self.hoverOpenDelay)
        guard !Task.isCancelled else { return }
        open(item)
      }
    }
  }

  // Opens the folder and highlights its first snippet.
  func activate(_ item: FooterItem) {
    if item !== folderItem || !isOpen {
      open(item)
    }
    if !snippets.isEmpty {
      highlightedIndex = 0
    }
  }

  func close() {
    openTask?.cancel()
    closeTask?.cancel()
    folder = nil
    folderItem = nil
    highlightedIndex = nil
    panel?.orderOut(nil)
    hidePreview()
  }

  private func open(_ item: FooterItem) {
    guard let folderID = item.snippetFolderID,
          let folder = Defaults[.snippetFolders].first(where: { $0.id == folderID }),
          folder.isVisibleInPopup,
          AppState.shared.appDelegate?.panel.isPresented == true else { return }

    highlightedIndex = nil
    self.folder = folder
    folderItem = item
    observePopup()

    let panel = panel ?? makePanel()
    self.panel = panel
    layout()
    panel.orderFrontRegardless()
  }

  // MARK: - Choosing

  func moveHighlight(by offset: Int) {
    guard !snippets.isEmpty else { return }

    let index = (highlightedIndex ?? -offset) + offset
    highlightedIndex = min(max(index, 0), snippets.count - 1)
  }

  func choose(_ index: Int, modifierFlags: NSEvent.ModifierFlags) {
    guard snippets.indices.contains(index) else { return }

    let content = snippets[index].content
    close()
    AppState.shared.pasteSnippet(content, modifierFlags: modifierFlags)
  }

  func chooseHighlighted(modifierFlags: NSEvent.ModifierFlags) {
    guard let highlightedIndex else { return }
    choose(highlightedIndex, modifierFlags: modifierFlags)
  }

  // Pointer over a snippet highlights it and keeps the folder selected in the popup.
  func hover(_ index: Int) {
    closeTask?.cancel()
    highlightedIndex = index
    if let folderItem, AppState.shared.footer.selectedItem !== folderItem {
      AppState.shared.navigator.selectWithoutScrolling(id: folderItem.id)
    }
  }

  // MARK: - Layout

  private var isPointerInPanel: Bool {
    guard let panel, panel.isVisible else { return false }
    return panel.frame.contains(NSEvent.mouseLocation)
  }

  private func makePanel() -> NSPanel {
    let panel = SnippetsSubmenuPanel()
    panel.contentView = FirstMouseHostingView(rootView: SnippetsSubmenuView(submenu: self))
    return panel
  }

  // Places the submenu next to the popup, level with the folder row.
  private func layout() {
    guard let panel,
          let popup = AppState.shared.appDelegate?.panel,
          let folderItem,
          let rowFrame = AppState.shared.screenFrame(of: folderItem, in: popup) else { return }

    let screen = NSScreen.screens.first { $0.frame.intersects(rowFrame) } ?? NSScreen.main
    let visibleFrame = screen?.visibleFrame ?? .zero
    let height = min(
      CGFloat(max(snippets.count, 1)) * Popup.itemHeight + 2 * Popup.verticalPadding,
      visibleFrame.height
    )

    opensToRight = popup.frame.maxX + Self.spacing + Self.width <= visibleFrame.maxX
    let x = opensToRight ? popup.frame.maxX + Self.spacing : popup.frame.minX - Self.spacing - Self.width
    let top = min(rowFrame.maxY + Popup.verticalPadding, visibleFrame.maxY)
    let y = max(top - height, visibleFrame.minY)

    panel.setFrame(NSRect(x: x, y: y, width: Self.width, height: height), display: true)
    if previewPanel?.isVisible == true {
      layoutPreview()
    }
  }

  // Keeps the submenu attached when the popup resizes, e.g. when the preview closes.
  private func observePopup() {
    guard popupObservers.isEmpty, let popup = AppState.shared.appDelegate?.panel else { return }

    for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
      popupObservers.append(NotificationCenter.default.addObserver(
        forName: name,
        object: popup,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, self.isOpen else { return }
          self.layout()
        }
      })
    }
  }

  // MARK: - Preview

  private func highlightChanged() {
    previewTask?.cancel()
    guard let highlightedIndex, snippets.indices.contains(highlightedIndex) else {
      hidePreview()
      return
    }

    let snippet = snippets[highlightedIndex]
    // Once open, the preview follows the highlighted snippet like in the popup.
    if previewPanel?.isVisible == true {
      showPreview(snippet)
      return
    }

    guard Defaults[.openPreviewAutomatically] else { return }

    previewTask = Task {
      try? await Task.sleep(for: .milliseconds(Defaults[.snippetPreviewDelay]))
      guard !Task.isCancelled, self.highlightedIndex != nil else { return }
      showPreview(snippet)
    }
  }

  private func showPreview(_ snippet: Snippet) {
    let rootView = SnippetPreviewView(snippet: snippet, folderTitle: folder?.title ?? "")
    if let previewView {
      previewView.rootView = rootView
    } else {
      let panel = SnippetsSubmenuPanel()
      panel.ignoresMouseEvents = true
      let view = NSHostingView(rootView: rootView)
      panel.contentView = view
      previewPanel = panel
      previewView = view
    }

    layoutPreview()
    previewPanel?.orderFrontRegardless()
  }

  private func hidePreview() {
    previewTask?.cancel()
    previewPanel?.orderOut(nil)
  }

  // Places the preview beyond the submenu, or on the other side of the popup when there is no room.
  private func layoutPreview() {
    guard let previewPanel, let panel, let popup = AppState.shared.appDelegate?.panel else { return }

    let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
    let width = Defaults[.previewWidth]
    let height = min(max(popup.frame.height, Popup.minimumPreviewHeight), 400)

    let rightX = panel.frame.maxX + Self.previewSpacing
    let leftX = (opensToRight ? popup.frame.minX : panel.frame.minX) - Self.previewSpacing - width
    let x = opensToRight && rightX + width <= visibleFrame.maxX ? rightX : leftX
    let y = max(visibleFrame.minY, min(panel.frame.maxY - height, visibleFrame.maxY - height))

    previewPanel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
  }

  // Snippets are plain text, so formatting can be ignored and
  // the only question is whether to paste after copying.
  static func shouldPaste(_ modifierFlags: NSEvent.ModifierFlags) -> Bool {
    if modifierFlags.isEmpty {
      return Defaults[.pasteByDefault]
    }

    switch HistoryItemAction(modifierFlags) {
    case .paste, .pasteWithoutFormatting:
      return true
    case .copy:
      return false
    case .unknown:
      return Defaults[.pasteByDefault]
    }
  }
}

// Floats above the popup without taking the keyboard from it.
private class SnippetsSubmenuPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  init() {
    super.init(
      contentRect: .zero,
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: true
    )
    level = .popUpMenu
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    animationBehavior = .none
    collectionBehavior = [.auxiliary, .moveToActiveSpace, .fullScreenAuxiliary]
  }
}

// Reacts to the first click even though the panel never becomes key.
private class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
