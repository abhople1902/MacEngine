//
//  ProcessSamplerTests.swift
//  MacEngineTests
//
//  Runs against the live process table, so assertions stay on properties that
//  hold on any Mac rather than on specific processes or numbers.
//

import XCTest
@testable import MacEngine

final class ProcessSamplerTests: XCTestCase {
    func testSampleNeverExceedsTheRequestedLimit() {
        let sampler = ProcessSampler()
        XCTAssertLessThanOrEqual(sampler.sample(limit: 3).count, 3)
    }

    func testEveryRowDescribesARealProcess() throws {
        let sampler = ProcessSampler()
        let processes = sampler.sample(limit: 5)
        let sample = try XCTUnwrap(processes.first)

        XCTAssertGreaterThan(sample.pid, 0)
        XCTAssertFalse(sample.name.isEmpty)
    }

    func testFirstSampleHasNoCPUBaselineSoReportsZero() {
        let sampler = ProcessSampler()
        let processes = sampler.sample(limit: 5)
        XCTAssertTrue(processes.allSatisfy { $0.cpuFraction == 0 })
    }

    func testRowsArriveSortedByCPUDescending() {
        let sampler = ProcessSampler()
        _ = sampler.sample(limit: 5, now: Date())
        // Give the machine an interval to accumulate CPU time against.
        let second = sampler.sample(limit: 5, now: Date().addingTimeInterval(0.5))

        let fractions = second.map(\.cpuFraction)
        XCTAssertEqual(fractions, fractions.sorted(by: >))
    }

    func testResetDiscardsTheBaselineSoUsageStartsOver() {
        let sampler = ProcessSampler()
        _ = sampler.sample(limit: 5, now: Date())
        sampler.reset()

        let afterReset = sampler.sample(limit: 5, now: Date().addingTimeInterval(0.5))
        XCTAssertTrue(afterReset.allSatisfy { $0.cpuFraction == 0 })
    }
}
