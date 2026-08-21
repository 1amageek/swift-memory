import DatabaseKit

enum MemoryIdentifier {
    static func ulid(at timestamp: Timestamp) throws -> String {
        guard timestamp.secondsSinceUnixEpoch >= 0 else {
            throw MemoryError.invalidIdentifierTimestamp(timestamp)
        }
        let milliseconds = UInt64(timestamp.secondsSinceUnixEpoch) * 1_000
            + UInt64(timestamp.nanoseconds / 1_000_000)
        var generator = SystemRandomNumberGenerator()
        let randomness = ByteString(
            (0..<10).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        )
        return try ULID(
            timestampMilliseconds: milliseconds,
            randomness: randomness
        ).ulidString
    }
}
