import Foundation

/// Keyed decoding helpers for the lenient `#[serde(default)]` fields used by
/// the server. A missing key falls back, but a present key with the wrong type
/// still throws (which surfaces as `APIError.invalid_response`).
extension KeyedDecodingContainer {
    func mngValue<T: Decodable>(
        _ key: Key,
        default defaultValue: @autoclosure () -> T
    ) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? defaultValue()
    }
}
