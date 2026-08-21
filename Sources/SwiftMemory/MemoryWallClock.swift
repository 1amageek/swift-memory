import Database
#if os(WASI)
import WASILibc
#else
import Foundation
#endif

/// System wall time used for persisted memory timestamps.
public struct MemoryWallClock: WallClock {
    public init() {}

    public var now: Timestamp {
        #if os(WASI)
        var nanoseconds: __wasi_timestamp_t = 0
        let result = __wasi_clock_time_get(
            0,
            1_000_000,
            &nanoseconds
        )
        precondition(result == 0, "WASI realtime clock is unavailable")
        return Timestamp(secondsSinceUnixEpoch: Int64(nanoseconds / 1_000_000_000))
        #else
        Timestamp(secondsSinceUnixEpoch: Int64(Date().timeIntervalSince1970))
        #endif
    }
}
