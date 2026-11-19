import Foundation
import Observation

nonisolated enum SettingsKey {
    static let mistakeLimit = "settings.mistakeLimit"
    static let haptics = "settings.haptics"
    static let showTimer = "settings.showTimer"
    static let sounds = "settings.sounds"
    static let theme = "settings.theme"
    static let largeDigits = "settings.largeDigits"
    static let hardcoreDefault = "settings.hardcoreDefault"
    static let lastDifficulty = "settings.lastDifficulty"
}

/// Connects the game logic to the views: owns the games in progress, the clock,
/// statistics and auto-saving.
@Observable
final class GameSession {
    /// The regular game and today's daily puzzle live side by side,
    /// so opening one never throws away the other.
    private var games: [GameSlot: GameState] = [:]
    private(set) var activeSlot = GameSlot.regular
    private(set) var statistics: Statistics
    /// Time on the clock of the game on the board.
    private(set) var elapsed: TimeInterval = 0
    private(set) var isGenerating = false
    private(set) var isPaused = false
    private(set) var lastWinWasBestTime = false
    /// The current day, refreshed whenever the app comes to the foreground.
    private(set) var today = DayKey.today
    /// The hint being explained. Asking for a hint again applies it.
    private(set) var activeHint: Hint?
    var selected: Int?
    var notesMode = false

    // Counters the views watch to play haptics and sounds.
    private(set) var inputFeedback = 0
    private(set) var errorFeedback = 0
    private(set) var successFeedback = 0

    /// Per-cell counters the board watches to play the "row, column or box completed"
    /// animation, and how long each cell waits so the effect ripples out from the last move.
    private(set) var cellPulses = [Int](repeating: 0, count: BoardGeometry.cellCount)
    private(set) var cellPulseDelays = [Double](repeating: 0, count: BoardGeometry.cellCount)

    @ObservationIgnored private let store: GameStore
    @ObservationIgnored private var sceneActive = true
    @ObservationIgnored private var boardVisible = false
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var lastTick: Date?

    init(store: GameStore = .default) {
        self.store = store
        statistics = store.loadStatistics()
        games[.regular] = store.loadGame(.regular)
        if let daily = store.loadGame(.daily) {
            if daily.dailyDay == today {
                games[.daily] = daily
            } else {
                // Yesterday's unfinished daily puzzle is gone; keep the time spent on it.
                retire(daily, time: daily.elapsed)
                store.save(nil, slot: .daily)
            }
        }
        elapsed = games[.regular]?.elapsed ?? 0
    }

    // MARK: - What the views show

    /// The game on the board.
    var game: GameState? { games[activeSlot] }

    var regularGame: GameState? { games[.regular] }
    var canContinue: Bool { games[.regular]?.status == .playing }

    /// Today's daily puzzle, once it has been opened.
    var dailyGame: GameState? {
        guard let daily = games[.daily], daily.dailyDay == today else { return nil }
        return daily
    }

    var isDailySolved: Bool { statistics.isDailySolved(today) }
    var dailyStreak: Int { statistics.dailyStreak(today: today) }

    func elapsed(in slot: GameSlot) -> TimeInterval {
        slot == activeSlot ? elapsed : games[slot]?.elapsed ?? 0
    }

    /// All the time spent playing, including the games still in progress.
    var totalPlayTime: TimeInterval {
        GameSlot.allCases.reduce(statistics.totalPlayTime) { total, slot in
            games[slot]?.status == .playing ? total + elapsed(in: slot) : total
        }
    }

    /// True when starting a new game from the game screen would throw away the regular game
    /// in progress without the player seeing it: the daily puzzle is on the board and the
    /// parked regular game has been started. The views ask for confirmation first.
    var newGameReplacesParkedGame: Bool {
        activeSlot == .daily && canContinue && games[.regular]?.hasStarted == true
    }

    /// Whether a game started from the game screen should be hardcore:
    /// the same as the game being played, or the setting's default after a daily puzzle.
    var hardcoreForNextGame: Bool {
        if let game, !game.isDaily { return game.isHardcore }
        return UserDefaults.standard.bool(forKey: SettingsKey.hardcoreDefault)
    }

    // MARK: - Starting games

