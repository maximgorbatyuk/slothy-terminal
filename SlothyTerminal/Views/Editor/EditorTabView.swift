import AppKit
import SwiftUI
import STTextView
import STTextViewSwiftUI

/// Editor tab content for `.editor` mode tabs. Loads the file via
/// `FileEditorService`, drives an `STTextViewSwiftUI.TextView` bound to an
/// `AttributedString`, tracks dirty state on `Tab.isDirty`, and exposes
/// save / save-as / revert closures through `FocusedValues` so the global
/// File menu can target the focused editor.
///
/// The syntax-highlighting plugin is created ONCE (lazily, when the tab
/// first transitions to `.ready`) and never replaced — STTextView's plugin
/// API is add-only and the SwiftUI wrapper only consumes the `plugins`
/// array in `makeNSView`. Save As / Revert mutate the live coordinator
/// via `updateLanguage(_:)` / `updateTheme(_:)` instead of allocating a
/// new plugin instance.
struct EditorTabView: View {
  @Bindable var tab: Tab
  @Environment(AppState.self) private var appState
  /// Non-private so the synthesized memberwise init stays internal — the
  /// `private` access level on a stored property downgrades the whole
  /// init's accessibility, breaking `EditorTabView(tab:)` callers.
  var configManager = ConfigManager.shared

  @State private var loadState: LoadState = .loading
  @State private var attributedText: AttributedString = AttributedString()
  @State private var encoding: String.Encoding = .utf8
  @State private var lastSavedText: String = ""
  @State private var lastSavedTextCount: Int = 0
  @State private var loadedFileURL: URL?
  @State private var isSaving: Bool = false
  @State private var skipNextDirtyCheck: Bool = false
  @State private var highlightingPlugin: SyntaxHighlightingPlugin?
  @State private var saveErrorMessage: String?
  @State private var showSavedToast: Bool = false
  @State private var savedToastTask: Task<Void, Never>?

  enum LoadState: Equatable {
    case loading
    case ready
    case error(String)
    case tooLarge(UInt64)
    case missing
  }

