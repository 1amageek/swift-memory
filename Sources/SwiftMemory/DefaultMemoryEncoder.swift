// DefaultMemoryEncoder.swift
// Internal encoder used by Memory to collect Givens

/// Default MemoryEncoder implementation used internally by Memory.
struct DefaultMemoryEncoder: MemoryEncoder {
    private let container = GivenContainer()

    func givenContainer() -> GivenContainer { container }
}
