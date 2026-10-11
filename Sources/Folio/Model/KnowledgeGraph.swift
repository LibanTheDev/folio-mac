import CoreGraphics
import Foundation

struct GraphNode: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Identifiable {
        case book, author, concept, note, mentalModel
        var id: String { rawValue }
        var title: String {
            switch self {
            case .book: "Books"
            case .author: "Authors"
            case .concept: "Concepts"
            case .note: "Notes"
            case .mentalModel: "Mental models"
            }
        }
    }

    let id: String
    let kind: Kind
    let label: String
    var bookID: UUID?
    var noteID: UUID?
}

/// A connection with the reason it exists, so every link is traceable.
struct GraphEdge: Hashable {
    let a: String
    let b: String
    let reason: String
}

struct KnowledgeGraph {
    var nodes: [GraphNode] = []
    var edges: [GraphEdge] = []
    var positions: [String: CGPoint] = [:]

    var degree: [String: Int] {
        var d: [String: Int] = [:]
        for e in edges { d[e.a, default: 0] += 1; d[e.b, default: 0] += 1 }
        return d
    }

    func node(_ id: String) -> GraphNode? { nodes.first { $0.id == id } }

    func neighbors(of id: String) -> [(node: GraphNode, reason: String)] {
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        return edges.compactMap { e in
            if e.a == id, let n = byID[e.b] { return (n, e.reason) }
            if e.b == id, let n = byID[e.a] { return (n, e.reason) }
            return nil
        }
    }

    static func conceptID(_ name: String) -> String { "c:" + name.lowercased().replacingOccurrences(of: "-", with: " ") }

    /// Builds the graph from the library. Concepts come from book tags, note tags and genres; only concepts
    /// that connect at least two things are kept, so the map shows relationships rather than noise.
    static func build(books: [Book], includeNotes: Bool, focus: String? = nil, maxBooks: Int = 80) -> KnowledgeGraph {
        let chosen = books
            .filter { !$0.notes.isEmpty || $0.favorite || ($0.rating ?? 0) >= 4 || !$0.tags.isEmpty }
            .sorted { ($0.notes.count, $0.ratingValue) > ($1.notes.count, $1.ratingValue) }
            .prefix(maxBooks)

        var g = KnowledgeGraph()
        var nodeIDs = Set<String>()
        func addNode(_ n: GraphNode) { if nodeIDs.insert(n.id).inserted { g.nodes.append(n) } }
        var conceptLinks: [String: [(String, String)]] = [:]   // concept id -> [(node id, reason)]
        var conceptNames: [String: String] = [:]

        func concept(_ raw: String, from nodeID: String, reason: String) {
            let name = raw.replacingOccurrences(of: "-", with: " ").capitalized
            let id = conceptID(raw)
            conceptNames[id] = conceptNames[id] ?? name
            conceptLinks[id, default: []].append((nodeID, reason))
        }

        for b in chosen {
            let bid = "b:\(b.id.uuidString)"
            addNode(GraphNode(id: bid, kind: .book, label: b.title, bookID: b.id))
            for a in b.authors.prefix(2) {
                let aid = "a:\(a.lowercased())"
                addNode(GraphNode(id: aid, kind: .author, label: a))
                g.edges.append(GraphEdge(a: bid, b: aid, reason: "written by \(a)"))
            }
            for t in b.tags { concept(t, from: bid, reason: "book tagged #\(t)") }
            for genre in b.genres.prefix(3) { concept(genre, from: bid, reason: "genre: \(genre)") }
            guard includeNotes else { continue }
            for n in b.notes where n.kind == .mentalModel || !n.tags.isEmpty || !n.links.isEmpty {
                let nid = "n:\(n.id.uuidString)"
                let label = String(n.plainText.prefix(60)) + (n.plainText.count > 60 ? "…" : "")
                addNode(GraphNode(id: nid, kind: n.kind == .mentalModel ? .mentalModel : .note, label: label, bookID: b.id, noteID: n.id))
                g.edges.append(GraphEdge(a: nid, b: bid, reason: "\(n.kind.title.lowercased()) from \(b.title)"))
                for t in n.tags { concept(t, from: nid, reason: "note tagged #\(t)") }
            }
        }
        if includeNotes {
            for b in chosen {
                for n in b.notes {
                    for target in n.links where nodeIDs.contains("n:\(target.uuidString)") && nodeIDs.contains("n:\(n.id.uuidString)") {
                        g.edges.append(GraphEdge(a: "n:\(n.id.uuidString)", b: "n:\(target.uuidString)", reason: "connected notes"))
                    }
                }
            }
        }
        for (cid, links) in conceptLinks {
            let distinct = Set(links.map(\.0))
            guard distinct.count >= 2 || cid == focus else { continue }
            addNode(GraphNode(id: cid, kind: .concept, label: conceptNames[cid] ?? cid))
            var seen = Set<String>()
            for (nid, reason) in links where seen.insert(nid).inserted {
                g.edges.append(GraphEdge(a: nid, b: cid, reason: reason))
            }
        }
        // Drop authors that connect to only one book unless nothing else links that book.
        if let focus, nodeIDs.contains(focus) || g.nodes.contains(where: { $0.id == focus }) {
            g = g.neighborhood(of: focus, hops: 2)
        }
        return g
    }