  var body: some View {
    Group {
      switch loadState {
      case .loading:
        ProgressView("Loading…")
          .progressViewStyle(.circular)
          .frame(maxWidth: .infinity, maxHeight: .infinity)

      case .ready:
        readyTextView

      case .error(let message):
        editorMessageView(
          systemImage: "exclamationmark.triangle",
          title: "Couldn't open file",
          detail: message
        )

      case .tooLarge(let byteCount):
        editorMessageView(
          systemImage: "doc.badge.ellipsis",
          title: "File is too large",
          detail: "\(formatByteCount(byteCount)) exceeds the editor limit of \(formatByteCount(UInt64(FileEditorService.maxInlineSize)))."
        )

      case .missing:
        editorMessageView(
          systemImage: "questionmark.folder",
          title: "File no longer exists",
          detail: tab.fileURL?.path ?? ""
        )
      }
    }
    .overlay(alignment: .bottom) {
      if showSavedToast {
        savedToastView
          .padding(.bottom, 16)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.easeInOut(duration: 0.18), value: showSavedToast)
    .task(id: tab.fileURL) {
      guard tab.fileURL != loadedFileURL else {
        return
      }

      await loadFile()
    }
    .onChange(of: attributedText) { _, newValue in
      /// `AttributedString(stringValue).characters.count` is not always
      /// equal to `stringValue.count` (Unicode normalization for decomposed
      /// scalars, ZWJ sequences, etc.). The first onChange after loadFile
      /// would otherwise mark a freshly-loaded file as dirty.
      if skipNextDirtyCheck {
        skipNextDirtyCheck = false
        return
      }

      let newCount = newValue.characters.count
      if newCount != lastSavedTextCount {
        tab.isDirty = true
        return
      }

      let plain = String(newValue.characters)
      tab.isDirty = (plain != lastSavedText)
    }
    /// Re-bake the editor font into the `AttributedString` binding whenever
    /// the user changes the Settings → Editor Font controls. STTextView's
    /// SwiftUI wrapper re-assigns `attributedText` from this binding on
    /// every `updateNSView`, which wipes any `.font` attribute the live
    /// `textView.font` setter wrote to text storage; baking the font into
    /// the binding makes the wipe a no-op.
    .onChange(of: editorFontSettingsKey) { _, _ in
      rebakeEditorFont()
    }
    .focusedValue(\.editorSave, loadState == .ready ? EditorSaveAction(isEnabled: canSave, action: save) : nil)
    .focusedValue(\.editorSaveAs, loadState == .ready ? EditorSaveAsAction(isEnabled: canSaveAs, action: saveAs) : nil)
    .focusedValue(\.editorRevert, loadState == .ready ? EditorRevertAction(isEnabled: canRevert, action: revert) : nil)
    .alert("Save failed", isPresented: Binding(
      get: { saveErrorMessage != nil },
      set: { if !$0 { saveErrorMessage = nil } }
    )) {
      Button("OK") { saveErrorMessage = nil }
    } message: {
      Text(saveErrorMessage ?? "")
    }
    .alert(
      "Save changes to \(tab.title)?",
      isPresented: Binding(
        get: { appState.tabPendingDirtyEditorClose == tab.id },
        set: { isPresented in
          if !isPresented && appState.tabPendingDirtyEditorClose == tab.id {
            appState.cancelDirtyEditorClose()
          }
        }
      )
    ) {
      Button("Save") {
        saveAndCloseAfterDirtyPrompt()
      }
      Button("Don't Save", role: .destructive) {
        appState.discardAndCloseDirtyEditor()
      }
      Button("Cancel", role: .cancel) {
        appState.cancelDirtyEditorClose()
      }
    } message: {
      Text("If you don't save, your changes will be lost.")
    }
  }

  private var canSave: Bool {
    if case .ready = loadState {
      return tab.isDirty && !isSaving
    }

    return false
  }

  private var canSaveAs: Bool {
    if case .ready = loadState {
      return !isSaving
    }

    return false
  }

  private var canRevert: Bool {
    if case .ready = loadState {
      return tab.isDirty && !isSaving
    }

    return false
  }

  private func loadFile() async {
    guard let fileURL = tab.fileURL else {
      loadState = .missing
      return
    }

    loadState = .loading

    do {
      let result = try await FileEditorService.load(fileURL)
      encoding = result.encoding
      lastSavedText = result.text
      lastSavedTextCount = AttributedString(result.text).characters.count
      skipNextDirtyCheck = true
      attributedText = makeAttributedString(text: result.text, font: editorNSFont)
      loadedFileURL = fileURL
      installOrUpdateHighlightingPlugin(for: fileURL)
      tab.isDirty = false
      loadState = .ready
    } catch EditorError.missing {
      loadState = .missing
    } catch let EditorError.tooLarge(byteCount) {
      loadState = .tooLarge(byteCount)
    } catch EditorError.binaryFile {
      loadState = .error("This file appears to be binary and cannot be opened as text.")
    } catch EditorError.permissionDenied {
      loadState = .error("You don't have permission to read this file.")
    } catch EditorError.undecodableOnLoad {
      loadState = .error("Couldn't decode this file under any supported text encoding.")
    } catch {
      loadState = .error(error.localizedDescription)
    }
  }

  private func save() {
    guard canSave,
          !isSaving,
          let fileURL = tab.fileURL
    else {
      return
    }

    isSaving = true
    let plain = String(attributedText.characters)
    let writeEncoding = encoding

    Task { @MainActor in
      defer { isSaving = false }

      do {
        try await FileEditorService.save(plain, to: fileURL, encoding: writeEncoding)
        commitSavedSnapshot(plain)
        triggerSavedToast()
      } catch let EditorError.unrepresentableOnSave(enc) {
        saveErrorMessage = unrepresentableSaveMessage(for: enc, text: plain, saveAsContext: false)
      } catch EditorError.permissionDenied {
        saveErrorMessage = "You don't have permission to write to this file."
      } catch let EditorError.tooLarge(byteCount) {
        saveErrorMessage = "The current buffer (\(formatByteCount(byteCount))) exceeds the editor's save limit."
      } catch {
        saveErrorMessage = error.localizedDescription
      }
    }
  }

  /// Save initiated from the dirty-close prompt. On success closes the tab
  /// when the buffer matches what was written; if the user kept typing
  /// during the save, the post-save state is still dirty — we cancel the
  /// close instead of looping the alert.
  private func saveAndCloseAfterDirtyPrompt() {
    guard !isSaving else {
      return
    }

    guard let fileURL = tab.fileURL else {
      appState.discardAndCloseDirtyEditor()
      return
    }

    isSaving = true
    let plain = String(attributedText.characters)
    let writeEncoding = encoding
    let tabID = tab.id

    Task { @MainActor in
      defer { isSaving = false }

      do {
        try await FileEditorService.save(plain, to: fileURL, encoding: writeEncoding)
        let stillDirty = commitSavedSnapshot(plain)
        if stillDirty {
          /// User typed during the save. Drop the close request and let
          /// them save again; the dirty marker on the tab shows the state.
          appState.cancelDirtyEditorClose()
        } else {
          /// After clearing isDirty the dirty-editor branch in closeTab is
          /// skipped and the immediate-close path runs; performCloseTab
          /// clears `tabPendingDirtyEditorClose` if it matched this tab.
          appState.closeTab(id: tabID)
        }
      } catch let EditorError.unrepresentableOnSave(enc) {
        appState.cancelDirtyEditorClose()
        saveErrorMessage = unrepresentableSaveMessage(for: enc, text: plain, saveAsContext: true)
      } catch EditorError.permissionDenied {
        appState.cancelDirtyEditorClose()
        saveErrorMessage = "You don't have permission to write to this file."
      } catch let EditorError.tooLarge(byteCount) {
        appState.cancelDirtyEditorClose()
        saveErrorMessage = "The current buffer (\(formatByteCount(byteCount))) exceeds the editor's save limit."
      } catch {
        appState.cancelDirtyEditorClose()
        saveErrorMessage = error.localizedDescription
      }
    }
  }

  private func saveAs() {
    guard canSaveAs, !isSaving else {
      return
    }

    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = tab.fileURL?.lastPathComponent ?? "Untitled.txt"
    if let directory = tab.fileURL?.deletingLastPathComponent() {
      panel.directoryURL = directory
    }

    /// Claim `isSaving` for the entire panel-open → write lifecycle so a
    /// stray Cmd+S during the panel can't queue a concurrent writer.
    isSaving = true

    panel.begin { @MainActor [tab, encoding, attributedText, appState] response in
      guard response == .OK,
            let newURL = panel.url
      else {
        isSaving = false
        return
      }

      let canonical = AppState.canonicalFileURL(newURL)

      if appState.hasOpenEditorTab(for: canonical, excludingTabID: tab.id) {
        isSaving = false
        saveErrorMessage = "Another editor tab is already editing \(canonical.lastPathComponent)."
        return
      }

      let plain = String(attributedText.characters)
      let writeEncoding = encoding
      let previousFileURL = tab.fileURL

      /// Claim the URL synchronously BEFORE the async save so any
      /// concurrent `openFileInEditor(canonical)` dedupes to this tab
      /// instead of creating a duplicate.
      loadedFileURL = canonical
      tab.fileURL = canonical

      Task { @MainActor in
        defer { isSaving = false }

        do {
          try await FileEditorService.save(plain, to: canonical, encoding: writeEncoding)
          _ = commitSavedSnapshot(plain)
          /// Update the live highlighter's language to match the new
          /// extension. Installing a fresh plugin won't take effect —
          /// STTextView only consumes plugins at makeNSView time.
          installOrUpdateHighlightingPlugin(for: canonical)
          triggerSavedToast()
        } catch let EditorError.unrepresentableOnSave(enc) {
          tab.fileURL = previousFileURL
          loadedFileURL = previousFileURL
          saveErrorMessage = unrepresentableSaveMessage(for: enc, text: plain, saveAsContext: false)
        } catch EditorError.permissionDenied {
          tab.fileURL = previousFileURL
          loadedFileURL = previousFileURL
          saveErrorMessage = "You don't have permission to write to that location."
        } catch let EditorError.tooLarge(byteCount) {
          tab.fileURL = previousFileURL
          loadedFileURL = previousFileURL
          saveErrorMessage = "The current buffer (\(formatByteCount(byteCount))) exceeds the editor's save limit."
        } catch {
          tab.fileURL = previousFileURL
          loadedFileURL = previousFileURL
          saveErrorMessage = error.localizedDescription
        }
      }
    }
  }

  private func revert() {
    guard canRevert else {
      return
    }

    let alert = NSAlert()
    alert.messageText = "Revert to saved version?"
    alert.informativeText = "All unsaved changes will be discarded."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Revert")
    alert.addButton(withTitle: "Cancel")

    guard alert.runModal() == .alertFirstButtonReturn else {
      return
    }

    /// Reset loadedFileURL so loadFile actually runs (the `.task(id:)`
    /// guard alone would short-circuit because tab.fileURL didn't change).
    loadedFileURL = nil

    Task {
      await loadFile()
    }
  }

  private var savedToastView: some View {
    HStack(spacing: 6) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .appFont(size: 12)

      Text("File was saved")
        .appFont(size: 12, weight: .medium)
        .foregroundStyle(.primary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(.regularMaterial)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.15), radius: 6, y: 2)
  }

