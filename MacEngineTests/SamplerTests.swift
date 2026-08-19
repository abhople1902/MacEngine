//
//  SamplerTests.swift
//  MacEngineTests
//
//  These run against the live machine inside the sandboxed host app, so they
//  also prove the Mach and volume queries survive the app's entitlements.
//

import XCTest
@testable import MacEngine

final class SamplerTests: XCTestCase {

    func testFirstCPUSampleReportsIdleBecauseThereIsNoBaseline() {
        let sample = CPUSampler().sample()
        XCTAssertEqual(sample.idleFraction, 1)
        XCTAssertEqual(sample.busyFraction, 0)
        XCTAssertGreaterThan(sample.coreCount, 0)
    }

    func testSecondCPUSampleReportsFractionsThatSumToOne() {
        let sampler = CPUSampler()
        _ = sampler.sample()
        burnCPUBriefly()
        let sample = sampler.sample()

        let total = sample.userFraction + sample.systemFraction
            + sample.niceFraction + sample.idleFraction
        XCTAssertEqual(total, 1, accuracy: 0.001)
        XCTAssertTrue((0...1).contains(sample.busyFraction))
    }

    func testResetDiscardsTheBaseline() {
        let sampler = CPUSampler()
        _ = sampler.sample()
        burnCPUBriefly()
        sampler.reset()
        XCTAssertEqual(sampler.sample().idleFraction, 1)
    }

    func testMemorySampleDescribesThisMachine() {
        let memory = MemorySampler().sample()
        XCTAssertGreaterThan(memory.totalBytes, 0)
        XCTAssertGreaterThan(memory.usedBytes, 0)
        XCTAssertLessThan(memory.usedBytes, memory.totalBytes)
        XCTAssertTrue((0...1).contains(memory.usedFraction))
    }

    func testDiskSampleDescribesTheBootVolume() {
        let disk = DiskSampler().sample()
        XCTAssertGreaterThan(disk.totalBytes, 0)
        XCTAssertLessThanOrEqual(disk.availableBytes, disk.totalBytes)
        XCTAssertFalse(disk.volumeName.isEmpty)
    }

    func testDiskSampleIsServedFromCacheWithinTheRefreshWindow() {
        let sampler = DiskSampler()
        let now = Date()
        let first = sampler.sample(now: now)
        let second = sampler.sample(now: now.addingTimeInterval(1))
        XCTAssertEqual(first, second)
    }

    private func burnCPUBriefly() {
        let deadline = Date().addingTimeInterval(0.05)
        var accumulator = 0.0
        while Date() < deadline {
            accumulator += Double.random(in: 0...1).squareRoot()
        }
        XCTAssertGreaterThan(accumulator, 0)
    }
}
