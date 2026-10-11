import AppKit
import SwiftUI

/// Drives formatting commands on the editor's current selection.
@MainActor
final class MarkdownEditorController: ObservableObject {
    weak var textView: NSTextView?

    /// Wraps the selection in `marker` (e.g. ** for bold), or unwraps it if already wrapped.
    func toggleWrap(_ marker: String) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let r = tv.selectedRange()
        let selected = ns.substring(with: r)
        let m = marker.count
        if selected.hasPrefix(marker), selected.hasSuffix(marker), selected.count >= 2 * m {
            replace(tv, r, String(selected.dropFirst(m).dropLast(m)), select: NSRange(location: r.location, length: r.length - 2 * m))
        } else if r.location >= m, NSMaxRange(r) + m <= ns.length,
                  ns.substring(with: NSRange(location: r.location - m, length: m)) == marker,
                  ns.substring(with: NSRange(location: NSMaxRange(r), length: m)) == marker {
            let outer = NSRange(location: r.location - m, length: r.length + 2 * m)
            replace(tv, outer, selected, select: NSRange(location: r.location - m, length: r.length))
        } else {
            replace(tv, r, marker + selected + marker, select: NSRange(location: r.location + m, length: r.length))
        }
    }

    /// Toggles a line prefix (e.g. "- " or "> ") on every line in the selection.
    func toggleLinePrefix(_ prefix: String) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let lineRange = ns.lineRange(for: tv.selectedRange())
        let block = ns.substring(with: lineRange)
        var lines = block.components(separatedBy: "\n")
        let trailingNewline = block.hasSuffix("\n")
        if trailingNewline { lines.removeLast() }
        let allPrefixed = lines.allSatisfy { $0.hasPrefix(prefix) || $0.isEmpty }
        let updated = lines.map { line -> String in
            if line.isEmpty { return line }
            return allPrefixed ? String(line.dropFirst(prefix.count)) : prefix + line
        }.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        replace(tv, lineRange, updated, select: NSRange(location: lineRange.location, length: (updated as NSString).length - (trailingNewline ? 1 : 0)))
    }

    func insertLink() {
        guard let tv = textView else { return }
        let r = tv.selectedRange()
        let selected = (tv.string as NSString).substring(with: r)
        let text = selected.isEmpty ? "link" : selected
        let replacement = "[\(text)](https://)"
        replace(tv, r, replacement, select: NSRange(location: r.location + text.count + 3, length: 8))
    }

    func focus() {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
    }

    private func replace(_ tv: NSTextView, _ range: NSRange, _ string: String, select: NSRange) {
        guard tv.shouldChangeText(in: range, replacementString: string) else { return }
        tv.replaceCharacters(in: range, with: string)
        tv.didChangeText()
        tv.setSelectedRange(select)
        tv.window?.makeFirstResponder(tv)
    }
}

/// Plain-text Markdown editor backed by NSTextView (undo, spelling, selection-aware formatting).
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: MarkdownEditorController
    var fontSize: CGFloat = 13.5

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isContinuousSpellCheckingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.font = .systemFont(ofSize: fontSize)
        tv.textColor = .labelColor
        tv.textContainerInset = NSSize(width: 6, height: 10)
        tv.drawsBackground = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        tv.string = text
        controller.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        controller.textView = tv
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        init(_ parent: MarkdownEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

/// Formatting buttons for a MarkdownEditor. Shortcuts: ⌘B bold, ⌘I italic, ⌘K… is reserved for the palette.
struct MarkdownToolbar: View {
    let controller: MarkdownEditorController
    var body: some View {
        HStack(spacing: 2) {
            Button { controller.toggleWrap("**") } label: { Image(systemName: "bold") }
                .keyboardShortcut("b", modifiers: .command).help("Bold (⌘B)").accessibilityLabel("Bold")
            Button { controller.toggleWrap("_") } label: { Image(systemName: "italic") }
                .keyboardShortcut("i", modifiers: .command).help("Italic (⌘I)").accessibilityLabel("Italic")
            Button { controller.toggleWrap("`") } label: { Image(systemName: "chevron.left.forwardslash.chevron.right") }
                .help("Code").accessibilityLabel("Code")
            Divider().frame(height: 14)
            Button { controller.toggleLinePrefix("- ") } label: { Image(systemName: "list.bullet") }
                .help("Bulleted list").accessibilityLabel("Bulleted list")
            Button { controller.toggleLinePrefix("> ") } label: { Image(systemName: "text.quote") }
                .help("Block quote").accessibilityLabel("Block quote")
            Button { controller.insertLink() } label: { Image(systemName: "link") }
                .help("Link").accessibilityLabel("Insert link")
        }
        .buttonStyle(IconButtonStyle(size: 26))
    }
}
