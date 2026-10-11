import Foundation

extension KeyedDecodingContainer {
    /// Decodes a value if present and well-formed, otherwise returns the default.
    /// Used for every non-essential field so schema additions never break older files.
    func value<T: Decodable>(_ key: Key, _ fallback: @autoclosure () -> T) -> T {
        guard contains(key) else { return fallback() }
        do {
            if try decodeNil(forKey: key) { return fallback() }
            return try decode(T.self, forKey: key)
        } catch {
            return fallback()
        }
    }
}
