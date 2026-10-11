import Foundation

/// Reading progress observed in another app (currently Apple Books). Values are copied exactly as
/// reported; Folio never infers dates or sessions from them.
struct ExternalProgress: Codable, Hashable {
    enum Source: String, Codable { case appleBooks }
    var source: Source = .appleBooks
    /// 0…1 position in the book as reported by the source.
    var fraction: Double
    /// Furthest position ever reached, when reported.
    var highWatermark: Double?
    var finished: Bool
    /// Completion date, only when the source records one.
    var finishedDate: Date?
    /// When Folio last read this value from the source.
    var observedAt: Date

    init(source: Source = .appleBooks, fraction: Double, highWatermark: Double? = nil, finished: Bool,
         finishedDate: Date? = nil, observedAt: Date) {
        self.source = source; self.fraction = fraction; self.highWatermark = highWatermark
        self.finished = finished; self.finishedDate = finishedDate; self.observedAt = observedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = c.value(.source, .appleBooks)
        fraction = c.value(.fraction, 0)
        highWatermark = c.value(.highWatermark, nil)
        finished = c.value(.finished, false)
        finishedDate = c.value(.finishedDate, nil)
        observedAt = c.value(.observedAt, Date.distantPast)
    }
}

/// Where an imported note came from.
struct NoteSource: Codable, Hashable {
    enum Kind: String, Codable { case appleBooks }
    var kind: Kind = .appleBooks
    /// The source's stable identifier (Apple Books annotation UUID).
    var externalID: String
    /// Source location, e.g. an EPUB CFI.
    var location: String?
    /// Highlight colour/style code as stored by the source.
    var style: Int?
    /// Text as last imported; if the note's text differs, the user edited it in Folio and it is left alone.
    var importedText: String
    var importedAt: Date

    init(kind: Kind = .appleBooks, externalID: String, location: String?, style: Int?, importedText: String, importedAt: Date) {
        self.kind = kind; self.externalID = externalID; self.location = location; self.style = style
        self.importedText = importedText; self.importedAt = importedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.value(.kind, .appleBooks)
        externalID = try c.decode(String.self, forKey: .externalID)
        location = c.value(.location, nil)
        style = c.value(.style, nil)
        importedText = c.value(.importedText, "")
        importedAt = c.value(.importedAt, Date.distantPast)
    }
}
