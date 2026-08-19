//
//  RingBufferTests.swift
//  MacEngineTests
//

import XCTest
@testable import MacEngine

final class RingBufferTests: XCTestCase {

    func testElementsAreEmptyBeforeAnyAppend() {
        let buffer = RingBuffer<Int>(capacity: 4)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.elements, [])
    }

    func testElementsKeepInsertionOrderBelowCapacity() {
        var buffer = RingBuffer<Int>(capacity: 4)
        [1, 2, 3].forEach { buffer.append($0) }
        XCTAssertEqual(buffer.elements, [1, 2, 3])
    }

    func testOldestElementIsEvictedOnceFull() {
        var buffer = RingBuffer<Int>(capacity: 3)
        [1, 2, 3, 4, 5].forEach { buffer.append($0) }
        XCTAssertEqual(buffer.elements, [3, 4, 5])
    }

    func testCountSaturatesAtCapacity() {
        var buffer = RingBuffer<Int>(capacity: 3)
        (0..<10).forEach { buffer.append($0) }
        XCTAssertEqual(buffer.count, 3)
        XCTAssertTrue(buffer.isFull)
    }

    func testFirstAndLastTrackTheWindow() {
        var buffer = RingBuffer<Int>(capacity: 3)
        [1, 2, 3, 4].forEach { buffer.append($0) }
        XCTAssertEqual(buffer.first, 2)
        XCTAssertEqual(buffer.last, 4)
    }

    func testRemoveAllResetsTheWindow() {
        var buffer = RingBuffer<Int>(capacity: 3)
        [1, 2, 3, 4].forEach { buffer.append($0) }
        buffer.removeAll()
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.elements, [])
        buffer.append(9)
        XCTAssertEqual(buffer.elements, [9])
    }

    func testCapacityOfOneKeepsOnlyTheNewestElement() {
        var buffer = RingBuffer<Int>(capacity: 1)
        [1, 2, 3].forEach { buffer.append($0) }
        XCTAssertEqual(buffer.elements, [3])
    }
}
