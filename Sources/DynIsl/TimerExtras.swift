import Foundation

extension Timer {
    @discardableResult
    static func repeating(every interval: TimeInterval, tolerance ratio: Double = 0.2,
                          _ block: @escaping @Sendable (Timer) -> Void) -> Timer {
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true, block: block)
        t.tolerance = interval * ratio
        return t
    }
}
