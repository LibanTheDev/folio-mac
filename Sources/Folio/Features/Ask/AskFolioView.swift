import SwiftUI

struct AskFolioView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @StateObject private var ai = AISettings.shared
    @StateObject private var index = EmbeddingIndex.shared
    @State private var mode = AskFolio.Mode.ask
    @State private var question = ""
    @State private var answers: [AskFolio.Answer] = []
    @State private var evidence: (question: String, sources: [AskFolio.Source])?
    @State private var running = false
    @State private var error: String?

    private var canUseAI: Bool { ai.enabled && ai.shareNotes }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Ask Folio", caption: "Grounded in your own notes",
                           subtitle: "Ask about what you've learned. Every claim about your reading links back to a note you saved.")
                if library.allNotes.isEmpty {
                    EmptyStateView(icon: "text.bubble", title: "Save some notes first",
                                   message: "Ask Folio answers from your highlights, quotes and reflections. Add a few on any book and come back.") {
                        Button("Open Knowledge") { app.go(.knowledge) }.buttonStyle(GlassButtonStyle())
                    }
                    .frame(height: 320)
                } else {
                    modes
                    composer
                    if !canUseAI { consentCard }
                    if running {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Finding relevant notes on this Mac, then asking \(ai.provider == .anthropic ? "Claude" : "your model") to synthesize…")
                                .font(DS.Text.callout).foregroundStyle(DS.textSecondary)
                        }
                    }
                    if let error {
                        GlassCard {
                            Label(error, systemImage: "exclamationmark.triangle").font(DS.Text.callout)
                        }
                    }
                    if let evidence { EvidenceView(question: evidence.question, sources: evidence.sources) }
                    ForEach(Array(answers.enumerated()), id: \.offset) { _, a in AnswerView(answer: a) }
                }
            }
            .padding(.horizontal, DS.Space.page)
            .padding(.top, 10)
            .padding(.bottom, 30)
        }
    }

    private var modes: some View {
        FlowLayout(spacing: 6) {
            ForEach(AskFolio.Mode.allCases) { m in
                Button { mode = m } label: { Label(m.rawValue, systemImage: m.symbol) }
                    .buttonStyle(PillButtonStyle(selected: mode == m))
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "text.bubble").font(.system(size: 15)).foregroundStyle(DS.accent).padding(.top, 2)
                TextField(mode.placeholder, text: $question, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(1...5)
                    .onSubmit(ask)
                Button(action: ask) {
                    Label(canUseAI ? "Ask" : "Find Notes", systemImage: canUseAI ? "arrow.up" : "magnifyingglass")
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || running)
            }
            .padding(14)
            .glass(.card, cornerRadius: DS.Radius.panel)
            if canUseAI {
                Text("Sends your question and only the most relevant notes (found on this Mac) to \(ai.provider == .anthropic ? "Anthropic" : "your server"). Quotes and citations are checked against your notes before display.")
                    .font(DS.Text.caption).foregroundStyle(DS.textTertiary)
            }
        }
    }

    private var consentCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Synthesized answers need AI access to relevant notes", systemImage: "lock.shield").font(DS.Text.headline)
                Text(ai.enabled
                     ? "AI is on, but sharing notes is off. Ask Folio sends only the passages relevant to each question, never your whole vault. Until you allow it, Folio shows you the relevant passages it finds locally."
                     : "AI features are off. Until you turn them on, Folio finds and shows the relevant passages from your notes, entirely on this Mac.")
                    .font(DS.Text.callout).foregroundStyle(DS.textSecondary)
                HStack {
                    if ai.enabled {
                        Button("Allow Relevant Notes") { ai.shareNotes = true }.buttonStyle(PrimaryButtonStyle(fullWidth: false))
                    }
                    SettingsLink { Text("Open AI Settings") }.buttonStyle(GlassButtonStyle())
                }
            }
        }
    }

    private func ask() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !running else { return }
        error = nil
        evidence = nil
        guard canUseAI else {
            let sources = AskFolio.retrieve(q, books: library.books, index: index)
            evidence = (q, sources)
            return
        }
        running = true
        let m = mode
        Task {
            defer { running = false }
            do {
                let provider = try ai.makeProvider()
                let answer = try await AskFolio.run(question: q, mode: m, provider: provider, books: library.books, index: index)
                answers.insert(answer, at: 0)
                question = ""
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Answer rendering

private struct AnswerView: View {
    let answer: AskFolio.Answer
    @State private var showSources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label(answer.mode.rawValue, systemImage: answer.mode.symbol)
                    .font(DS.Text.eyebrow).textCase(.uppercase).foregroundStyle(DS.accent)
                Spacer()
                Text(answer.provider).font(DS.Text.micro).foregroundStyle(DS.textTertiary)
            }
            Text(answer.question).font(DS.serif(19, .semibold))
            if answer.insufficientEvidence {
                Label("Your notes don't contain enough to fully answer this. What's below is limited to what they do support.",
                      systemImage: "exclamationmark.circle")
                    .font(DS.Text.callout)
                    .foregroundStyle(DS.statusReading)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.statusReading.opacity(0.1)))
            }
            ForEach(answer.sections, id: \.kind) { section in
                VStack(alignment: .leading, spacing: 8) {
                    SourceBadge(kind: section.kind)
                    ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, p in
                        ParagraphView(paragraph: p, sources: answer.sources, kind: section.kind)
                    }
                }
            }
            Button(showSources ? "Hide sources" : "Show all \(answer.sources.count) sources sent") { Motion.perform { showSources.toggle() } }
                .buttonStyle(GhostButtonStyle())
                .padding(.leading, -8)
            if showSources {
                VStack(alignment: .leading, spacing: 6) { ForEach(answer.sources) { SourceRow(source: $0) } }
            }
        }
        .padding(18)
        .glass(.card, cornerRadius: DS.Radius.panel)
    }
}

