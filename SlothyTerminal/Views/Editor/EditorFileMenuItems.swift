import SwiftUI

/// File-menu entries that target the currently focused editor tab through
/// `FocusedValues`. Items render unconditionally so Cmd+S / Cmd+Shift+S
/// stay claimed app-wide even when no editor is focused — otherwise the
/// chords fall through to the focused terminal, where Cmd+S sends ^S
/// (XOFF / stop output) and freezes the foreground process.
struct EditorFileMenuItems: View {
  @FocusedValue(\.editorSave) private var editorSave
  @FocusedValue(\.editorSaveAs) private var editorSaveAs
  @FocusedValue(\.editorRevert) private var editorRevert

  var body: some View {
    Button("Save") {
      editorSave?()
    }
    .keyboardShortcut("s", modifiers: .command)
    .disabled(!(editorSave?.isEnabled ?? false))

    Button("Save As…") {
      editorSaveAs?()
    }
    .keyboardShortcut("s", modifiers: [.command, .shift])
    .disabled(!(editorSaveAs?.isEnabled ?? false))

    Button("Revert to Saved") {
      editorRevert?()
    }
    .disabled(!(editorRevert?.isEnabled ?? false))
  }
}
