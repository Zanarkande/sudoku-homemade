import Foundation

/// A calendar day written as a number, e.g. 20261114 for 14 November 2026.
/// Identifies daily puzzles and the days on which one was solved.
nonisolated enum DayKey {
    private static var calendar: Calendar { Calendar(identifier: .gregorian) }

    static var today: Int { key(for: Date()) }

    static func key(for date: Date) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    /// Noon on the given day (noon avoids daylight-saving edge cases).
    static func date(for key: Int) -> Date? {
        calendar.date(from: DateComponents(year: key / 10_000, month: (key / 100) % 100, day: key % 100, hour: 12))
    }

    static func previous(_ key: Int) -> Int {
        guard let date = date(for: key), let before = calendar.date(byAdding: .day, value: -1, to: date) else {
            return key - 1
        }
        return self.key(for: before)
    }
}

/// Daily streaks, computed from the set of days on which the daily puzzle was solved.
nonisolated enum DailyStreak {
    /// Consecutive solved days up to today. The streak is still alive while
    /// today's puzzle is unsolved, as long as yesterday's was solved.
    static func current(days: Set<Int>, today: Int) -> Int {
        var day = days.contains(today) ? today : DayKey.previous(today)
        var streak = 0
        while days.contains(day) {
            streak += 1
            day = DayKey.previous(day)
        }
        return streak
    }

    /// The longest run of consecutive solved days ever.
    static func best(days: Set<Int>) -> Int {
        var best = 0
        var run = 0
        var last: Int?
        for day in days.sorted() {
            run = (last == DayKey.previous(day)) ? run + 1 : 1
            best = max(best, run)
            last = day
        }
        return best
    }
}
