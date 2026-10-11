import SwiftUI

/// Interactive map of books, authors, concepts, notes and mental models, built locally from the library.
struct KnowledgeMapView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @AppStorage("map.includeNotes") private var includeNotes = true
    @State private var graph = KnowledgeGraph()
    @State private var hidden = Set<GraphNode.Kind>()
    @State private var focus: String?
    @State private var selected: String?
    @State private var hovered: String?
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var building = true

    private var visibleNodes: [GraphNode] { graph.nodes.filter { !hidden.contains($0.kind) } }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 10) {
                controls
                ZStack {
                    canvas
                    if building {
                        ProgressView("Building your map…").controlSize(.small)
                    } else if graph.nodes.isEmpty {
                        EmptyStateView(icon: "point.3.connected.trianglepath.dotted", title: "Not enough connections yet",
                                       message: "Tag notes and books (e.g. #incentives), link related notes, or rate favourites. The map draws itself from those connections.")
                    }
                }
                .glass(.card, cornerRadius: DS.Radius.panel)
            }
            .padding(.leading, DS.Space.page)
            .padding(.trailing, 12)
            .padding(.bottom, 16)
            inspector
                .frame(width: 290)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
        }
        .task(id: "\(includeNotes)-\(focus ?? "")-\(library.books.count)-\(library.allNotes.count)") { rebuild() }
    }

    private func rebuild() {
        building = true
        var g = KnowledgeGraph.build(books: library.books, includeNotes: includeNotes, focus: focus)
        g.layout()
        graph = g
        if let s = selected, g.node(s) == nil { selected = nil }
        building = false
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 6) {
            ForEach(GraphNode.Kind.allCases) { kind in
                if kind != .note && kind != .mentalModel || includeNotes {
                    Button {
                        if hidden.contains(kind) { hidden.remove(kind) } else { hidden.insert(kind) }
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(Self.color(kind)).frame(width: 8, height: 8)
                            Text(kind.title)
                        }
                        .opacity(hidden.contains(kind) ? 0.4 : 1)
                    }
                    .buttonStyle(PillButtonStyle(selected: !hidden.contains(kind)))
                    .accessibilityLabel("\(hidden.contains(kind) ? "Show" : "Hide") \(kind.title)")
                }
            }
            Spacer()
            Toggle("Notes", isOn: $includeNotes).toggleStyle(.switch).controlSize(.mini)
            Menu {
                Button("Whole library") { focus = nil }
                Divider()
                let concepts = graph.nodes.filter { $0.kind == .concept }.sorted { (graph.degree[$0.id] ?? 0) > (graph.degree[$1.id] ?? 0) }
                ForEach(concepts.prefix(40)) { c in Button(c.label) { focus = c.id; selected = c.id } }
            } label: {
                Label(focus.flatMap { graph.node($0)?.label } ?? "Whole library", systemImage: "scope")
            }
            .menuStyle(.button).buttonStyle(GlassButtonStyle()).menuIndicator(.hidden).fixedSize()
            Button { Motion.perform { zoom = 1; baseZoom = 1; offset = .zero; baseOffset = .zero } } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .buttonStyle(IconButtonStyle()).help("Fit map").accessibilityLabel("Fit map")
        }
    }

    // MARK: Canvas

    static func color(_ kind: GraphNode.Kind) -> Color {
        switch kind {
        case .book: DS.chartSeries[0]
        case .author: DS.chartSeries[1]
        case .concept: DS.chartSeries[2]
        case .note: DS.chartSeries[3]
        case .mentalModel: DS.chartSeries[4]
        }
    }

    private func screen(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let scale = min(size.width, size.height) * 0.88 * zoom
        return CGPoint(x: size.width / 2 + p.x * scale + offset.width, y: size.height / 2 + p.y * scale + offset.height)
    }

    private func radius(_ n: GraphNode) -> CGFloat {
        let d = CGFloat(graph.degree[n.id] ?? 0)
        let base: CGFloat = n.kind == .note || n.kind == .mentalModel ? 3.5 : n.kind == .author ? 4 : 5
        return base + d.squareRoot() * 2
    }

    private func hit(_ location: CGPoint, in size: CGSize) -> String? {
        var best: (String, CGFloat)?
        for n in visibleNodes {
            guard let p = graph.positions[n.id] else { continue }
            let s = screen(p, in: size)
            let d = hypot(s.x - location.x, s.y - location.y)
            if d <= radius(n) + 6, d < (best?.1 ?? .infinity) { best = (n.id, d) }
        }
        return best?.0
    }

    private var canvas: some View {
        GeometryReader { geo in
            let size = geo.size
            let visible = Set(visibleNodes.map(\.id))
            let active = selected ?? hovered
            let neighborIDs = Set(active.map { graph.neighbors(of: $0).map(\.node.id) } ?? [])
            Canvas { ctx, _ in
                for e in graph.edges where visible.contains(e.a) && visible.contains(e.b) {
                    guard let pa = graph.positions[e.a], let pb = graph.positions[e.b] else { continue }
                    var path = Path()
                    path.move(to: screen(pa, in: size))
                    path.addLine(to: screen(pb, in: size))
                    let lit = active != nil && (e.a == active || e.b == active)
                    ctx.stroke(path, with: .color(lit ? DS.accent.opacity(0.75) : DS.textTertiary.opacity(active == nil ? 0.22 : 0.08)),
                               lineWidth: lit ? 1.6 : 0.8)
                }
                for n in visibleNodes {
                    guard let p = graph.positions[n.id] else { continue }
                    let s = screen(p, in: size)
                    let r = radius(n)
                    let dim = active != nil && n.id != active && !neighborIDs.contains(n.id)
                    let rect = CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)
                    let shape = n.kind == .concept ? Path(roundedRect: rect, cornerRadius: 2.5) : Path(ellipseIn: rect)
                    ctx.fill(shape, with: .color(Self.color(n.kind).opacity(dim ? 0.25 : 1)))
                    if n.id == selected {
                        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(DS.accent), lineWidth: 2)
                    }
                    let showLabel = n.id == active || neighborIDs.contains(n.id)
                        || (active == nil && (zoom > 1.4 || (graph.degree[n.id] ?? 0) >= 4) && n.kind != .note)
                    if showLabel {
                        let text = Text(n.label.count > 34 ? String(n.label.prefix(32)) + "…" : n.label)
                            .font(.system(size: n.kind == .concept ? 11 : 10, weight: n.kind == .concept || n.id == active ? .semibold : .regular))
                            .foregroundStyle(dim ? DS.textTertiary : DS.textPrimary)
                        ctx.draw(text, at: CGPoint(x: s.x, y: s.y + r + 8), anchor: .top)
                    }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let loc) = phase { hovered = hit(loc, in: size) } else { hovered = nil }
            }
            .onTapGesture(coordinateSpace: .local) { location in selected = hit(location, in: size) }
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { v in offset = CGSize(width: baseOffset.width + v.translation.width, height: baseOffset.height + v.translation.height) }
                    .onEnded { _ in baseOffset = offset }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { v in zoom = max(0.4, min(5, baseZoom * v.magnification)) }
                    .onEnded { _ in baseZoom = zoom }
            )
            .accessibilityElement()
            .accessibilityLabel("Knowledge map with \(visibleNodes.count) items and \(graph.edges.count) connections. Use the panel to explore connections.")
        }
    }

    // MARK: Inspector

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let id = selected, let node = graph.node(id) {
                Label(node.kind.title.dropLast(node.kind == .mentalModel ? 0 : 1).description, systemImage: icon(node.kind))
                    .font(DS.Text.eyebrow).textCase(.uppercase).foregroundStyle(Self.color(node.kind))
                Text(node.label).font(DS.serif(17, .semibold)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let n = node.noteID {
                        Button("Open Note") { app.openNote(n) }.buttonStyle(GlassButtonStyle())
                    } else if let b = node.bookID {
                        Button("Open Book") { app.openDetail(b) }.buttonStyle(GlassButtonStyle())
                    }
                    if node.kind == .concept || node.kind == .author {
                        Button(focus == id ? "Show All" : "Focus") { focus = focus == id ? nil : id }.buttonStyle(GlassButtonStyle())
                    }
                }
                let neighbors = graph.neighbors(of: id)
                Text("\(neighbors.count) CONNECTION\(neighbors.count == 1 ? "" : "S")").font(DS.Text.eyebrow).tracking(0.6).foregroundStyle(DS.textTertiary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(neighbors, id: \.node.id) { item in
                            Button { selected = item.node.id } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(Self.color(item.node.kind)).frame(width: 7, height: 7).padding(.top, 4)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.node.label).font(DS.Text.callout).lineLimit(2)
                                        Text(item.reason).font(DS.Text.micro).foregroundStyle(DS.textTertiary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Text("Your intellectual map").font(DS.serif(17, .semibold))
                Text("Books link to their authors and to concepts from your tags and genres. Notes link to their books, their tags and to each other. Click anything to see why it's connected.")
                    .font(DS.Text.callout).foregroundStyle(DS.textSecondary)
                Text("\(graph.nodes.count) items · \(graph.edges.count) connections").font(DS.Text.caption).foregroundStyle(DS.textTertiary)
                Text("Drag to pan, pinch to zoom.").font(DS.Text.caption).foregroundStyle(DS.textTertiary)
                Spacer()
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .glass(.card, cornerRadius: DS.Radius.panel)
    }

    private func icon(_ k: GraphNode.Kind) -> String {
        switch k {
        case .book: "book.closed"
        case .author: "person"
        case .concept: "tag"
        case .note: "note.text"
        case .mentalModel: "brain"
        }
    }
}
