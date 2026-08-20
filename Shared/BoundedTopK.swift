//
//  BoundedTopK.swift
//  Shared
//
//  Keeps the K highest-scoring elements out of a stream without retaining or
//  sorting the whole stream. There are ~600 processes on a normal Mac and the
//  dashboard shows five of them, so sorting everything to throw away 99% of the
//  result is the obvious waste to avoid: this is O(n log k) and holds k
//  elements, against O(n log n) and n for a full sort.
//
//  Implemented as a min-heap of the survivors, so the element most at risk of
//  being displaced is always the root and the comparison against it is O(1).
//

import Foundation

nonisolated struct BoundedTopK<Element> {
    private var storage: [(score: Double, value: Element)] = []
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = Swift.max(capacity, 0)
        storage.reserveCapacity(self.capacity)
    }

    var count: Int { storage.count }
    var isEmpty: Bool { storage.isEmpty }

    /// The lowest score currently retained, or `nil` while below capacity.
    var threshold: Double? {
        storage.count < capacity ? nil : storage.first?.score
    }

    mutating func insert(_ value: Element, score: Double) {
        guard capacity > 0 else { return }

        if storage.count < capacity {
            storage.append((score, value))
            siftUp(from: storage.count - 1)
            return
        }

        // Ties keep the incumbent: a process that is already on screen should
        // not flicker out for an equal-scoring newcomer.
        guard let weakest = storage.first, score > weakest.score else { return }
        storage[0] = (score, value)
        siftDown(from: 0)
    }

    /// Highest score first. Sorting happens once, over at most `capacity` items.
    func sortedDescending() -> [Element] {
        storage.sorted { $0.score > $1.score }.map(\.value)
    }

    private mutating func siftUp(from index: Int) {
        var child = index
        while child > 0 {
            let parent = (child - 1) / 2
            guard storage[child].score < storage[parent].score else { return }
            storage.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func siftDown(from index: Int) {
        var parent = index
        while true {
            let left = parent * 2 + 1
            let right = left + 1
            var smallest = parent

            if left < storage.count, storage[left].score < storage[smallest].score {
                smallest = left
            }
            if right < storage.count, storage[right].score < storage[smallest].score {
                smallest = right
            }
            guard smallest != parent else { return }

            storage.swapAt(parent, smallest)
            parent = smallest
        }
    }
}
