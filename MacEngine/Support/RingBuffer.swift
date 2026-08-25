import Foundation

nonisolated struct RingBuffer<Element> {
    private var storage: [Element?]
    private var writeIndex = 0
    private(set) var count = 0

    let capacity: Int

    init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer needs a capacity of at least 1")
        self.capacity = capacity
        storage = Array(repeating: nil, count: capacity)
    }

    var isEmpty: Bool { count == 0 }
    var isFull: Bool { count == capacity }

    mutating func append(_ element: Element) {
        storage[writeIndex] = element
        writeIndex = (writeIndex + 1) % capacity
        if count < capacity { count += 1 }
    }

    var elements: [Element] {
        guard count > 0 else { return [] }
        let start = isFull ? writeIndex : 0
        return (0..<count).compactMap { storage[(start + $0) % capacity] }
    }

    var last: Element? {
        guard count > 0 else { return nil }
        return storage[(writeIndex + capacity - 1) % capacity]
    }

    var first: Element? {
        guard count > 0 else { return nil }
        return storage[isFull ? writeIndex : 0]
    }

    mutating func removeAll() {
        storage = Array(repeating: nil, count: capacity)
        writeIndex = 0
        count = 0
    }
}

nonisolated extension RingBuffer: Sequence {
    func makeIterator() -> IndexingIterator<[Element]> {
        elements.makeIterator()
    }
}