  /// Shows the save-confirmation toast for ~1.6s. Rapid repeated saves
  /// cancel the previous dismiss timer so the toast doesn't flicker.
  private func triggerSavedToast() {
    savedToastTask?.cancel()
    showSavedToast = true
    savedToastTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_600_000_000)
      guard !Task.isCancelled else {
        return
      }
      showSavedToast = false
    }
  }

  private func editorMessageView(systemImage: String, title: String, detail: String) -> some View {
    VStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(size: 28))
        .foregroundStyle(.secondary)

      Text(title)
        .appFont(size: 13, weight: .semibold)

      if !detail.isEmpty {
        Text(detail)
          .appFont(size: 11)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .textSelection(.enabled)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(24)
  }

  private func formatByteCount(_ byteCount: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(min(byteCount, UInt64(Int64.max))), countStyle: .file)
  }

  /// Either creates the syntax-highlighting plugin for the first time (so
  /// STTextView's `makeNSView` will install it on first render), or
  /// updates the language of the already-installed plugin in place.
  /// Never replaces the plugin instance — STTextView has no `removePlugin`
  /// API and the SwiftUI wrapper only adds plugins in `makeNSView`.
  private func installOrUpdateHighlightingPlugin(for fileURL: URL) {
    let language = EditorLanguage.resolve(for: fileURL)
    let theme = EditorTheme.resolve(for: fileURL)

    if let plugin = highlightingPlugin {
      if let coordinator = plugin.coordinator {
        coordinator.updateLanguage(language)
        coordinator.updateTheme(theme)
      }
      /// If the coordinator hasn't been made yet (rare — happens only
      /// before the NSView is in a window), the plugin's `initialLanguage`
      /// captured at construction time still applies; we can't update it
      /// retroactively because makeCoordinator hasn't run yet. The next
      /// load / Save As will route through here again.
    } else {
      highlightingPlugin = SyntaxHighlightingPlugin(language: language, theme: theme)
    }
  }

  /// The theme for the file currently being edited. Falls back to the
  /// dark theme while the tab is still resolving its `fileURL` (which
  /// in practice never renders because the `.loading` / `.missing`
  /// branches of `body` don't show the TextView).
  private var currentTheme: EditorTheme {
    if let fileURL = tab.fileURL {
      return EditorTheme.resolve(for: fileURL)
    }

    return .dark
  }

  /// The TextView pipeline once the file has finished loading. Pulled
  /// out of `body` because the inline modifier chain (TextView + font +
  /// theme background + colorScheme override) was tripping SwiftUI's
  /// expression-complexity limit alongside the surrounding switch and
  /// `.onChange` modifiers.
  @ViewBuilder
  private var readyTextView: some View {
    /// `selection: .constant(nil)` is deliberate. STTextViewSwiftUI
    /// publishes selection changes through the binding on every click
    /// / drag, which forces SwiftUI to call `updateNSView`, which
    /// re-assigns `attributedText`, which calls `setString` on
    /// STTextView, which wipes the layout manager's rendering
    /// attributes — making syntax colors flash off and back on. We
    /// don't read selection anywhere; passing `.constant(nil)` short-
    /// circuits the wipe-on-click loop. If a future feature needs
    /// the caret position, observe it through STTextView's delegate
    /// rather than re-introducing this binding.
    TextView(
      text: $attributedText,
      selection: .constant(nil),
      options: [.showLineNumbers, .highlightSelectedLine, .wrapLines],
      plugins: [highlightingPlugin].compactMap { $0 }
    )
    /// STTextView's SwiftUI wrapper shadows SwiftUI's `\.font`
    /// environment key with its own NSFont-typed one, so a plain
    /// `.font(.custom(...))` modifier here has no effect. Use the
    /// wrapper's `textViewFont(_:)` to push the NSFont into the
    /// right env slot. The wrapper detects font changes in
    /// `updateNSView` and re-applies them to the text view + gutter.
    .textViewFont(editorNSFont)
    .background(Color(currentTheme.background))
    .environment(\.colorScheme, currentTheme.colorScheme)
    /// SwiftUI doesn't clip `NSViewRepresentable` contents to their
    /// layout frame, so STTextView's gutter / document view can paint
    /// over neighbouring SwiftUI siblings (e.g. the tab bar above)
    /// once the scroll view's gutter view extends past the editor's
    /// reported bounds. Clipping here keeps the editor's pixels
    /// inside its own rect.
    .clipped()
  }

  /// Resolves the user-configured editor font to an `NSFont`, falling
  /// back to the platform monospaced system font when the named family
  /// is not installed.
  private var editorNSFont: NSFont {
    let size = configManager.config.editorFontSize
    return NSFont(name: configManager.config.editorFontName, size: size)
      ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
  }

  /// Stable `Hashable` key combining the font family and size so a
  /// single `.onChange` modifier can watch both inputs — keeps the
  /// `body`'s top-level modifier chain short enough for SwiftUI's
  /// expression-complexity checker.
  private var editorFontSettingsKey: String {
    "\(configManager.config.editorFontName)#\(configManager.config.editorFontSize)"
  }

  /// Constructs an `AttributedString` whose entire range carries the
  /// given NSFont as a text-storage attribute. STTextView's SwiftUI
  /// wrapper round-trips the binding through `attributedText =` on
  /// every `updateNSView` — embedding the font here ensures that
  /// round-trip preserves it instead of falling back to the layout
  /// manager's default body font.
  private func makeAttributedString(text: String, font: NSFont) -> AttributedString {
    let mutable = NSMutableAttributedString(
      string: text,
      attributes: [.font: font]
    )
    return AttributedString(mutable)
  }

  /// Re-bakes the current editor font into the existing buffer. Called
  /// when the user changes the family or size in Settings; preserves
  /// the in-memory characters and only swaps the `.font` attribute.
  /// Sets `skipNextDirtyCheck` so the attribute-only mutation doesn't
  /// false-trip the dirty detector.
  private func rebakeEditorFont() {
    guard case .ready = loadState else {
      return
    }

    let plain = String(attributedText.characters)
    skipNextDirtyCheck = true
    attributedText = makeAttributedString(text: plain, font: editorNSFont)
  }

  /// Records that `plain` was successfully written and updates the dirty
  /// flag against the LIVE buffer (which may have changed during the save
  /// await). Returns `true` if the tab is still dirty after the commit.
  @discardableResult
  private func commitSavedSnapshot(_ plain: String) -> Bool {
    lastSavedText = plain
    lastSavedTextCount = AttributedString(plain).characters.count
    let currentPlain = String(attributedText.characters)
    let stillDirty = currentPlain != plain
    tab.isDirty = stillDirty
    return stillDirty
  }

  private func unrepresentableSaveMessage(for encoding: String.Encoding, text: String, saveAsContext: Bool) -> String {
    if text.contains("\u{0000}") {
      return "Buffer contains characters that can't be saved as text."
    }

    if saveAsContext {
      return "Some characters can't be saved with \(encoding.displayName). Try Save As to a UTF-8 file."
    }

    return "Some characters can't be saved with \(encoding.displayName). Try saving as UTF-8."
  }
}

