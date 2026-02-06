import Foundation

/// Thread-safe LRU cache with configurable max size in bytes.
actor LRUCache {
    private var cache: [String: Data] = [:]
    private var accessOrder: [String] = []
    private var currentSize: Int = 0
    let maxSize: Int

    init(maxSize: Int = 100 * 1024 * 1024) { // 100MB default
        self.maxSize = maxSize
    }

    func get(_ key: String) -> Data? {
        guard let data = cache[key] else { return nil }
        // Move to end (most recently used)
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
            accessOrder.append(key)
        }
        return data
    }

    func set(_ key: String, data: Data) {
        // Remove existing entry if present
        if let existing = cache[key] {
            currentSize -= existing.count
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
            }
        }

        // Evict oldest entries until there's room
        while currentSize + data.count > maxSize && !accessOrder.isEmpty {
            let oldest = accessOrder.removeFirst()
            if let removed = cache.removeValue(forKey: oldest) {
                currentSize -= removed.count
            }
        }

        cache[key] = data
        accessOrder.append(key)
        currentSize += data.count
    }

    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
        currentSize = 0
    }

    var usedSize: Int { currentSize }
    var entryCount: Int { cache.count }
}
