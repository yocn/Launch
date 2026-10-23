import Foundation

// 事件拦截被系统停用后，30 秒内最多重开 2 次
struct TapReenableLimiter {
    private var times: [Date] = []

    mutating func allows(at now: Date) -> Bool {
        times = times.filter { now.timeIntervalSince($0) < 30 }
        guard times.count < 2 else {
            return false
        }
        times.append(now)
        return true
    }

    mutating func reset() {
        times = []
    }
}
