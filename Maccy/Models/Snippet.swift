import Defaults
import Foundation

// Snippets are reusable pieces of text organized in folders.
// Based on snippets in https://github.com/Clipy/Clipy.
nonisolated struct Snippet: Codable, Equatable, Identifiable, Defaults.Serializable {
  var id = UUID()
  var title: String
  var content: String
  var isEnabled = true
}

nonisolated struct SnippetFolder: Codable, Equatable, Identifiable, Defaults.Serializable {
  var id = UUID()
  var title: String
  var isEnabled = true
  var snippets: [Snippet] = []

  // Folder is shown in the popup only when it has snippets to paste.
  var isVisibleInPopup: Bool {
    isEnabled && snippets.contains(where: \.isEnabled)
  }
}

nonisolated extension Array where Element == SnippetFolder {
  // Folders and snippets matching the query by title or content.
  // Matching folder keeps all its snippets.
  func filtered(by query: String) -> [SnippetFolder] {
    let query = query.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return self }

    return compactMap { folder in
      if folder.title.localizedCaseInsensitiveContains(query) {
        return folder
      }

      var matchingFolder = folder
      matchingFolder.snippets = folder.snippets.filter {
        $0.title.localizedCaseInsensitiveContains(query) || $0.content.localizedCaseInsensitiveContains(query)
      }
      return matchingFolder.snippets.isEmpty ? nil : matchingFolder
    }
  }

  // Puts the dragged folder or snippet in place of the target.
  // Dropping a snippet onto a folder moves it to the end of the folder.
  @discardableResult
  mutating func move(_ draggedID: UUID, onto targetID: UUID) -> Bool {
    guard draggedID != targetID,
          let source = location(of: draggedID),
          let target = location(of: targetID) else { return false }

    if let sourceSnippet = source.snippet {
      let snippet = self[source.folder].snippets.remove(at: sourceSnippet)
      if let targetSnippet = target.snippet {
        self[target.folder].snippets.insert(snippet, at: targetSnippet)
      } else {
        self[target.folder].snippets.append(snippet)
      }
    } else {
      guard source.folder != target.folder else { return false }
      let folder = remove(at: source.folder)
      insert(folder, at: target.folder)
    }

    return true
  }

  // Inserts a copy of the snippet after the target snippet, or at the end of the target folder,
  // and returns the identifier of the copy.
  @discardableResult
  mutating func paste(_ snippet: Snippet, at targetID: UUID) -> UUID? {
    guard let target = location(of: targetID) else { return nil }

    var copy = snippet
    copy.id = UUID()
    if self[target.folder].snippets.contains(where: { $0.title == snippet.title }) {
      copy.title = String(format: NSLocalizedString("snippets_editor_copy_title", comment: ""), snippet.title)
    }

    let index = target.snippet.map { $0 + 1 } ?? self[target.folder].snippets.count
    self[target.folder].snippets.insert(copy, at: index)
    return copy.id
  }

  // Index of the folder and, for snippets, index of the snippet in it.
  func location(of id: UUID) -> (folder: Int, snippet: Int?)? {
    for (folderIndex, folder) in enumerated() {
      if folder.id == id {
        return (folderIndex, nil)
      }
      if let snippetIndex = folder.snippets.firstIndex(where: { $0.id == id }) {
        return (folderIndex, snippetIndex)
      }
    }

    return nil
  }
}

// Reads and writes snippets in the XML format used by Clipy,
// so that snippets can be moved between the applications:
//
// <folders>
//   <folder>
//     <title>Folder</title>
//     <snippets>
//       <snippet>
//         <title>Snippet</title>
//         <content>Content</content>
//       </snippet>
//     </snippets>
//   </folder>
// </folders>
nonisolated enum SnippetsXML {
  enum ImportError: Error {
    case invalidFormat
  }

  private static let rootElement = "folders"
  private static let folderElement = "folder"
  private static let snippetsElement = "snippets"
  private static let snippetElement = "snippet"
  private static let titleElement = "title"
  private static let contentElement = "content"

  static func decode(_ data: Data) throws -> [SnippetFolder] {
    let document = try XMLDocument(data: data, options: [.nodePreserveWhitespace])
    guard let root = document.rootElement(), root.name == rootElement else {
      throw ImportError.invalidFormat
    }

    return root.elements(forName: folderElement).map { folderNode in
      let snippets = folderNode.elements(forName: snippetsElement).first?
        .elements(forName: snippetElement)
        .map { snippetNode in
          Snippet(
            title: value(of: titleElement, in: snippetNode) ?? "untitled snippet",
            content: value(of: contentElement, in: snippetNode) ?? ""
          )
        } ?? []

      return SnippetFolder(
        title: value(of: titleElement, in: folderNode) ?? "untitled folder",
        snippets: snippets
      )
    }
  }

  static func encode(_ folders: [SnippetFolder]) -> Data {
    let root = XMLElement(name: rootElement)
    for folder in folders {
      let folderNode = XMLElement(name: folderElement)
      folderNode.addChild(XMLElement(name: titleElement, stringValue: folder.title))
      let snippetsNode = XMLElement(name: snippetsElement)
      for snippet in folder.snippets {
        let snippetNode = XMLElement(name: snippetElement)
        snippetNode.addChild(XMLElement(name: titleElement, stringValue: snippet.title))
        snippetNode.addChild(XMLElement(name: contentElement, stringValue: snippet.content))
        snippetsNode.addChild(snippetNode)
      }
      folderNode.addChild(snippetsNode)
      root.addChild(folderNode)
    }

    let document = XMLDocument(rootElement: root)
    document.version = "1.0"
    document.characterEncoding = "UTF-8"
    return document.xmlData(options: [.nodePrettyPrint])
  }

  private static func value(of name: String, in element: XMLElement) -> String? {
    return element.elements(forName: name).first?.stringValue
  }
}