    /// Subgraph within `hops` of a node.
    func neighborhood(of id: String, hops: Int) -> KnowledgeGraph {
        var keep: Set<String> = [id]
        var frontier: Set<String> = [id]
        for _ in 0..<hops {
            var next = Set<String>()
            for e in edges {
                if frontier.contains(e.a), !keep.contains(e.b) { next.insert(e.b) }
                if frontier.contains(e.b), !keep.contains(e.a) { next.insert(e.a) }
            }
            keep.formUnion(next)
            frontier = next
        }
        var g = KnowledgeGraph()
        g.nodes = nodes.filter { keep.contains($0.id) }
        g.edges = edges.filter { keep.contains($0.a) && keep.contains($0.b) }
        return g
    }

    /// Deterministic force-directed layout (Fruchterman–Reingold) in a unit square centred on 0.
    mutating func layout(iterations: Int = 260) {
        let n = nodes.count
        guard n > 0 else { return }
        let ids = nodes.map(\.id)
        let index = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        var pos: [CGPoint] = ids.map { id in
            var h: UInt64 = 1469598103934665603
            for b in id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
            return CGPoint(x: Double(h % 10_000) / 10_000 - 0.5, y: Double((h / 10_000) % 10_000) / 10_000 - 0.5)
        }
        let pairs = edges.compactMap { e -> (Int, Int)? in
            guard let a = index[e.a], let b = index[e.b], a != b else { return nil }
            return (a, b)
        }
        let k = (1.0 / Double(n)).squareRoot() * 0.9
        var temperature = 0.12
        for _ in 0..<iterations {
            var disp = Array(repeating: CGPoint.zero, count: n)
            for i in 0..<n {
                for j in (i + 1)..<n {
                    var dx = pos[i].x - pos[j].x, dy = pos[i].y - pos[j].y
                    var d2 = dx * dx + dy * dy
                    if d2 < 1e-6 { dx = 0.001 * Double(i - j); dy = 0.001; d2 = dx * dx + dy * dy }
                    let force = k * k / d2
                    disp[i].x += dx * force; disp[i].y += dy * force
                    disp[j].x -= dx * force; disp[j].y -= dy * force
                }
            }
            for (a, b) in pairs {
                let dx = pos[a].x - pos[b].x, dy = pos[a].y - pos[b].y
                let d = max(1e-4, (dx * dx + dy * dy).squareRoot())
                let force = d / k
                disp[a].x -= dx / d * force * d; disp[a].y -= dy / d * force * d
                disp[b].x += dx / d * force * d; disp[b].y += dy / d * force * d
            }
            for i in 0..<n {
                // Gentle gravity keeps disconnected pieces on screen.
                disp[i].x -= pos[i].x * 0.6
                disp[i].y -= pos[i].y * 0.6
                let len = max(1e-6, (disp[i].x * disp[i].x + disp[i].y * disp[i].y).squareRoot())
                let step = min(len, temperature)
                pos[i].x += disp[i].x / len * step
                pos[i].y += disp[i].y / len * step
            }
            temperature *= 0.985
        }
        // Normalize into [-0.5, 0.5].
        let xs = pos.map(\.x), ys = pos.map(\.y)
        let span = max(xs.max()! - xs.min()!, ys.max()! - ys.min()!, 1e-3)
        let cx = (xs.max()! + xs.min()!) / 2, cy = (ys.max()! + ys.min()!) / 2
        positions = Dictionary(uniqueKeysWithValues: ids.enumerated().map { i, id in
            (id, CGPoint(x: (pos[i].x - cx) / span, y: (pos[i].y - cy) / span))
        })
    }
}
