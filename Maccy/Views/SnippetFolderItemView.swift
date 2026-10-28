import SwiftUI

struct SnippetFolderItemView: View {
  @Bindable var item: FooterItem
  @Environment(AppState.self) private var appState

  var body: some View {
    ListItemView(
      id: item.id,
      selectionId: item.id,
      // Numbers open folders only when the popup shows just snippets.
      shortcuts: appState.popup.mode == .snippets ? item.shortcuts : [],
      isSelected: item.isSelected,
      accessibilityLabel: item.title
    ) {
      HStack(spacing: 6) {
        Image(systemName: "folder")
        Text(verbatim: item.title)
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
      }
    }
    .buttonAction {
      item.action()
    }
    .background {
      GeometryReader { proxy in
        Color.clear
          .onAppear { item.windowFrame = proxy.frame(in: .global) }
          .onChange(of: proxy.frame(in: .global)) { _, frame in item.windowFrame = frame }
      }
    }
    .onHover { hovering in
      if hovering && appState.preview.state.isOpen {
        appState.preview.togglePreview()
      }
    }
  }
}
