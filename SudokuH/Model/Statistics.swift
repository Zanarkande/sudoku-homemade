import Foundation

/// The groups statistics are kept for. Every game belongs to exactly one:
/// daily puzzles to `.daily`, hardcore games to `.hardcore`, the rest to their difficulty.
nonisolated enum StatCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    // The first four raw values match `Difficulty`, which is how statistics were first saved.
    case easy, medium, hard, expert, hardcore, daily

    var id: String { rawValue }

    init(_ difficulty: Difficulty) {
        switch difficulty {
        case .easy: self = .easy
        case .medium: self = .medium
        case .hard: self = .hard
        case .expert: self = .expert
        }
    }

    init(_ game: GameState) {
        if game.isDaily {
            self = .daily
        } else if game.isHardcore {
            self = .hardcore
        } else {
            self.init(game.difficulty)
        }
    }

    var title: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        case .expert: "Expert"
        case .hardcore: "Hardcore"
        case .daily: "Daily Puzzle"
        }
    }
}

nonisolated struct DifficultyStats: Codable, Equatable, Sendable {
    var played = 0
    var won = 0
    var bestTime: TimeInterval?
    /// Sum of the times of the wins counted in `timedWins` (wins recorded by
    /// older versions of the app have no time, so they are left out of the average).
    var totalWinTime: TimeInterval = 0
    var timedWins = 0
    /// Wins in a row.
    var currentStreak = 0
    var bestStreak = 0

    init(
        played: Int = 0,
        won: Int = 0,
        bestTime: TimeInterval? = nil,
        totalWinTime: TimeInterval = 0,
        timedWins: Int = 0,
        currentStreak: Int = 0,
        bestStreak: Int = 0
    ) {
        self.played = played
        self.won = won
        self.bestTime = bestTime
        self.totalWinTime = totalWinTime
        self.timedWins = timedWins
        self.currentStreak = currentStreak
        self.bestStreak = bestStreak
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        played = try container.decodeIfPresent(Int.self, forKey: .played) ?? 0
        won = try container.decodeIfPresent(Int.self, forKey: .won) ?? 0
        bestTime = try container.decodeIfPresent(TimeInterval.self, forKey: .bestTime)
        totalWinTime = try container.decodeIfPresent(TimeInterval.self, forKey: .totalWinTime) ?? 0
        timedWins = try container.decodeIfPresent(Int.self, forKey: .timedWins) ?? 0
        currentStreak = try container.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        bestStreak = try container.decodeIfPresent(Int.self, forKey: .bestStreak) ?? 0
    }

    /// 0...1, or nil before the first game.
    var winRate: Double? {
        played > 0 ? min(1, Double(won) / Double(played)) : nil
    }

    var averageTime: TimeInterval? {
        timedWins > 0 ? totalWinTime / Double(timedWins) : nil
    }
}

/// One finished game, kept for the history list and the chart.
nonisolated struct GameRecord: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var date: Date
    var difficulty: Difficulty
    var time: TimeInterval
    var mistakes: Int
    var hints: Int
    var isHardcore: Bool
    var isDaily: Bool
    var won: Bool

    var category: StatCategory {
        isDaily ? .daily : isHardcore ? .hardcore : StatCategory(difficulty)
    }
}

nonisolated struct Statistics: Codable, Equatable, Sendable {
    static let historyLimit = 500

    private var entries: [String: DifficultyStats] = [:]
    /// Time spent on games that are finished or were given up.
    private(set) var totalPlayTime: TimeInterval = 0
    /// Finished games, oldest first.
    private(set) var history: [GameRecord] = []
    /// Days (see `DayKey`) on which the daily puzzle was solved, in order.
    private(set) var dailyDays: [Int] = []

    init() {}

    /// Every field is optional so that statistics saved by older versions keep loading.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decodeIfPresent([String: DifficultyStats].self, forKey: .entries) ?? [:]
        totalPlayTime = try container.decodeIfPresent(TimeInterval.self, forKey: .totalPlayTime) ?? 0
        history = try container.decodeIfPresent([GameRecord].self, forKey: .history) ?? []
        dailyDays = try container.decodeIfPresent([Int].self, forKey: .dailyDays) ?? []
    }

    subscript(category: StatCategory) -> DifficultyStats {
        get { entries[category.rawValue] ?? DifficultyStats() }
        set { entries[category.rawValue] = newValue }
    }

    // MARK: - Totals

    var totalPlayed: Int { StatCategory.allCases.reduce(0) { $0 + self[$1].played } }
    var totalWon: Int { StatCategory.allCases.reduce(0) { $0 + self[$1].won } }

    // MARK: - Recording

    mutating func recordStarted(_ category: StatCategory) {
        self[category].played += 1
    }

    /// Returns true if this win set a new best time.
    @discardableResult
    mutating func recordWin(_ category: StatCategory, time: TimeInterval) -> Bool {
        var stats = self[category]
        defer { self[category] = stats }
        stats.won += 1
        stats.totalWinTime += time
        stats.timedWins += 1
        stats.currentStreak += 1
        stats.bestStreak = max(stats.bestStreak, stats.currentStreak)
        if let best = stats.bestTime, best <= time { return false }
        stats.bestTime = time
        return true
    }

    /// A lost game ends the winning streak.
    mutating func recordLoss(_ category: StatCategory) {
        self[category].currentStreak = 0
    }

    /// Giving up a game that was started also ends the winning streak.
    mutating func recordAbandoned(_ category: StatCategory) {
        self[category].currentStreak = 0
    }

    mutating func addPlayTime(_ time: TimeInterval) {
        totalPlayTime += max(0, time)
    }

    mutating func addRecord(_ record: GameRecord) {
        history.append(record)
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
        }
    }

    // MARK: - Daily puzzle

    mutating func markDailySolved(_ day: Int) {
        guard !dailyDays.contains(day) else { return }
        dailyDays.append(day)
        dailyDays.sort()
    }

    func isDailySolved(_ day: Int) -> Bool { dailyDays.contains(day) }

    func dailyStreak(today: Int) -> Int {
        DailyStreak.current(days: Set(dailyDays), today: today)
    }

    var bestDailyStreak: Int {
        DailyStreak.best(days: Set(dailyDays))
    }

    // MARK: - Backup

    /// All statistics as readable text, for backups.
    func exportText() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Reads a backup made with `exportText()`. Returns nil if the text isn't one.
    static func importing(_ text: String) -> Statistics? {
        let data = Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["entries"] is [String: Any] else { return nil }
        return try? JSONDecoder().decode(Statistics.self, from: data)
    }
}
