import Defaults
import Foundation
import Testing
@testable import Maccy

extension SharedStateTests {
  @MainActor
  final class FooterSnippetsTests {
    let savedSnippetFolders = Defaults[.snippetFolders]
    let savedShowSnippets = Defaults[.showSnippets]

    init() {
      Defaults[.showSnippets] = true
      Defaults[.snippetFolders] = [
        SnippetFolder(title: "Shown", snippets: [Snippet(title: "Snippet", content: "content")]),
        SnippetFolder(title: "Empty")
      ]
    }

    deinit {
      Defaults[.snippetFolders] = savedSnippetFolders
      Defaults[.showSnippets] = savedShowSnippets
    }

    @Test("Footer lists folders with enabled snippets")
    func listsFolders() async {
      let footer = Footer()

      await waitUntil { footer.snippetItems.count == 1 }
      #expect(footer.snippetItems.map(\.title) == ["Shown"])
      #expect(footer.items.count == footer.actionItems.count + 1)
    }

    @Test("Turning off snippets removes folders from the footer")
    func hidesFolders() async {
      let footer = Footer()
      await waitUntil { footer.snippetItems.count == 1 }

      Defaults[.showSnippets] = false

      await waitUntil { footer.snippetItems.isEmpty }
      #expect(footer.snippetItems.isEmpty)
      #expect(editSnippetsItem(footer)?.isVisible == false)
    }

    @Test("Turning snippets back on lists folders again")
    func showsFoldersAgain() async {
      Defaults[.showSnippets] = false
      let footer = Footer()
      await waitUntil { footer.snippetItems.isEmpty }

      Defaults[.showSnippets] = true

      await waitUntil { footer.snippetItems.count == 1 }
      #expect(footer.snippetItems.map(\.title) == ["Shown"])
      #expect(editSnippetsItem(footer)?.isVisible == true)
    }

    private func editSnippetsItem(_ footer: Footer) -> FooterItem? {
      footer.actionItems.first { $0.title == "edit_snippets" }
    }

    // Footer picks up settings changes asynchronously.
    private func waitUntil(_ condition: () -> Bool) async {
      for _ in 0..<40 where !condition() {
        try? await Task.sleep(for: .milliseconds(50))
      }
    }
  }
}