    func newGame(_ difficulty: Difficulty, hardcore: Bool = false) async {
        guard !isGenerating else { return }
        isGenerating = true
        let puzzle = await Task.detached(priority: .userInitiated) {
            SudokuGenerator.generate(difficulty)
        }.value
        isGenerating = false
        start(GameState(puzzle: puzzle, isHardcore: hardcore), in: .regular)
    }

    /// Puts the regular game back on the board.
    func resumeRegular() {
        activate(.regular)
    }

    /// Puts today's daily puzzle on the board, creating it the first time.
    /// Returns false if there is nothing to show.
    func openDaily() async -> Bool {
        today = DayKey.today
        if dailyGame != nil {
            activate(.daily)
            return true
        }
        guard !isDailySolved, !isGenerating else { return false }
        isGenerating = true
        let day = today
        let puzzle = await Task.detached(priority: .userInitiated) {
            DailyPuzzle.puzzle(for: day)
        }.value
        isGenerating = false
        start(GameState(puzzle: puzzle, dailyDay: day), in: .daily)
        return true
    }

    /// Starts the game on the board over. A won game can't be replayed: solving it again
    /// would count a second win (and, for the daily puzzle, a best time on a known grid).
    var canRestart: Bool { game.map { $0.status != .won } ?? false }

    func restart() {
        guard canRestart, var restarted = game else { return }
        restarted.restart()
        start(restarted, in: activeSlot)
    }

    private func start(_ newGame: GameState, in slot: GameSlot) {
        park()
        if let replaced = games[slot] {
            retire(replaced, time: elapsed(in: slot))
        }
        games[slot] = newGame
        activeSlot = slot
        elapsed = 0
        resetBoardState()
        save()
        updateClock()
    }

    private func activate(_ slot: GameSlot) {
        if slot != activeSlot {
            park()
            activeSlot = slot
            elapsed = games[slot]?.elapsed ?? 0
            resetBoardState()
        }
        updateClock()
    }

    /// Stops the clock and saves the game on the board before another one takes its place.
    private func park() {
        stopClock()
        save()
    }

    private func resetBoardState() {
        selected = nil
        notesMode = false
        isPaused = false
        activeHint = nil
        lastWinWasBestTime = false
    }

    /// Accounts for a game that is being thrown away.
    private func retire(_ game: GameState, time: TimeInterval) {
        guard game.status == .playing else { return } // finished games were already counted
        statistics.addPlayTime(time)
        if game.hasStarted {
            statistics.recordAbandoned(StatCategory(game))
        }
        store.save(statistics)
    }

    // MARK: - Player actions

    func select(_ index: Int) {
        guard game?.status == .playing, !isPaused else { return }
        selected = index
    }

    func enter(_ digit: Int) {
        guard let selected, var updated = game else { return }
        let outcome = notesMode
            ? updated.toggleNote(digit, at: selected)
            : updated.place(
                digit,
                at: selected,
                enforceMistakeLimit: UserDefaults.standard.bool(forKey: SettingsKey.mistakeLimit)
            )
        commit(updated, outcome, filled: selected)
    }

    func erase() {
        guard let selected, var updated = game else { return }
        let outcome = updated.erase(at: selected)
        commit(updated, outcome)
    }

    func undo() {
        guard var updated = game else { return }
        let outcome = updated.undo()
        commit(updated, outcome)
    }

    /// First call: explains the easiest technique that applies and highlights its cells.
    /// Second call: applies the hint. Hardcore games have no hints.
    func hint() {
        guard var updated = game, updated.status == .playing, !updated.isHardcore, !isPaused else { return }
        if let hint = activeHint {
            selected = hint.cell
            switch hint.action {
            case .erase:
                let outcome = updated.erase(at: hint.cell)
                commit(updated, outcome)
            case .place:
                let result = updated.hint(preferring: hint.cell, countsAsHint: false)
                commit(updated, result.outcome, filled: result.index)
            }
            activeHint = nil
            return
        }
        guard let hint = HintEngine.hint(
            values: updated.values, solution: updated.puzzle.solution, preferred: selected
        ) else { return }
        let wasStarted = updated.hasStarted
        updated.registerHint()
        if !wasStarted {
            statistics.recordStarted(StatCategory(updated))
            store.save(statistics)
        }
        games[activeSlot] = updated
        activeHint = hint
        inputFeedback += 1
        save()
    }

