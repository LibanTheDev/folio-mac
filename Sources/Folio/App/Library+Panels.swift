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
        importGoodreads(from: url)
    }

    func importGoodreads(from url: URL) {
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

// MARK: - Data ownership

extension Library {
    /// Full-fidelity backup in Folio's own format (everything: books, notes, sessions, shelves, goals).
    func exportFolioBackup() {
        let panel = NSSavePanel()
        panel.title = "Export Folio Backup"
        panel.nameFieldStringValue = "Folio Backup \(LibraryStore.dayStamp()).folio.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try LibraryStore.encoder().encode(snapshot).write(to: url, options: .atomic)
            alertMessage = "Saved a complete backup of \(books.count) books, \(allNotes.count) notes and \(sessions.count) sessions."
        } catch {
            alertMessage = "Backup failed: \(error.localizedDescription)"
        }
    }

    /// One Markdown file per book that has notes or a review, plus an index.
    func exportMarkdownNotes() {
        let panel = NSOpenPanel()
        panel.title = "Export Notes as Markdown"
        panel.message = "Choose a folder. Folio will create a “Folio Notes” folder inside it."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let base = panel.url else { return }
        let folder = base.appendingPathComponent("Folio Notes", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let withContent = books.filter { !$0.notes.isEmpty || !$0.review.isEmpty }
            var noteBook: [UUID: String] = [:]
            for b in books { for n in b.notes { noteBook[n.id] = MarkdownExporter.filename(for: b).replacingOccurrences(of: ".md", with: "") } }
            var index = "# Folio Notes\n\n"
            for b in withContent.sorted(by: { $0.sortTitle < $1.sortTitle }) {
                let name = MarkdownExporter.filename(for: b)
                try MarkdownExporter.markdown(for: b, linkTitle: { noteBook[$0] })
                    .write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
                index += "- [[\(name.replacingOccurrences(of: ".md", with: ""))]] (\(b.notes.count) notes)\n"
            }
            try index.write(to: folder.appendingPathComponent("Index.md"), atomically: true, encoding: .utf8)
            alertMessage = "Exported \(withContent.count) books with notes to “\(folder.lastPathComponent)”."
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch {
            alertMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func exportSessionsCSV() {
        let panel = NSSavePanel()
        panel.title = "Export Reading Sessions"
        panel.nameFieldStringValue = "Folio Reading Sessions.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SessionsCSV.export(sessions, books: books).write(to: url, atomically: true, encoding: .utf8)
            alertMessage = "Exported \(sessions.count) reading sessions."
        } catch {
            alertMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Replaces the library with a Folio backup after showing what's in it. The current library is
    /// saved to Backups first, so a restore can itself be undone.
    func restoreFromBackup() {
        let panel = NSOpenPanel()
        panel.title = "Restore Folio Backup"
        panel.allowedContentTypes = [.json]
        if let dir = try? FileManager.default.contentsOfDirectory(at: store.backupsURL, includingPropertiesForKeys: nil), !dir.isEmpty {
            panel.directoryURL = store.backupsURL
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = try LibraryStore.decode(Data(contentsOf: url))
            let alert = NSAlert()
            alert.messageText = "Replace your library with this backup?"
            alert.informativeText = "The backup contains \(file.books.count) books, \(file.books.reduce(0) { $0 + $1.notes.count }) notes and \(file.sessions.count) sessions. Your current library (\(books.count) books) will be saved to the Backups folder first."
            alert.addButton(withTitle: "Restore")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            restore(from: file)
            alertMessage = "Restored \(file.books.count) books from the backup."
        } catch {
            alertMessage = "That file isn't a readable Folio backup: \(error.localizedDescription)"
        }
    }
}
