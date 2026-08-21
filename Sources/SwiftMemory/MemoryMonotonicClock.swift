import Database
#if os(WASI)
import WASILibc
#endif

/// Process-local monotonic time for database deadlines and retry scheduling.
public struct MemoryMonotonicClock: StorageMonotonicClock {
    #if !os(WASI)
    private static let clock = ContinuousClock()
    private static let origin = clock.now
    #endif

    public init() {}

    public var now: StorageInstant {
        #if os(WASI)
        var nanoseconds: __wasi_timestamp_t = 0
        let result = __wasi_clock_time_get(
            1,
            1_000_000,
            &nanoseconds
        )
        precondition(result == 0, "WASI monotonic clock is unavailable")
        return StorageInstant(
            durationSinceReference: Duration(
                secondsComponent: Int64(nanoseconds / 1_000_000_000),
                attosecondsComponent: Int64(nanoseconds % 1_000_000_000) * 1_000_000_000
            )
        )
        #else
        StorageInstant(
            durationSinceReference: Self.origin.duration(to: Self.clock.now)
        )
        #endif
    }

    public func sleep(
        until deadline: StorageInstant
    ) async throws(StorageClockError) {
        let remaining = now.duration(to: deadline)
        guard remaining > .zero else { return }
        #if os(WASI)
        guard !Task.isCancelled else { throw .cancelled }
        let components = remaining.components
        var request = timespec(
            tv_sec: time_t(components.seconds),
            tv_nsec: Int(components.attoseconds / 1_000_000_000)
        )
        guard nanosleep(&request, nil) == 0 else { throw .unavailable }
        guard !Task.isCancelled else { throw .cancelled }
        #else
        do {
            try await Self.clock.sleep(for: remaining)
        } catch {
            throw .cancelled
        }
        #endif
    }
}
