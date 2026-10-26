import SwiftUI

struct SnippetsSubmenuView: View {
  var submenu: SnippetsSubmenu

  var body: some View {
    ZStack {
      if #available(macOS 26.0, *) {
        GlassEffectView()
      } else {
        VisualEffectView()
      }

      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 0) {
            ForEach(Array(submenu.snippets.enumerated()), id: \.element.id) { index, snippet in
              row(index: index, snippet: snippet)
            }
          }
          .padding(.vertical, Popup.verticalPadding)
          .padding(.horizontal, Popup.horizontalPadding)
        }
        .scrollIndicators(.never)
        .onChange(of: submenu.highlightedIndex) { _, index in
          if let index, submenu.snippets.indices.contains(index) {
            proxy.scrollTo(submenu.snippets[index].id)
          }
        }
      }
    }
    .clipShape(.rect(cornerRadius: Popup.cornerRadius + Popup.horizontalPadding))
  }

  private func row(index: Int, snippet: Snippet) -> some View {
    let isHighlighted = submenu.highlightedIndex == index

    return HStack(spacing: 6) {
      Text(verbatim: snippet.title)
        .lineLimit(1)
        .truncationMode(.middle)

      Spacer(minLength: 0)

      if index < SnippetsSubmenu.numberKeys.count {
        Text(verbatim: SnippetsSubmenu.numberKeys[index])
          .foregroundStyle(isHighlighted ? Color.white.opacity(0.8) : .secondary)
          .monospacedDigit()
      }
    }
    .padding(.horizontal, 10)
    .frame(height: Popup.itemHeight)
    .foregroundStyle(isHighlighted ? Color.white : .primary)
    .background(
      isHighlighted ? Color.accentColor.opacity(0.8) : .white.opacity(0.001),
      in: .rect(cornerRadius: Popup.cornerRadius)
    )
    .id(snippet.id)
    .onHover { hovering in
      if hovering {
        submenu.hover(index)
      }
    }
    .onTapGesture {
      let modifierFlags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
      submenu.choose(index, modifierFlags: modifierFlags)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: snippet.title))
    .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
  }
}
