import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// Folio's private drag type (declared in Info.plist by build_app.sh).
    static let folioItem = UTType(exportedAs: "app.folio.reader.item")
}

/// What's carried when dragging books or shelves. Other apps receive readable text instead of IDs.
struct FolioDrag: Codable, Transferable, Hashable {
    enum Kind: String, Codable { case book, shelf }
    let kind: Kind
    let id: UUID
    var title: String = ""
    var author: String = ""

    static func book(_ b: Book) -> FolioDrag { FolioDrag(kind: .book, id: b.id, title: b.title, author: b.authorLine) }
    static func shelf(_ s: Shelf) -> FolioDrag { FolioDrag(kind: .shelf, id: s.id, title: s.name) }

    var plainText: String { kind == .book ? "\(title) by \(author)" : title }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .folioItem)
        ProxyRepresentation(exporting: \.plainText)
    }
}
