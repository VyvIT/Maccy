import Foundation
import Testing
@testable import Maccy

struct SnippetsXMLTests {
  @Test("Decodes Clipy snippets")
  func decodesClipySnippets() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <folders>
      <folder>
        <title>Greetings</title>
        <snippets>
          <snippet>
            <title>Hello</title>
            <content>Hello,
      world &amp; friends!</content>
          </snippet>
          <snippet>
            <title>Bye</title>
            <content></content>
          </snippet>
        </snippets>
      </folder>
      <folder>
        <title>Empty</title>
        <snippets/>
      </folder>
    </folders>
    """

    let folders = try SnippetsXML.decode(Data(xml.utf8))

    #expect(folders.map(\.title) == ["Greetings", "Empty"])
    #expect(folders[0].snippets.map(\.title) == ["Hello", "Bye"])
    #expect(folders[0].snippets[0].content == "Hello,\n  world & friends!")
    #expect(folders[0].snippets[1].content == "")
    #expect(folders[1].snippets.isEmpty)
  }

  @Test("Encoded snippets decode to the same folders")
  func roundTrip() throws {
    let folders = [
      SnippetFolder(title: "Code", snippets: [
        Snippet(title: "Function", content: "func foo() {\n  <bar/>\n}\n"),
        Snippet(title: "Spaces", content: "  leading and trailing  ")
      ]),
      SnippetFolder(title: "Empty")
    ]

    let decoded = try SnippetsXML.decode(SnippetsXML.encode(folders))

    #expect(decoded.map(\.title) == folders.map(\.title))
    #expect(decoded.map { $0.snippets.map(\.title) } == folders.map { $0.snippets.map(\.title) })
    #expect(decoded.map { $0.snippets.map(\.content) } == folders.map { $0.snippets.map(\.content) })
  }

  @Test("Folder is shown in popup only with enabled snippets")
  func folderVisibilityInPopup() {
    let enabled = Snippet(title: "Enabled", content: "")
    let disabled = Snippet(title: "Disabled", content: "", isEnabled: false)

    #expect(SnippetFolder(title: "Mixed", snippets: [disabled, enabled]).isVisibleInPopup)
    #expect(!SnippetFolder(title: "Empty").isVisibleInPopup)
    #expect(!SnippetFolder(title: "All disabled", snippets: [disabled]).isVisibleInPopup)
    #expect(!SnippetFolder(title: "Disabled", isEnabled: false, snippets: [enabled]).isVisibleInPopup)
  }

  @Test("Rejects documents that are not Clipy snippets")
  func rejectsUnknownDocuments() {
    #expect(throws: (any Error).self) {
      try SnippetsXML.decode(Data("<plist></plist>".utf8))
    }
    #expect(throws: (any Error).self) {
      try SnippetsXML.decode(Data("not xml".utf8))
    }
  }
}

struct SnippetFoldersTests {
  private let first = Snippet(title: "First", content: "alpha")
  private let second = Snippet(title: "Second", content: "beta")
  private let third = Snippet(title: "Third", content: "gamma")
  private let other = Snippet(title: "Other", content: "delta")

  private let folders: [SnippetFolder]

  init() {
    folders = [
      SnippetFolder(title: "Greek", snippets: [first, second, third]),
      SnippetFolder(title: "More", snippets: [other]),
      SnippetFolder(title: "Empty")
    ]
  }

  @Test("Filter matches folder titles, snippet titles and contents")
  func filter() {
    #expect(folders.filtered(by: " ") == folders)
    #expect(folders.filtered(by: "more").map(\.title) == ["More"])
    #expect(folders.filtered(by: "more")[0].snippets == [other])
    #expect(folders.filtered(by: "GAMMA").map(\.title) == ["Greek"])
    #expect(folders.filtered(by: "GAMMA")[0].snippets == [third])
    #expect(folders.filtered(by: "sec")[0].snippets == [second])
    #expect(folders.filtered(by: "nothing").isEmpty)
  }

  @Test("Moving a snippet down or up takes the target's place")
  func moveSnippetWithinFolder() {
    var down = folders
    let moved1 = down.move(first.id, onto: third.id)
    #expect(moved1)
    #expect(down[0].snippets == [second, third, first])

    var up = folders
    let moved2 = up.move(third.id, onto: first.id)
    #expect(moved2)
    #expect(up[0].snippets == [third, first, second])
  }

  @Test("Moving a snippet to another folder")
  func moveSnippetBetweenFolders() {
    var ontoSnippet = folders
    let moved3 = ontoSnippet.move(second.id, onto: other.id)
    #expect(moved3)
    #expect(ontoSnippet[0].snippets == [first, third])
    #expect(ontoSnippet[1].snippets == [second, other])

    var ontoFolder = folders
    let moved4 = ontoFolder.move(first.id, onto: ontoFolder[2].id)
    #expect(moved4)
    #expect(ontoFolder[2].snippets == [first])
  }

  @Test("Moving folders")
  func moveFolders() {
    var down = folders
    let moved5 = down.move(down[0].id, onto: down[2].id)
    #expect(moved5)
    #expect(down.map(\.title) == ["More", "Empty", "Greek"])

    var up = folders
    let moved6 = up.move(up[2].id, onto: up[0].id)
    #expect(moved6)
    #expect(up.map(\.title) == ["Empty", "Greek", "More"])

    var ontoOwnSnippet = folders
    let moved7 = ontoOwnSnippet.move(ontoOwnSnippet[0].id, onto: first.id)
    #expect(!moved7)
    let moved8 = ontoOwnSnippet.move(first.id, onto: first.id)
    #expect(!moved8)
    #expect(ontoOwnSnippet == folders)
  }
}

struct SnippetPasteTests {
  private let first = Snippet(title: "First", content: "alpha")
  private let second = Snippet(title: "Second", content: "beta", isEnabled: false)
  private let folders: [SnippetFolder]

  init() {
    folders = [
      SnippetFolder(title: "Greek", snippets: [first, second]),
      SnippetFolder(title: "Empty")
    ]
  }

  @Test("Pasting onto a snippet inserts a copy after it")
  func pasteAfterSnippet() throws {
    var pasted = folders
    let pastedID = pasted.paste(second, at: first.id)
    let id = try #require(pastedID)

    #expect(pasted[0].snippets.map(\.title) == ["First", "Second copy", "Second"])
    #expect(pasted[0].snippets[1].id == id)
    #expect(id != second.id)
    #expect(pasted[0].snippets[1].content == "beta")
    #expect(!pasted[0].snippets[1].isEnabled)
  }

  @Test("Pasting onto a folder appends a copy keeping its title")
  func pasteIntoFolder() throws {
    var pasted = folders
    let emptyFolderID = pasted[1].id
    let pastedID = pasted.paste(first, at: emptyFolderID)
    let id = try #require(pastedID)

    #expect(pasted[1].snippets.map(\.title) == ["First"])
    #expect(pasted[1].snippets[0].id == id)
    #expect(pasted[0].snippets == [first, second])
  }

  @Test("Pasting onto an unknown item does nothing")
  func pasteUnknownTarget() {
    var pasted = folders
    let id = pasted.paste(first, at: UUID())

    #expect(id == nil)
    #expect(pasted == folders)
  }
}
