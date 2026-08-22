//
//  VMCompositionTests.swift
//  MacEngineTests
//
//  The composition bar is only worth drawing if the segments are honest about
//  what they do and do not account for.
//

import Foundation
import Testing
@testable import MacEngine

@Suite("VM composition")
struct VMCompositionTests {

    @Test("Segments always sum to installed RAM")
    func segmentsSumToTotal() {
        let memory = MemoryMetrics(
            totalBytes: 16_000_000_000,
            appBytes: 5_000_000_000,
            wiredBytes: 2_000_000_000,
            compressedBytes: 1_000_000_000,
            freeBytes: 1_000_000_000,
            activeBytes: 4_000_000_000,
            inactiveBytes: 2_000_000_000,
            speculativeBytes: 500_000_000
        )

        let sum = memory.composition.reduce(UInt64(0)) { $0 + $1.bytes }

        #expect(sum == memory.totalBytes)
    }

    @Test("The shortfall is surfaced rather than absorbed")
    func remainderBecomesItsOwnSegment() {
        let memory = MemoryMetrics(
            totalBytes: 10,
            appBytes: 0,
            wiredBytes: 1,
            compressedBytes: 1,
            freeBytes: 1,
            activeBytes: 1,
            inactiveBytes: 1,
            speculativeBytes: 1
        )

        let unaccounted = memory.composition.first { $0.state == .unaccounted }

        #expect(unaccounted?.bytes == 4)
        #expect(memory.compositionCoverage == 0.6)
    }

    /// Counters that overshoot installed RAM — the reads are not atomic, so
    /// this is possible — must not wrap the remainder into a huge number.
    @Test("Counters that overshoot do not underflow the remainder")
    func remainderDoesNotUnderflow() {
        let memory = MemoryMetrics(
            totalBytes: 4,
            appBytes: 0,
            wiredBytes: 4,
            compressedBytes: 4,
            freeBytes: 4,
            activeBytes: 4,
            inactiveBytes: 0,
            speculativeBytes: 0
        )

        let unaccounted = memory.composition.first { $0.state == .unaccounted }

        #expect(unaccounted?.bytes == 0)
        #expect(memory.compositionCoverage == 1)
    }

    @Test("Every state carries a label and an explanation")
    func everyStateIsDocumented() {
        #expect(VMPageState.allCases.allSatisfy { !$0.title.isEmpty && !$0.explanation.isEmpty })
    }

    // MARK: - Against the live machine

    /// The counters never reach installed RAM — firmware and the kernel carve
    /// out memory before the VM system manages any of it, which measures at a
    /// stable ~6% here. The bar shows that gap instead of scaling it away, so
    /// the assertion is that it stays a carve-out and not a bug.
    @Test("This Mac's counters cover the memory the VM actually manages")
    func liveCountersCoverManagedMemory() {
        let memory = MemorySampler().sample()

        #expect(memory.compositionCoverage > 0.85)
        #expect(memory.compositionCoverage <= 1)
        #expect(memory.composition.reduce(UInt64(0)) { $0 + $1.bytes } == memory.totalBytes)
    }

    @Test("Swap and pressure come back from the kernel, not from a guess")
    func liveSwapAndPressureAreReadable() {
        let memory = MemorySampler().sample()

        #expect(memory.swap.usedBytes <= memory.swap.totalBytes || memory.swap.totalBytes == 0)
        #expect(MemoryPressure.allCases.contains(memory.pressure))
        #expect(memory.fileBackedBytes > 0)
    }
}
