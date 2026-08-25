import XCTest
@testable import MacEngine

final class BoundedTopKTests: XCTestCase {
    private func topThree(of scores: [Double]) -> [Double] {
        var heap = BoundedTopK<Double>(capacity: 3)
        for score in scores {
            heap.insert(score, score: score)
        }
        return heap.sortedDescending()
    }

    func testKeepsTheHighestScoresRegardlessOfInsertionOrder() {
        XCTAssertEqual(topThree(of: [1, 9, 3, 7, 5, 2, 8]), [9, 8, 7])
    }

    func testAscendingInputIsTheWorstCaseForAMinHeap() {
        XCTAssertEqual(topThree(of: [1, 2, 3, 4, 5, 6]), [6, 5, 4])
    }

    func testDescendingInputNeverDisplacesTheEarlyLeaders() {
        XCTAssertEqual(topThree(of: [6, 5, 4, 3, 2, 1]), [6, 5, 4])
    }

    func testFewerElementsThanCapacityAreAllKept() {
        XCTAssertEqual(topThree(of: [4, 2]), [4, 2])
    }

    func testThresholdIsNilUntilCapacityIsReached() {
        var heap = BoundedTopK<String>(capacity: 2)
        heap.insert("a", score: 1)
        XCTAssertNil(heap.threshold)
    }

    func testThresholdReportsTheWeakestRetainedScore() {
        var heap = BoundedTopK<String>(capacity: 2)
        heap.insert("a", score: 1)
        heap.insert("b", score: 5)
        XCTAssertEqual(heap.threshold, 1)
    }

    func testTiesKeepTheIncumbentSoRowsDoNotFlicker() {
        var heap = BoundedTopK<String>(capacity: 1)
        heap.insert("first", score: 3)
        heap.insert("second", score: 3)
        XCTAssertEqual(heap.sortedDescending(), ["first"])
    }

    func testZeroCapacityRetainsNothing() {
        var heap = BoundedTopK<String>(capacity: 0)
        heap.insert("a", score: 99)
        XCTAssertTrue(heap.isEmpty)
    }
}