private struct SourceBadge: View {
    let kind: AskFolio.SectionKind
    var body: some View {
        let color: Color = kind == .from_your_notes ? DS.accent : kind == .from_book_metadata ? DS.textSecondary : DS.statusReading
        Label(kind.title, systemImage: kind == .from_your_notes ? "note.text" : kind == .from_book_metadata ? "book.closed" : "globe")
            .font(DS.Text.eyebrow)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

private struct ParagraphView: View {
    let paragraph: AskFolio.Paragraph
    let sources: [AskFolio.Source]
    let kind: AskFolio.SectionKind

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(paragraph.text)
                .font(.system(size: 13))
                .lineSpacing(3)
                .textSelection(.enabled)
                .foregroundStyle(paragraph.unsupported ? DS.textTertiary : DS.textPrimary)
            FlowLayout(spacing: 4) {
                ForEach(paragraph.citations, id: \.self) { id in
                    if let s = sources.first(where: { $0.id == id }) { CitationChip(source: s) }
                }
            }
            if paragraph.unsupported {
                warning(kind == .from_your_notes ? "No supporting note was cited, so treat this as unverified." : "No supporting source was cited.")
            }
            if !paragraph.unverifiedQuotes.isEmpty {
                warning("Quoted text not found in your notes: \(paragraph.unverifiedQuotes.map { "“\($0)”" }.joined(separator: ", "))")
            }
            if !paragraph.invalidCitations.isEmpty {
                warning("Ignored citations that don't match any source: \(paragraph.invalidCitations.joined(separator: ", "))")
            }
        }
    }

    private func warning(_ s: String) -> some View {
        Label(s, systemImage: "exclamationmark.triangle").font(DS.Text.caption).foregroundStyle(DS.statusDNF)
    }
}

/// Clickable [S1] chip that previews its source and links to it.
private struct CitationChip: View {
    @EnvironmentObject var app: AppState
    let source: AskFolio.Source
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Text(source.id)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(source.id.hasPrefix("S") ? DS.accent : DS.textSecondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(source.id.hasPrefix("S") ? DS.selection : DS.fill))
        }
        .buttonStyle(.plain)
        .help("\(source.title) · \(source.label)")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(source.id) · \(source.title)").font(DS.Text.headline)
                Text(source.label).font(DS.Text.caption).foregroundStyle(DS.textSecondary)
                ScrollView { Text(source.text).font(.system(size: 12.5)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 180)
                Button(source.id.hasPrefix("S") ? "Open Note" : "Open Book") {
                    showing = false
                    switch source.kind {
                    case .note(let n, _): app.openNote(n)
                    case .metadata(let b): app.openDetail(b)
                    }
                }
                .buttonStyle(GlassButtonStyle())
            }
            .padding(14)
            .frame(width: 340)
        }
    }
}

private struct SourceRow: View {
    @EnvironmentObject var app: AppState
    let source: AskFolio.Source
    var body: some View {
        Button {
            switch source.kind {
            case .note(let n, _): app.openNote(n)
            case .metadata(let b): app.openDetail(b)
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(source.id).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(DS.textTertiary).frame(width: 26, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(source.title) · \(source.label)").font(DS.Text.caption.weight(.medium))
                    Text(source.text).font(DS.Text.caption).foregroundStyle(DS.textSecondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Local, AI-free view: the passages from the reader's notes that bear on the question.
private struct EvidenceView: View {
    let question: String
    let sources: [AskFolio.Source]

    var body: some View {
        let notes = sources.filter { $0.id.hasPrefix("S") }
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT YOUR NOTES SAY").font(DS.Text.eyebrow).tracking(0.8).foregroundStyle(DS.textTertiary)
            Text(question).font(DS.serif(19, .semibold))
            if notes.isEmpty {
                Text("None of your notes seem related to this question.").font(DS.Text.callout).foregroundStyle(DS.textSecondary)
            } else {
                Text("\(notes.count) relevant passage\(notes.count == 1 ? "" : "s") from \(Set(notes.map(\.title)).count) book\(Set(notes.map(\.title)).count == 1 ? "" : "s"), found on this Mac:")
                    .font(DS.Text.callout).foregroundStyle(DS.textSecondary)
                let grouped = Dictionary(grouping: notes, by: \.title)
                ForEach(grouped.keys.sorted(), id: \.self) { title in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(DS.Text.headline)
                        ForEach(grouped[title]!) { SourceRow(source: $0) }
                    }
                }
            }
        }
        .padding(18)
        .glass(.card, cornerRadius: DS.Radius.panel)
    }
}
