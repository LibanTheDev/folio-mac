import SwiftUI

// MARK: - Cover

struct CoverView: View {
    let title: String
    let author: String
    /// Low-res first; later URLs are layered on top as they arrive.
    let urls: [URL]
    var cornerRadius: CGFloat = 3

    init(title: String, author: String, url: URL?, cornerRadius: CGFloat = 3) {
        self.init(title: title, author: author, urls: url.map { [$0] } ?? [], cornerRadius: cornerRadius)
    }

    init(title: String, author: String, urls: [URL], cornerRadius: CGFloat = 3) {
        self.title = title
        self.author = author
        self.urls = urls
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        PlaceholderCover(title: title, author: author)
            .overlay {
                ZStack {
                    ForEach(urls, id: \.self) { RemoteImage(url: $0) }
                }
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.black.opacity(0.08)))
            .shadow(color: .black.opacity(0.16), radius: 3, x: 1, y: 2)
    }
}

extension CoverView {
    init(book: Book, size: String = "M") {
        let sizes = size == "L" ? ["M", "L"] : [size]
        self.init(title: book.title, author: book.authorLine, urls: sizes.compactMap { book.coverURL(size: $0) })
    }
}

/// In-memory + URLCache-backed image loader so covers appear instantly when revisited.
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, NSImage>()
    private var inflight: [URL: Task<Data?, Never>] = [:]

    func cached(_ url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> NSImage? {
        if let img = cached(url) { return img }
        let task = inflight[url] ?? Task<Data?, Never> {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return data
        }
        inflight[url] = task
        let data = await task.value
        inflight[url] = nil
        if let img = cached(url) { return img }
        guard let data, let img = NSImage(data: data), img.size.width > 2 else { return nil }
        cache.setObject(img, forKey: url as NSURL)
        return img
    }
}

struct RemoteImage: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill().transition(.opacity)
                }
            }
            .task(id: url) {
            if let hit = ImageCache.shared.cached(url) { image = hit; return }
            let loaded = await ImageCache.shared.load(url)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

struct PlaceholderCover: View {
    let title: String
    let author: String

    var body: some View {
        let hue = stableHue(title + author)
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [Color(hue: hue, saturation: 0.32, brightness: 0.52), Color(hue: hue, saturation: 0.40, brightness: 0.30)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                Rectangle().fill(.white.opacity(0.08)).frame(width: geo.size.width * 0.06).frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: geo.size.height * 0.04) {
                    Text(title)
                        .font(.system(size: max(8, geo.size.width * 0.11), weight: .semibold, design: .serif))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.6)
                    Rectangle().fill(.white.opacity(0.5)).frame(width: geo.size.width * 0.25, height: 1)
                    Text(author)
                        .font(.system(size: max(6, geo.size.width * 0.07)))
                        .lineLimit(2)
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(geo.size.width * 0.12)
            }
        }
    }
}

// MARK: - Rating

struct StarRating: View {
    @Binding var rating: Double?
    var size: CGFloat = 16
    var editable = true
    @State private var hover: Double?

    var body: some View {
        HStack(spacing: size * 0.12) {
            ForEach(1...5, id: \.self) { i in
                let value = hover ?? rating ?? 0
                Image(systemName: symbol(i, value))
                    .font(.system(size: size))
                    .foregroundStyle(value >= Double(i) - 0.5 ? Theme.accent : Theme.faint)
                    .overlay {
                        if editable {
                            HStack(spacing: 0) {
                                hitArea(Double(i) - 0.5)
                                hitArea(Double(i))
                            }
                        }
                    }
            }
        }
        .help(editable ? "Click to rate (half stars supported). Click again to clear." : "")
        .accessibilityElement()
        .accessibilityLabel(rating.map { "\($0.formatted()) stars" } ?? "Not rated")
    }

    private func symbol(_ i: Int, _ value: Double) -> String {
        if value >= Double(i) { return "star.fill" }
        if value >= Double(i) - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }

    private func hitArea(_ v: Double) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { hover = v } else if hover == v { hover = nil }
            }
            .onTapGesture { rating = rating == v ? nil : v }
    }
}

extension StarRating {
    init(value: Double?, size: CGFloat = 10) {
        self.init(rating: .constant(value), size: size, editable: false)
    }
}

// MARK: - Misc

struct ProgressBar: View {
    var value: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.accentSoft)
                Capsule().fill(tint).frame(width: max(height, geo.size.width * value))
            }
        }
        .frame(height: height)
    }
}

struct StatusBadge: View {
    let status: ReadingStatus
    var body: some View {
        Label(status.shortTitle, systemImage: status.symbol)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(status.tint.opacity(0.14), in: Capsule())
            .foregroundStyle(status.tint)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.serif(20, .medium)).foregroundStyle(Theme.ink)
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(Theme.muted) }
            Spacer()
        }
    }
}

// Opening a book (in the inspector) from anywhere.
private struct OpenBookKey: EnvironmentKey {
    static let defaultValue: (UUID) -> Void = { _ in }
}

extension EnvironmentValues {
    var openBook: (UUID) -> Void {
        get { self[OpenBookKey.self] }
        set { self[OpenBookKey.self] = newValue }
    }
}

extension Date {
    var shortString: String { formatted(date: .abbreviated, time: .omitted) }
    var numericString: String { formatted(date: .numeric, time: .omitted) }
}
