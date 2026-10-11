import Foundation

extension Library {
    func updateNote(_ noteID: UUID, _ change: (inout BookNote) -> Void) {
        for i in books.indices {
            if let j = books[i].notes.firstIndex(where: { $0.id == noteID }) {
                var n = books[i].notes[j]
                change(&n)
                guard n != books[i].notes[j] else { return }
                n.updated = Date()
                books[i].notes[j] = n
                books[i].updatedAt = Date()
                return
            }
        }
    }

    @discardableResult
    func addNote(to bookID: UUID, kind: BookNote.Kind, text: String = "") -> UUID? {
        guard let i = books.firstIndex(where: { $0.id == bookID }) else { return nil }
        let note = BookNote(kind: kind, text: text)
        books[i].notes.append(note)
        books[i].updatedAt = Date()
        return note.id
    }

    func deleteNote(_ noteID: UUID) {
        for i in books.indices {
            books[i].notes.removeAll { $0.id == noteID }
            for j in books[i].notes.indices where books[i].notes[j].links.contains(noteID) {
                books[i].notes[j].links.removeAll { $0 == noteID }
            }
        }
    }

    /// Connects two notes. The link is stored on `from`; the other side sees it as a backlink.
    func link(_ from: UUID, to: UUID) {
        guard from != to, note(to) != nil else { return }
        updateNote(from) { if !$0.links.contains(to) { $0.links.append(to) } }
    }

    func unlink(_ a: UUID, _ b: UUID) {
        updateNote(a) { $0.links.removeAll { $0 == b } }
        updateNote(b) { $0.links.removeAll { $0 == a } }
    }

    /// Outgoing links plus backlinks, without duplicates.
    func connections(of noteID: UUID) -> [NoteRef] {
        guard let me = note(noteID) else { return [] }
        var ids = me.note.links
        for b in books {
            for n in b.notes where n.links.contains(noteID) && !ids.contains(n.id) { ids.append(n.id) }
        }
        return ids.compactMap(note)
    }

    var allNoteTags: [String] {
        Array(Set(books.flatMap { $0.notes.flatMap(\.tags) })).sorted()
    }
}
