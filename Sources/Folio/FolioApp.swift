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
    @AppStorage("appearance") private var appearance = Appearance.light

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
            }
            CommandGroup(after: .importExport) {
                Button("Import Goodreads Library…") { library.importGoodreads() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Export Library as CSV…") { library.exportCSV() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                ForEach(Array(Page.allCases.enumerated()), id: \.element) { i, page in
                    Button(page.rawValue) { app.go(page) }
                        .keyboardShortcut(KeyEquivalent(Character(String(i + 1))))
                }
                Divider()
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
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .light: "Paper (Light)"
        case .dark: "Night (Dark)"
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
