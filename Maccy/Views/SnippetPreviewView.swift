import SwiftUI

// Preview of a snippet next to the folder submenu,
// styled like the history item preview.
struct SnippetPreviewView: View {
  private static let largeTextThreshold = 1_000
  private static let minimumVisibleLines: CGFloat = 5

  // Tall enough for the title, five lines of content and the details below.
  static var minimumHeight: CGFloat {
    let lineHeight = NSLayoutManager().defaultLineHeight(for: .preferredFont(forTextStyle: .body))
    let titleHeight = NSLayoutManager().defaultLineHeight(for: .preferredFont(forTextStyle: .headline))
    let padding: CGFloat = 16
    let details = 3 * lineHeight + 2 * padding + 1
    return (2 * padding + titleHeight + 6 + minimumVisibleLines * lineHeight + details).rounded(.up)
  }

  var snippet: Snippet
  var folderTitle: String

  private var lineCount: Int {
    snippet.content.isEmpty ? 0 : snippet.content.components(separatedBy: .newlines).count
  }

  var body: some View {
    ZStack {
      if #available(macOS 26.0, *) {
        GlassEffectView()
      } else {
        VisualEffectView()
      }

      VStack(alignment: .leading, spacing: 0) {
        Text(verbatim: snippet.title)
          .font(.headline)
          .lineLimit(1)
          .padding(.bottom, 6)

        if snippet.content.utf8.count >= Self.largeTextThreshold {
          LargeTextView(text: snippet.content)
            .id("snippetpreview-\(snippet.id)")
        } else {
          ScrollView {
            Text(snippet.content)
              .font(.body)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxWidth: .infinity)
        }

        Spacer(minLength: 0)

        Divider()
          .padding(.vertical)

        HStack(spacing: 3) {
          Text("snippet_preview_folder")
          Text(verbatim: folderTitle)
        }
        HStack(spacing: 3) {
          Text("snippet_preview_characters")
          Text(String(snippet.content.count))
        }
        HStack(spacing: 3) {
          Text("snippet_preview_lines")
          Text(String(lineCount))
        }
      }
      .controlSize(.small)
      .padding()
    }
    .clipShape(.rect(cornerRadius: Popup.cornerRadius + Popup.horizontalPadding))
  }
}
