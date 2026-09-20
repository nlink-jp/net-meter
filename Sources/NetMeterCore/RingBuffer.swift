/// A fixed-capacity buffer that overwrites its oldest element.
public struct RingBuffer<Element: Sendable>: Sendable {
    private var storage: [Element] = []
    private var next = 0
    public let capacity: Int

    public init(capacity: Int) {
        precondition(capacity > 0, "a ring buffer needs room for at least one element")
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[next] = element
        }
        next = (next + 1) % capacity
    }

    /// Oldest first.
    public var elements: [Element] {
        guard storage.count == capacity else { return storage }
        return Array(storage[next...] + storage[..<next])
    }

    public var last: Element? {
        guard !storage.isEmpty else { return nil }
        return storage[(next + capacity - 1) % capacity]
    }
}