    func dismissHint() {
        activeHint = nil
    }

    /// `filled` is the cell the move put a digit in, if any; completion animations start there.
    private func commit(_ updated: GameState, _ outcome: MoveOutcome, filled: Int? = nil) {
        guard outcome != .ignored, let previous = game else { return }
        var updated = updated
        activeHint = nil
        if !previous.hasStarted && updated.hasStarted {
            statistics.recordStarted(StatCategory(updated))
            store.save(statistics)
        }
        switch outcome {
        case .ignored:
            break
        case .changed:
            inputFeedback += 1
        case .mistake:
            errorFeedback += 1
        case .lost:
            errorFeedback += 1
            finish(&updated)
        case .won:
            successFeedback += 1
            finish(&updated)
        }
        games[activeSlot] = updated
        // A completed row would give away that it is right, so hardcore games don't celebrate it.
        if let filled, !updated.isHardcore {
            pulse(updated.completedUnits.subtracting(previous.completedUnits), from: filled)
        }
        save()
    }

    /// Records a game that was just won or lost.
    private func finish(_ finished: inout GameState) {
        stopClock()
        finished.elapsed = elapsed
        let won = finished.status == .won
        let category = StatCategory(finished)
        statistics.addPlayTime(elapsed)
        statistics.addRecord(GameRecord(
            date: Date(),
            difficulty: finished.difficulty,
            time: elapsed,
            mistakes: finished.mistakes,
            hints: finished.hintsUsed,
            isHardcore: finished.isHardcore,
            isDaily: finished.isDaily,
            won: won
        ))
        if won {
            lastWinWasBestTime = statistics.recordWin(category, time: elapsed)
            if let day = finished.dailyDay {
                statistics.markDailySolved(day)
            }
        } else {
            statistics.recordLoss(category)
        }
        store.save(statistics)
    }

    private func pulse(_ units: Set<Int>, from origin: Int) {
        for index in Set(units.flatMap { BoardGeometry.units[$0] }) {
            let distance = abs(BoardGeometry.row(of: index) - BoardGeometry.row(of: origin))
                + abs(BoardGeometry.column(of: index) - BoardGeometry.column(of: origin))
            cellPulseDelays[index] = Double(distance) * 0.045
            cellPulses[index] += 1
        }
    }

    // MARK: - Statistics

    func resetStatistics() {
        statistics = Statistics()
        store.save(statistics)
    }

    /// Replaces the statistics with a backup made by the export feature.
    /// Returns false (and changes nothing) if the text is not a valid backup.
    func importStatistics(from text: String) -> Bool {
        guard let imported = Statistics.importing(text) else { return false }
        statistics = imported
        store.save(statistics)
        return true
    }

    // MARK: - Clock

    func togglePause() {
        guard game?.status == .playing else { return }
        isPaused.toggle()
        updateClock()
    }

    /// Called when the app moves between foreground and background.
    func setSceneActive(_ active: Bool) {
        sceneActive = active
        if active { today = DayKey.today }
        updateClock()
    }

    /// Called when the game screen appears or disappears.
    func setBoardVisible(_ visible: Bool) {
        boardVisible = visible
        updateClock()
    }

    private func updateClock() {
        let shouldRun = sceneActive && boardVisible && !isPaused && game?.status == .playing
        if shouldRun {
            startClock()
        } else {
            stopClock()
            save()
        }
    }

    private func startClock() {
        guard clock == nil else { return }
        lastTick = Date()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    private func stopClock() {
        guard clock != nil else { return }
        tick()
        clock?.cancel()
        clock = nil
        lastTick = nil
    }

    private func tick() {
        guard let lastTick else { return }
        let now = Date()
        elapsed += now.timeIntervalSince(lastTick)
        self.lastTick = now
    }

    // MARK: - Persistence

    private func save() {
        guard var snapshot = game else { return }
        if snapshot.status == .playing { snapshot.elapsed = elapsed }
        if snapshot != games[activeSlot] { games[activeSlot] = snapshot }
        store.save(snapshot, slot: activeSlot)
    }
}
