import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct SnippetsEditorView: View { // swiftlint:disable:this type_body_length
  // Position of a folder or snippet in the folders list.
  private struct Location {
    var folder: Int
    var snippet: Int?
  }

  @Default(.snippetFolders) private var folders

  @State private var selection: UUID?
  @State private var expandedFolders: Set<UUID> = []
  @State private var renamingID: UUID?
  @State private var titleBeforeRename = ""
  @State private var folderToDelete: SnippetFolder?
  @State private var showImportError = false
  @State private var searchQuery = ""
  @State private var dropTargetID: UUID?

  @FocusState private var renameFocused: Bool

  private var isSearching: Bool {
    !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private var visibleFolders: [SnippetFolder] {
    folders.filtered(by: searchQuery)
  }

  private var selectedLocation: Location? {
    location(of: selection)
  }

  private var selectedIsEnabled: Bool {
    guard let location = selectedLocation else { return false }
    if let snippetIndex = location.snippet {
      return folders[location.folder].snippets[snippetIndex].isEnabled
    }
    return folders[location.folder].isEnabled
  }

  var body: some View {
    ZStack {
      if #available(macOS 26.0, *) {
        GlassEffectView()
          .ignoresSafeArea()
      } else {
        VisualEffectView(material: .sidebar)
          .ignoresSafeArea()
      }

      VStack(spacing: 0) {
        toolbar
        Divider()
        HSplitView {
          sidebar
            .frame(minWidth: 200, idealWidth: 250, maxWidth: 400)
          detail
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
    .alert(
      Text("snippets_editor_import_failed"),
      isPresented: $showImportError
    ) {}
    .confirmationDialog(
      Text("snippets_editor_delete_folder_message \(folderToDelete?.title ?? "")"),
      isPresented: Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } })
    ) {
      Button("snippets_editor_delete", role: .destructive) {
        if let folder = folderToDelete {
          remove(id: folder.id)
        }
      }
      Button("snippets_editor_cancel", role: .cancel) {}
    } message: {
      Text("snippets_editor_delete_folder_comment")
    }
  }

  // MARK: - Toolbar

  private var toolbar: some View {
    HStack(spacing: 4) {
      SnippetsToolbarButton(title: "snippets_editor_add_snippet", systemImage: "doc.badge.plus") {
        addSnippet()
      }
      SnippetsToolbarButton(title: "snippets_editor_add_folder", systemImage: "folder.badge.plus") {
        addFolder()
      }
      SnippetsToolbarButton(title: "snippets_editor_delete", systemImage: "trash") {
        requestRemoveSelection()
      }
      .disabled(selection == nil)
      SnippetsToolbarButton(
        title: selectedIsEnabled || selection == nil ? "snippets_editor_disable" : "snippets_editor_enable",
        systemImage: selectedIsEnabled || selection == nil ? "eye.slash" : "eye"
      ) {
        toggleSelectionEnabled()
      }
      .disabled(selection == nil)

      Spacer()

      SnippetsToolbarButton(title: "snippets_editor_import", systemImage: "square.and.arrow.down") {
        importSnippets()
      }
      SnippetsToolbarButton(title: "snippets_editor_export", systemImage: "square.and.arrow.up") {
        exportSnippets()
      }
      .disabled(folders.isEmpty)
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 8)
  }

  // MARK: - Sidebar

  private var sidebar: some View {
    VStack(spacing: 0) {
      SearchFieldView(placeholder: "snippets_editor_search", query: $searchQuery)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)

      list
    }
  }

  private var list: some View {
    List(selection: $selection) {
      ForEach(visibleFolders) { folder in
        DisclosureGroup(isExpanded: expandedBinding(folder.id)) {
          ForEach(folder.snippets) { snippet in
            row(
              id: snippet.id,
              title: snippet.title,
              systemImage: "doc.text",
              isEnabled: folder.isEnabled && snippet.isEnabled
            )
          }
        } label: {
          row(
            id: folder.id,
            title: folder.title,
            systemImage: "folder",
            isEnabled: folder.isVisibleInPopup,
            count: folder.snippets.count
          )
        }
      }
    }
    .listStyle(.sidebar)
    .scrollContentBackground(.hidden)
    .contextMenu(forSelectionType: UUID.self) { ids in
      if let id = ids.first {
        if snippet(id) != nil {
          Button("snippets_editor_copy") { copySnippet(id) }
            .keyboardShortcut("c")
        }
        Button("snippets_editor_paste") { pasteSnippet(at: id) }
          .keyboardShortcut("v")
          .disabled(NSPasteboard.general.availableType(from: [.snippet]) == nil)
        if snippet(id) != nil {
          Button("snippets_editor_duplicate") { duplicateSnippet(id) }
            .keyboardShortcut("d")
        }
        Divider()
        Button("snippets_editor_rename") { startRename(id) }
        Button(isEnabled(id) ? "snippets_editor_disable" : "snippets_editor_enable") {
          selection = id
          toggleSelectionEnabled()
        }
        Divider()
        Button("snippets_editor_delete", role: .destructive) {
          selection = id
          requestRemoveSelection()
        }
      }
    } primaryAction: { ids in
      // Double click renames like in Finder.
      if let id = ids.first {
        startRename(id)
      }
    }
    .onDeleteCommand {
      requestRemoveSelection()
    }
    .onReceive(NotificationCenter.default.publisher(for: .snippetsEditorCommand)) { notification in
      guard let command = notification.object as? SnippetsEditorCommand, let id = selection else { return }

      switch command {
      case .copy:
        copySnippet(id)
      case .paste:
        pasteSnippet(at: id)
      case .duplicate:
        duplicateSnippet(id)
      }
    }
    .overlay {
      if isSearching && visibleFolders.isEmpty {
        Text("snippets_editor_no_results")
          .foregroundStyle(.secondary)
          .padding()
      } else if folders.isEmpty {
        Text("snippets_editor_empty")
          .multilineTextAlignment(.center)
          .foregroundStyle(.secondary)
          .padding()
      }
    }
  }

  @ViewBuilder
  private func row(id: UUID, title: String, systemImage: String, isEnabled: Bool, count: Int? = nil) -> some View {
    HStack(spacing: 6) {
      Image(systemName: systemImage)
        .foregroundStyle(isEnabled ? Color.accentColor : .secondary)

      if renamingID == id {
        TextField("", text: titleBinding(id))
          .textFieldStyle(.plain)
          .focused($renameFocused)
          .onSubmit { finishRename() }
          .onExitCommand { cancelRename() }
      } else {
        Text(verbatim: title)
          .lineLimit(1)
          .foregroundStyle(isEnabled ? .primary : .secondary)
      }

      Spacer(minLength: 0)

      if let count {
        Text(verbatim: "\(count)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    }
    .padding(.horizontal, 4)
    .background(
      dropTargetID == id ? Color.accentColor.opacity(0.25) : .clear,
      in: RoundedRectangle(cornerRadius: 4)
    )
    .draggable(id.uuidString)
    .dropDestination(for: String.self) { items, _ in
      guard let draggedID = items.first.flatMap(UUID.init(uuidString:)) else { return false }
      return move(draggedID, onto: id)
    } isTargeted: { isTargeted in
      if isTargeted {
        dropTargetID = id
      } else if dropTargetID == id {
        dropTargetID = nil
      }
    }
    .tag(id)
  }

  // MARK: - Detail

  @ViewBuilder
  private var detail: some View {
    if let location = selectedLocation, let snippetIndex = location.snippet {
      snippetDetail(
        folder: folders[location.folder],
        snippet: folders[location.folder].snippets[snippetIndex]
      )
    } else if let location = selectedLocation {
      folderDetail(folders[location.folder])
    } else {
      Text("snippets_editor_no_selection")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func folderDetail(_ folder: SnippetFolder) -> some View {
    let enabledCount = folder.snippets.filter(\.isEnabled).count

    return VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Image(systemName: "folder")
          .font(.system(size: 34))
          .foregroundStyle(folder.isVisibleInPopup ? Color.accentColor : .secondary)
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: folder.title)
            .font(.title2.weight(.semibold))
            .lineLimit(2)
          Text("snippets_editor_folder_count \(folder.snippets.count) \(enabledCount)")
            .foregroundStyle(.secondary)
        }
      }

      Label(
        folder.isVisibleInPopup ? "snippets_editor_folder_visible" : "snippets_editor_folder_hidden",
        systemImage: folder.isVisibleInPopup ? "eye" : "eye.slash"
      )
      .foregroundStyle(.secondary)

      HStack {
        Button("snippets_editor_add_snippet") {
          addSnippet()
        }
        Button("snippets_editor_rename") {
          startRename(folder.id)
        }
      }

      Spacer()
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .id(folder.id)
  }

  private func snippetDetail(folder: SnippetFolder, snippet: Snippet) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: snippet.title)
            .font(.title3.weight(.semibold))
            .lineLimit(1)
          Text(verbatim: folder.title)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Toggle(isOn: snippetBinding(snippet.id, \.isEnabled)) {
          Text("snippets_editor_show_in_popup")
        }
        .toggleStyle(.switch)
        .controlSize(.small)
      }

      TextEditor(text: snippetBinding(snippet.id, \.content))
        .font(.body.monospaced())
        .scrollContentBackground(.hidden)
        .padding(6)
        .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))

      Text("snippets_editor_characters \(snippet.content.count)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
    .padding(16)
    .id(snippet.id)
  }

  // MARK: - Lookup

  private func location(of id: UUID?) -> Location? {
    guard let id, let location = folders.location(of: id) else { return nil }
    return Location(folder: location.folder, snippet: location.snippet)
  }

  private func snippet(_ id: UUID) -> Snippet? {
    guard let location = location(of: id), let snippetIndex = location.snippet else { return nil }
    return folders[location.folder].snippets[snippetIndex]
  }

  private func isEnabled(_ id: UUID) -> Bool {
    guard let location = location(of: id) else { return false }
    if let snippetIndex = location.snippet {
      return folders[location.folder].snippets[snippetIndex].isEnabled
    }
    return folders[location.folder].isEnabled
  }

  private func expandedBinding(_ id: UUID) -> Binding<Bool> {
    Binding(
      // Show all matches while searching.
      get: { isSearching || expandedFolders.contains(id) },
      set: { isExpanded in
        if isExpanded {
          expandedFolders.insert(id)
        } else {
          expandedFolders.remove(id)
        }
      }
    )
  }

  // Bindings look the item up by its identifier, so they stay valid
  // when the item is moved or removed while it is being edited.
  private func snippetBinding<Value>(_ id: UUID, _ keyPath: WritableKeyPath<Snippet, Value>) -> Binding<Value> {
    let fallback = folders.lazy.flatMap(\.snippets).first(where: { $0.id == id })?[keyPath: keyPath]
    return Binding(
      get: { folders.lazy.flatMap(\.snippets).first(where: { $0.id == id })?[keyPath: keyPath] ?? fallback! },
      set: { newValue in
        guard let location = location(of: id), let snippetIndex = location.snippet else { return }
        folders[location.folder].snippets[snippetIndex][keyPath: keyPath] = newValue
      }
    )
  }

  private func titleBinding(_ id: UUID) -> Binding<String> {
    Binding(
      get: {
        guard let location = location(of: id) else { return "" }
        if let snippetIndex = location.snippet {
          return folders[location.folder].snippets[snippetIndex].title
        }
        return folders[location.folder].title
      },
      set: { newValue in
        guard let location = location(of: id) else { return }
        if let snippetIndex = location.snippet {
          folders[location.folder].snippets[snippetIndex].title = newValue
        } else {
          folders[location.folder].title = newValue
        }
      }
    )
  }

  // MARK: - Actions

  private func addFolder() {
    let folder = SnippetFolder(title: NSLocalizedString("snippets_editor_new_folder", comment: ""))
    folders.append(folder)
    expandedFolders.insert(folder.id)
    selection = folder.id
    startRename(folder.id)
  }

  private func addSnippet() {
    if folders.isEmpty {
      let folder = SnippetFolder(title: NSLocalizedString("snippets_editor_new_folder", comment: ""))
      folders.append(folder)
    }

    let folderIndex = selectedLocation?.folder ?? folders.count - 1
    let snippet = Snippet(title: NSLocalizedString("snippets_editor_new_snippet", comment: ""), content: "")
    folders[folderIndex].snippets.append(snippet)
    expandedFolders.insert(folders[folderIndex].id)
    selection = snippet.id
    startRename(snippet.id)
  }

  private func requestRemoveSelection() {
    guard let location = selectedLocation else { return }

    let folder = folders[location.folder]
    if location.snippet == nil, !folder.snippets.isEmpty {
      folderToDelete = folder
    } else if let id = selection {
      remove(id: id)
    }
  }

  private func remove(id: UUID) {
    guard let location = location(of: id) else { return }

    if renamingID == id {
      renamingID = nil
    }
    selection = nil
    if let snippetIndex = location.snippet {
      folders[location.folder].snippets.remove(at: snippetIndex)
    } else {
      expandedFolders.remove(id)
      folders.remove(at: location.folder)
    }
  }

  private func move(_ draggedID: UUID, onto targetID: UUID) -> Bool {
    var updatedFolders = folders
    guard updatedFolders.move(draggedID, onto: targetID) else { return false }

    folders = updatedFolders
    if let target = location(of: targetID), target.snippet == nil, location(of: draggedID)?.snippet != nil {
      expandedFolders.insert(targetID)
    }
    selection = draggedID
    return true
  }

  // Copies go through the clipboard as a snippet-only type,
  // which the history ignores, so that they can be pasted in any folder.
  private func copySnippet(_ id: UUID) {
    guard let snippet = snippet(id), let data = try? JSONEncoder().encode(snippet) else { return }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setData(data, forType: .snippet)
  }

  private func pasteSnippet(at id: UUID?) {
    guard let id,
          let data = NSPasteboard.general.data(forType: .snippet),
          let snippet = try? JSONDecoder().decode(Snippet.self, from: data) else { return }

    insertCopy(of: snippet, at: id)
  }

  private func duplicateSnippet(_ id: UUID) {
    guard let snippet = snippet(id) else { return }
    insertCopy(of: snippet, at: id)
  }

  private func insertCopy(of snippet: Snippet, at id: UUID) {
    var updatedFolders = folders
    guard let copyID = updatedFolders.paste(snippet, at: id),
          let folderIndex = updatedFolders.location(of: copyID)?.folder else { return }

    folders = updatedFolders
    expandedFolders.insert(folders[folderIndex].id)
    selection = copyID
  }

  private func toggleSelectionEnabled() {
    guard let location = selectedLocation else { return }

    if let snippetIndex = location.snippet {
      folders[location.folder].snippets[snippetIndex].isEnabled.toggle()
    } else {
      folders[location.folder].isEnabled.toggle()
    }
  }

  private func startRename(_ id: UUID) {
    finishRename()
    titleBeforeRename = titleBinding(id).wrappedValue
    selection = id
    renamingID = id
    // Focus the field once it replaces the title.
    DispatchQueue.main.async {
      renameFocused = true
    }
  }

  private func finishRename() {
    guard let id = renamingID else { return }

    let title = titleBinding(id)
    if title.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      title.wrappedValue = titleBeforeRename
    }
    renamingID = nil
  }

  private func cancelRename() {
    guard let id = renamingID else { return }

    titleBinding(id).wrappedValue = titleBeforeRename
    renamingID = nil
  }

  private func importSnippets() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.xml]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      let imported = try SnippetsXML.decode(Data(contentsOf: url))
      folders.append(contentsOf: imported)
      expandedFolders.formUnion(imported.map(\.id))
      selection = imported.first?.id
    } catch {
      showImportError = true
    }
  }

  private func exportSnippets() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.xml]
    panel.nameFieldStringValue = "snippets.xml"
    guard panel.runModal() == .OK, let url = panel.url else { return }

    try? SnippetsXML.encode(folders).write(to: url, options: .atomic)
  }
}

private struct SnippetsToolbarButton: View {
  let title: LocalizedStringKey
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: systemImage)
          .font(.system(size: 16))
          .frame(height: 20)
        Text(title)
          .font(.caption)
      }
      .frame(minWidth: 64)
      .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .help(Text(title))
  }
}

#Preview {
  SnippetsEditorView()
    .environment(AppState.shared)
    .environment(\.locale, .init(identifier: "en"))
}
