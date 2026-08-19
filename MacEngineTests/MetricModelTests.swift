//
//  MetricModelTests.swift
//  MacEngineTests
//
//  The arithmetic every reading passes through before it reaches the UI.
//

import XCTest
@testable import MacEngine

final class MetricModelTests: XCTestCase {

    // MARK: - CPU

    func testBusyFractionIsTheComplementOfIdle() {
        let cpu = CPUMetrics(
            userFraction: 0.2,
            systemFraction: 0.1,
            niceFraction: 0.05,
            idleFraction: 0.65,
            coreCount: 8
        )
        XCTAssertEqual(cpu.busyFraction, 0.35, accuracy: 0.0001)
    }

    func testBusyFractionClampsWhenCountersDisagree() {
        let cpu = CPUMetrics(
            userFraction: 0.8,
            systemFraction: 0.5,
            niceFraction: 0.1,
            idleFraction: 0,
            coreCount: 8
        )
        XCTAssertEqual(cpu.busyFraction, 1.0)
    }

    // MARK: - Memory

    func testUsedMemoryIsAppPlusWiredPlusCompressed() {
        let memory = MemoryMetrics(
            totalBytes: 16_000_000_000,
            appBytes: 6_000_000_000,
            wiredBytes: 2_000_000_000,
            compressedBytes: 1_000_000_000,
            freeBytes: 7_000_000_000
        )
        XCTAssertEqual(memory.usedBytes, 9_000_000_000)
        XCTAssertEqual(memory.usedFraction, 0.5625, accuracy: 0.0001)
    }

    func testMemoryPressureCrossesIntoWarningAtSeventyPercent() {
        XCTAssertEqual(memory(usedFraction: 0.69).pressure, .normal)
        XCTAssertEqual(memory(usedFraction: 0.70).pressure, .warning)
        XCTAssertEqual(memory(usedFraction: 0.89).pressure, .warning)
        XCTAssertEqual(memory(usedFraction: 0.90).pressure, .critical)
    }

    func testUsedFractionIsZeroWhenTotalIsUnknown() {
        XCTAssertEqual(MemoryMetrics.zero.usedFraction, 0)
    }

    // MARK: - Disk

    func testDiskUsedIsCapacityMinusAvailable() {
        let disk = DiskMetrics(
            volumeName: "Macintosh HD",
            totalBytes: 500_000_000_000,
            availableBytes: 200_000_000_000
        )
        XCTAssertEqual(disk.usedBytes, 300_000_000_000)
        XCTAssertEqual(disk.usedFraction, 0.6, accuracy: 0.0001)
    }

    func testDiskUsedDoesNotUnderflowWhenAvailableExceedsCapacity() {
        let disk = DiskMetrics(volumeName: "Odd", totalBytes: 100, availableBytes: 400)
        XCTAssertEqual(disk.usedBytes, 0)
    }

    // MARK: - Snapshot coding

    func testSnapshotSurvivesTheJSONRoundTripUsedByXPC() throws {
        let original = MetricSnapshot(
            cpu: CPUMetrics(userFraction: 0.1, systemFraction: 0.1, niceFraction: 0, idleFraction: 0.8, coreCount: 10),
            memory: memory(usedFraction: 0.5),
            disk: DiskMetrics(volumeName: "Macintosh HD", totalBytes: 100, availableBytes: 40),
            topProcesses: [ProcessSample(pid: 42, name: "Xcode", cpuFraction: 0.18, memoryBytes: 1_800_000_000)]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MetricSnapshot.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - Helpers

    private func memory(usedFraction: Double) -> MemoryMetrics {
        let total: UInt64 = 16_000_000_000
        return MemoryMetrics(
            totalBytes: total,
            appBytes: UInt64(Double(total) * usedFraction),
            wiredBytes: 0,
            compressedBytes: 0,
            freeBytes: total - UInt64(Double(total) * usedFraction)
        )
    }
}
