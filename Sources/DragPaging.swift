import Foundation

/// A stationary pointer can turn several pages, but never runs past either end.
struct DragPageDwell {
    static let delay: TimeInterval = 0.55
    private(set) var direction = 0
    private var entered: TimeInterval = 0
    mutating func reset() { direction = 0; entered = 0 }
    mutating func update(direction next: Int, page: Int, count: Int, now: TimeInterval) -> Int? {
        let valid = next == -1 && page > 0 || next == 1 && page + 1 < count
        guard valid else { reset(); return nil }
        guard direction == next else { direction = next; entered = now; return nil }
        guard now - entered >= Self.delay else { return nil }
        entered = now
        return page + next
    }
}
