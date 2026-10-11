import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Lets the binary run as a regular app even when launched outside a bundle (e.g. `swift run`).
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct FolioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var library = Library()
    @StateObject private var app = AppState()
    @AppStorage("appearance") private var appearance = Appearance.system

    var body: some Scene {
        WindowGroup("Folio") {
            ContentView()
                .environmentObject(library)
                .environmentObject(app)
                .frame(minWidth: 1080, minHeight: 680)
                .preferredColorScheme(appearance.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add a Book…") { library.presentAddBook() }
                    .keyboardShortcut("n")
                Button("New Collection…") { app.editingShelf = Shelf(name: "", kind: .manual) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Smart Shelf…") {
                    app.editingShelf = Shelf(name: "", icon: "sparkles", kind: .smart, rules: [ShelfRule(.rating, .atLeast, "4")])
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                Menu("New Shelf from Template") {
                    ForEach(Shelf.templates(year: library.currentYear), id: \.name) { t in
                        Button(t.name) {
                            var s = t
                            s.id = UUID()
                            library.addShelf(s)
                            app.show(.shelf(s.id))
                        }
                    }
                }
            }
            CommandGroup(after: .importExport) {
                Button("Import Goodreads Library…") { library.importGoodreads() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Restore from Folio Backup…") { library.restoreFromBackup() }
                Divider()
                Menu("Export") {
                    Button("Complete Folio Backup (JSON)…") { library.exportFolioBackup() }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                    Button("Notes & Highlights as Markdown…") { library.exportMarkdownNotes() }
                    Button("Library as Goodreads CSV…") { library.exportCSV() }
                    Button("Reading Sessions as CSV…") { library.exportSessionsCSV() }
                }
            }
            CommandGroup(after: .toolbar) {
                ForEach(Array(Page.allCases.enumerated()), id: \.element) { i, page in
                    Button(page.rawValue) { app.go(page) }
                        .keyboardShortcut(KeyEquivalent(Character(String(i + 1))))
                }
                Divider()
                Button("Command Palette…") { app.paletteShown.toggle() }
                    .keyboardShortcut("k")
                Button("Find") { app.searchFocusRequests += 1 }
                    .keyboardShortcut("f")
                Button(app.inspectorShown ? "Hide Inspector" : "Show Inspector") { app.toggleInspector() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                Divider()
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(library)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "Match System"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}
