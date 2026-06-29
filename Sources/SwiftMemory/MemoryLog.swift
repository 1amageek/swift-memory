// MemoryLog.swift
// Platform-neutral logging helpers.

#if canImport(os)
import os.log
#endif

enum MemoryLog {
    static func info(category: String, _ message: @autoclosure () -> String) {
        #if canImport(os)
        let text = message()
        Logger(subsystem: "com.memory", category: category)
            .info("\(text, privacy: .public)")
        #endif
    }
}
