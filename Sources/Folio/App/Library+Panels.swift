import AppKit
import UniformTypeIdentifiers

/// File panels for import and export. Kept out of the model layer.
extension Library {
    func importGoodreads() {
        let panel = NSOpenPanel()
        panel.title = "Import Goodreads Library"
        panel.message = "Choose the CSV from Goodreads → My Books → Import and export → Export Library."
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let summary = merge(imported: try GoodreadsCSV.parse(text))
            alertMessage = "Imported \(summary.added) new book\(summary.added == 1 ? "" : "s")"
                + (summary.updated > 0 ? " and updated \(summary.updated)." : ".")
            Task { await enrichAll() }
        } catch {
            alertMessage = "Couldn't import that file: \(error.localizedDescription)"
        }
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.title = "Export Library"
        panel.nameFieldStringValue = "Folio Library.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try GoodreadsCSV.export(books).write(to: url, atomically: true, encoding: .utf8)
            alertMessage = "Exported \(books.count) books in Goodreads-compatible CSV format."
        } catch {
            alertMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}
