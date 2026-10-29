import Defaults
import SwiftUI

// Password with only the first and last characters visible.
struct MaskedPasswordView: View {
  var text: String

  @Default(.maskPasswordsShowLength) private var showLength

  var body: some View {
    let parts = PasswordDetector.maskedParts(text, showLength: showLength)
    HStack(spacing: 1) {
      Text(verbatim: parts.first)
      Text(verbatim: parts.hidden)
        .blur(radius: 2.5)
      Text(verbatim: parts.last)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("history_item_password_accessibility_label"))
  }
}

// Reveals the password while hovered and keeps it revealed when clicked.
struct PasswordRevealButton: View {
  @Binding var isRevealed: Bool

  @State private var appState = AppState.shared
  @State private var isHovered = false
  @State private var isPinnedOpen = false

  var body: some View {
    Button {
      isPinnedOpen.toggle()
      isRevealed = isPinnedOpen || isHovered
    } label: {
      Image(systemName: isRevealed || appState.isPasswordRevealKeyHeld ? "eye" : "eye.slash")
        .frame(width: 16, height: 16)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovered = hovering
      isRevealed = isPinnedOpen || hovering
    }
    .help(Text("password_reveal"))
    .accessibilityLabel(Text("password_reveal"))
  }
}
