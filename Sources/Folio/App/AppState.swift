import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case home = "Home", books = "My Books", discover = "Discover", stats = "Stats"
    var id: String { rawValue }
}

/// What "My Books" is showing.
enum Scope: Hashable {
    case all, favorites
    case status(ReadingStatus)
    case tag(String)
    case shelf(UUID)
}

@MainActor
final class AppState: ObservableObject {
    @Published var page: Page = .home { didSet { if oldValue != page { detailBook = nil } } }
    @Published var scope: Scope = .all
    @Published var selectedBook: UUID?
    @Published var inspectorShown = true
    /// Book shown as a full page in the main area.
    @Published var detailBook: UUID?
    @Published var search = ""
    @Published var searchFocusRequests = 0
    /// Shelf editor presentation: a shelf to edit, or a new draft.
    @Published var editingShelf: Shelf?

    func go(_ page: Page) {
        self.page = page
        detailBook = nil
    }

    func show(_ scope: Scope) {
        self.scope = scope
        page = .books
        detailBook = nil
    }

    /// Selects a book and shows it in the inspector.
    func open(_ id: UUID) {
        Motion.perform {
            selectedBook = id
            inspectorShown = true
        }
    }

    /// Opens the full book page.
    func openDetail(_ id: UUID) {
        Motion.perform {
            selectedBook = id
            detailBook = id
            inspectorShown = false
        }
    }

    func closeDetail() {
        Motion.perform { detailBook = nil }
    }

    func toggleInspector() {
        Motion.perform { inspectorShown.toggle() }
    }
}

// Opening a book from anywhere.
private struct OpenBookKey: EnvironmentKey {
    static let defaultValue: (UUID) -> Void = { _ in }
}

private struct OpenDetailKey: EnvironmentKey {
    static let defaultValue: (UUID) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Select a book into the inspector.
    var openBook: (UUID) -> Void {
        get { self[OpenBookKey.self] }
        set { self[OpenBookKey.self] = newValue }
    }

    /// Open a book's full detail page.
    var openDetail: (UUID) -> Void {
        get { self[OpenDetailKey.self] }
        set { self[OpenDetailKey.self] = newValue }
    }
}