// MARK: - FocusedValue plumbing

/// Save action surfaced to the global File menu through `FocusedValues`.
struct EditorSaveAction {
  let isEnabled: Bool
  let action: () -> Void

  func callAsFunction() {
    action()
  }
}

/// Save-As action surfaced to the File menu.
struct EditorSaveAsAction {
  let isEnabled: Bool
  let action: () -> Void

  func callAsFunction() {
    action()
  }
}

/// Revert action surfaced to the File menu.
struct EditorRevertAction {
  let isEnabled: Bool
  let action: () -> Void

  func callAsFunction() {
    action()
  }
}

private struct EditorSaveActionKey: FocusedValueKey {
  typealias Value = EditorSaveAction
}

private struct EditorSaveAsActionKey: FocusedValueKey {
  typealias Value = EditorSaveAsAction
}

private struct EditorRevertActionKey: FocusedValueKey {
  typealias Value = EditorRevertAction
}

extension FocusedValues {
  var editorSave: EditorSaveAction? {
    get { self[EditorSaveActionKey.self] }
    set { self[EditorSaveActionKey.self] = newValue }
  }

  var editorSaveAs: EditorSaveAsAction? {
    get { self[EditorSaveAsActionKey.self] }
    set { self[EditorSaveAsActionKey.self] = newValue }
  }

  var editorRevert: EditorRevertAction? {
    get { self[EditorRevertActionKey.self] }
    set { self[EditorRevertActionKey.self] = newValue }
  }
}

// MARK: - Encoding helpers

private extension String.Encoding {
  var displayName: String {
    switch self {
    case .utf8: return "UTF-8"
    case .windowsCP1252: return "Windows-1252"
    case .macOSRoman: return "Mac OS Roman"
    case .isoLatin1: return "ISO Latin-1"
    case .utf16: return "UTF-16"
    case .utf16BigEndian: return "UTF-16 BE"
    case .utf16LittleEndian: return "UTF-16 LE"
    default: return "this encoding"
    }
  }
}
