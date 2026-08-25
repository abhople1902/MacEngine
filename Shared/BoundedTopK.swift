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

        guard let weakest = storage.first, score > weakest.score else { return }
        storage[0] = (score, value)
        siftDown(from: 0)
    }

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
