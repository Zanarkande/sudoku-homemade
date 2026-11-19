import Foundation
import Testing
@testable import SudokuH

private func mask(_ digits: Int...) -> UInt16 {
    digits.reduce(0) { $0 | HintEngine.bit($1) }
}

private let emptyCandidates = [UInt16](repeating: 0, count: 81)

@Suite struct HintTests {
    let puzzle = Puzzle(difficulty: .easy, givens: samplePuzzle, solution: sampleSolution)

    @Test func candidatesLeaveOutDigitsSeenByTheCell() {
        let candidates = HintEngine.candidates(for: samplePuzzle)
        #expect(candidates[0] == 0) // filled cell
        // Row 0, column 2: the row has 5, 3, 7; the column has 8; the box has 5, 3, 6, 9, 8.
        #expect(candidates[2] == mask(1, 2, 4))
    }

    @Test func aWrongDigitIsPointedOutFirst() {
        var values = samplePuzzle
        values[2] = 1 // the solution is 4
        let hint = HintEngine.hint(values: values, solution: sampleSolution)
        #expect(hint?.technique == .mistake)
        #expect(hint?.action == .erase)
        #expect(hint?.cell == 2)
    }

    @Test func lastEmptyCellOfAUnitIsTheEasiestHint() {
        var values = sampleSolution
        values[40] = 0
        let hint = HintEngine.hint(values: values, solution: sampleSolution)
        #expect(hint?.technique == .lastCell)
        #expect(hint?.cell == 40)
        #expect(hint?.digit == sampleSolution[40])
        #expect(hint?.action == .place)
    }

    @Test func nakedSingleIsFound() {
        var candidates = emptyCandidates
        candidates[0] = mask(7)
        candidates[1] = mask(2, 7)
        candidates[2] = mask(2, 7, 9)
        candidates[9] = mask(2, 9) // keeps column 0 from being a "last empty cell"
        #expect(HintEngine.findSingle(in: candidates) == .init(cell: 0, digit: 7, kind: .naked))
    }

    @Test func hiddenSingleIsFound() {
        var candidates = emptyCandidates
        candidates[0] = mask(1, 2, 9) // 9 fits nowhere else in the box, row or column
        candidates[1] = mask(1, 2)
        candidates[2] = mask(1, 2)
        let single = HintEngine.findSingle(in: candidates)
        #expect(single?.cell == 0)
        #expect(single?.digit == 9)
        #expect(single?.kind == .hidden(unit: 18))
    }

    @Test func preferredCellWinsWhenItHasASingle() {
        var candidates = emptyCandidates
        candidates[0] = mask(7)
        candidates[40] = mask(3)
        #expect(HintEngine.findSingle(in: candidates, preferred: 40)?.cell == 40)
        #expect(HintEngine.findSingle(in: candidates, preferred: 5)?.cell == 0)
    }

    @Test func pointingPairRemovesTheDigitFromTheRestOfTheLine() {
        var candidates = emptyCandidates
        candidates[0] = mask(1, 5)
        candidates[1] = mask(2, 5)
        candidates[5] = mask(5, 7) // same row, another box
        let found = HintEngine.pointingPairs(in: candidates)
        #expect(found.count == 1)
        #expect(found.first?.technique == .pointingPair)
        #expect(found.first?.patternCells == [0, 1])
        #expect(found.first?.removals == [5: mask(5)])
        let after = HintEngine.applying(found[0], to: candidates)
        #expect(after[5] == mask(7))
    }

    @Test func boxLineReductionRemovesTheDigitFromTheRestOfTheBox() {
        var candidates = emptyCandidates
        candidates[0] = mask(1, 5)
        candidates[1] = mask(2, 5)
        candidates[9] = mask(5, 8) // same box, next row
        #expect(HintEngine.pointingPairs(in: candidates).isEmpty)
        let found = HintEngine.boxLineReductions(in: candidates)
        #expect(found.contains { $0.technique == .boxLine && $0.removals == [9: mask(5)] })
    }

    @Test func nakedPairRemovesItsDigitsFromTheUnit() {
        var candidates = emptyCandidates
        candidates[0] = mask(3, 4)
        candidates[1] = mask(3, 4)
        candidates[7] = mask(3, 9)
        let found = HintEngine.nakedPairs(in: candidates)
        #expect(found.contains { $0.patternCells == [0, 1] && $0.removals == [7: mask(3)] })
        #expect(found.allSatisfy { $0.technique == .nakedPair })
    }

    @Test func hiddenPairClearsTheOtherCandidatesOfItsCells() {
        var candidates = emptyCandidates
        candidates[0] = mask(1, 2, 5)
        candidates[4] = mask(1, 2, 6)
        candidates[8] = mask(5, 6)
        let found = HintEngine.hiddenPairs(in: candidates)
        #expect(found.contains { $0.patternCells == [0, 4] && $0.removals == [0: mask(5), 4: mask(6)] })
    }

    @Test func nakedTripleRemovesItsDigitsFromTheUnit() {
        var candidates = emptyCandidates
        candidates[0] = mask(1, 2)
        candidates[4] = mask(2, 3)
        candidates[8] = mask(1, 3)
        candidates[6] = mask(1, 9)
        let found = HintEngine.nakedTriples(in: candidates)
        #expect(found.contains { $0.patternCells == [0, 4, 8] && $0.removals == [6: mask(1)] })
    }

    @Test func hiddenTripleClearsTheOtherCandidatesOfItsCells() {
        var candidates = emptyCandidates
        candidates[0] = mask(1, 2, 7)
        candidates[4] = mask(2, 3, 8)
        candidates[8] = mask(1, 3)
        candidates[6] = mask(7, 8)
        let found = HintEngine.hiddenTriples(in: candidates)
        #expect(found.contains { $0.patternCells == [0, 4, 8] && $0.removals == [0: mask(7), 4: mask(8)] })
    }

    @Test func xWingRemovesTheDigitFromTheCrossingLines() {
        var candidates = emptyCandidates
        // 5 fits only in columns 1 and 7 of rows 0 and 4.
        candidates[1] = mask(1, 5)
        candidates[7] = mask(2, 5)
        candidates[37] = mask(3, 5)
        candidates[43] = mask(4, 5)
        candidates[19] = mask(5, 9) // row 2, column 1
        let found = HintEngine.xWings(in: candidates)
        #expect(found.contains { $0.technique == .xWing && $0.removals == [19: mask(5)] })
    }

    @Test func xyWingRemovesTheSharedDigitFromCellsSeeingBothWings() {
        var candidates = emptyCandidates
        candidates[0] = mask(1, 2)  // pivot
        candidates[4] = mask(1, 3)  // same row
        candidates[27] = mask(2, 3) // same column
        candidates[31] = mask(3, 9) // sees both wings
        let found = HintEngine.xyWings(in: candidates)
        #expect(found.count == 1)
        #expect(found.first?.patternCells == [0, 4, 27])
        #expect(found.first?.removals == [31: mask(3)])
    }

    @Test func aWrongGuessRunsIntoADeadEnd() {
        let candidates = HintEngine.candidates(for: samplePuzzle)
        // Row 0, column 2 can be 1, 2 or 4; the solution is 4.
        #expect(HintEngine.deadEnd(assuming: 1, at: 2, values: samplePuzzle, candidates: candidates) != nil)
        #expect(HintEngine.deadEnd(assuming: 4, at: 2, values: samplePuzzle, candidates: candidates) == nil)
    }

    @Test func eliminationHintExplainsTheTechniqueAndFillsTheUnlockedCell() {
        // A real position where no single exists is hard to write by hand, so check the
        // engine on generated hard puzzles: following its hints must always solve them.
        var rng = SeededGenerator(state: 2026)
        var techniques: [Hint.Technique: Int] = [:]
        for difficulty in [Difficulty.hard, .expert] {
            for _ in 0..<4 {
                let puzzle = SudokuGenerator.generate(difficulty, using: &rng)
                var values = puzzle.givens
                while values.contains(0) {
                    guard let hint = HintEngine.hint(values: values, solution: puzzle.solution) else {
                        Issue.record("No hint for an unfinished board")
                        return
                    }
                    #expect(hint.action == .place)
                    #expect(values[hint.cell] == 0)
                    #expect(hint.digit == puzzle.solution[hint.cell])
                    #expect(!hint.explanation.isEmpty)
                    techniques[hint.technique, default: 0] += 1
                    values[hint.cell] = hint.digit
                }
                #expect(values == puzzle.solution)
            }
        }
        let advanced: Set<Hint.Technique> = [
            .pointingPair, .boxLine, .nakedPair, .hiddenPair, .nakedTriple, .hiddenTriple, .xWing, .xyWing,
        ]
        #expect(techniques.keys.contains { advanced.contains($0) })
        // Revealing a cell without a reason is the very last resort.
        #expect(techniques[.reveal, default: 0] == 0)
        #expect(techniques[.hiddenSingle, default: 0] > 0)
    }

    @Test func easyPuzzlesOnlyNeedSingles() {
        var values = samplePuzzle
        while values.contains(0) {
            guard let hint = HintEngine.hint(values: values, solution: sampleSolution) else { break }
            #expect([.lastCell, .nakedSingle, .hiddenSingle].contains(hint.technique))
            values[hint.cell] = hint.digit
        }
        #expect(values == sampleSolution)
    }

    @Test func noHintForASolvedBoard() {
        #expect(HintEngine.hint(values: sampleSolution, solution: sampleSolution) == nil)
    }
}

@Suite struct DailyPuzzleTests {
    @Test func sameDayAlwaysGivesTheSamePuzzle() {
        let first = DailyPuzzle.puzzle(for: 2026_11_14)
        let second = DailyPuzzle.puzzle(for: 2026_11_14)
        #expect(first == second)
    }

    @Test func differentDaysGiveDifferentPuzzles() {
        let puzzles = [2026_11_14, 2026_11_15, 2026_11_16, 2027_11_14].map(DailyPuzzle.puzzle(for:))
        #expect(Set(puzzles.map(\.givens)).count == puzzles.count)
    }

    @Test func dailyPuzzleIsAValidMediumPuzzle() {
        let puzzle = DailyPuzzle.puzzle(for: 2026_01_01)
        #expect(puzzle.difficulty == .medium)
        #expect(SudokuSolver.countSolutions(puzzle.givens, limit: 2) == 1)
        #expect(SudokuSolver.solve(puzzle.givens) == puzzle.solution)
        #expect(SudokuSolver.isSolvableWithSingles(puzzle.givens))
    }

    @Test func seededRandomIsRepeatable() {
        var first = SeededRandom(seed: 99)
        var second = SeededRandom(seed: 99)
        var other = SeededRandom(seed: 100)
        let a = (0..<5).map { _ in first.next() }
        let b = (0..<5).map { _ in second.next() }
        let c = (0..<5).map { _ in other.next() }
        #expect(a == b)
        #expect(a != c)
    }

    @Test func dayKeysRoundTripAndStepBackAcrossMonthsAndYears() {
        #expect(DayKey.previous(2026_11_14) == 2026_11_13)
        #expect(DayKey.previous(2026_03_01) == 2026_02_28)
        #expect(DayKey.previous(2028_03_01) == 2028_02_29)
        #expect(DayKey.previous(2027_01_01) == 2026_12_31)
        let date = DayKey.date(for: 2026_11_14)
        #expect(date.map(DayKey.key(for:)) == 2026_11_14)
    }

    @Test func streakCountsConsecutiveDays() {
        let days: Set<Int> = [2026_11_10, 2026_11_12, 2026_11_13, 2026_11_14]
        #expect(DailyStreak.current(days: days, today: 2026_11_14) == 3)
        // Not solved yet today: yesterday's streak is still alive.
        #expect(DailyStreak.current(days: days, today: 2026_11_15) == 3)
        // A missed day ends it.
        #expect(DailyStreak.current(days: days, today: 2026_11_16) == 0)
        #expect(DailyStreak.best(days: days) == 3)
        #expect(DailyStreak.best(days: []) == 0)
        #expect(DailyStreak.best(days: [2026_02_28, 2026_03_01, 2026_03_02, 2026_03_03, 2026_11_14]) == 4)
    }
}

@Suite struct HardcoreTests {
    let puzzle = Puzzle(difficulty: .easy, givens: samplePuzzle, solution: sampleSolution)

    @Test func wrongDigitsAreNotRevealed() {
        var game = GameState(puzzle: puzzle, isHardcore: true)
        #expect(game.place(1, at: 2, enforceMistakeLimit: true) == .changed) // wrong: solution is 4
        #expect(game.place(2, at: 2, enforceMistakeLimit: true) == .changed)
        #expect(game.place(9, at: 2, enforceMistakeLimit: true) == .changed)
        #expect(game.status == .playing) // the mistake limit doesn't apply
    }

    @Test func reenteringAnyDigitClearsIt() {
        var game = GameState(puzzle: puzzle, isHardcore: true)
        _ = game.place(4, at: 2, enforceMistakeLimit: false) // correct
        #expect(game.place(4, at: 2, enforceMistakeLimit: false) == .changed)
        #expect(game.values[2] == 0)
    }

    @Test func notesAreNotClearedAutomatically() {
        var game = GameState(puzzle: puzzle, isHardcore: true)
        _ = game.toggleNote(4, at: 3)
        _ = game.place(4, at: 2, enforceMistakeLimit: false)
        #expect(game.hasNote(4, at: 3))
    }

    @Test func verdictComesOnlyWhenTheBoardIsFull() {
        var game = GameState(puzzle: puzzle, isHardcore: true)
        let empty = (0..<81).filter { !game.isGiven($0) }
        let wrongCell = empty[0]
        _ = game.place(sampleSolution[wrongCell] % 9 + 1, at: wrongCell, enforceMistakeLimit: false)
        for index in empty.dropFirst().dropLast() {
            #expect(game.place(sampleSolution[index], at: index, enforceMistakeLimit: false) == .changed)
        }
        let last = empty.last!
        #expect(game.place(sampleSolution[last], at: last, enforceMistakeLimit: false) == .lost)
        #expect(game.status == .lost)
        #expect(game.wrongCellCount == 1)
    }

    @Test func aCorrectFullBoardWins() {
        var game = GameState(puzzle: puzzle, isHardcore: true)
        var outcome = MoveOutcome.ignored
        for index in 0..<81 where !game.isGiven(index) {
            outcome = game.place(sampleSolution[index], at: index, enforceMistakeLimit: false)
        }
        #expect(outcome == .won)
    }

    @Test func restartKeepsTheMode() {
        var game = GameState(puzzle: puzzle, isHardcore: true, dailyDay: 2026_11_14)
        _ = game.place(4, at: 2, enforceMistakeLimit: false)
        game.restart()
        #expect(game.isHardcore)
        #expect(game.dailyDay == 2026_11_14)
        #expect(!game.hasStarted)
    }

    @Test func gamesAreFiledUnderOneCategory() {
        #expect(StatCategory(GameState(puzzle: puzzle)) == .easy)
        #expect(StatCategory(GameState(puzzle: puzzle, isHardcore: true)) == .hardcore)
        #expect(StatCategory(GameState(puzzle: puzzle, dailyDay: 2026_11_14)) == .daily)
    }
}

@Suite struct CompatibilityTests {
    @Test func statisticsSavedByTheFirstVersionStillLoad() throws {
        let old = #"{"entries":{"medium":{"played":5,"won":3,"bestTime":250.5},"easy":{"played":2,"won":2}}}"#
        let stats = try JSONDecoder().decode(Statistics.self, from: Data(old.utf8))
        #expect(stats[.medium].played == 5)
        #expect(stats[.medium].won == 3)
        #expect(stats[.medium].bestTime == 250.5)
        #expect(stats[.easy].played == 2)
        #expect(stats[.easy].bestTime == nil)
        #expect(stats.totalPlayed == 7)
        #expect(stats.history.isEmpty)
        #expect(stats.dailyDays.isEmpty)
    }

    @Test func gamesSavedByTheFirstVersionStillLoad() throws {
        var game = GameState(puzzle: Puzzle(difficulty: .hard, givens: samplePuzzle, solution: sampleSolution))
        _ = game.place(4, at: 2, enforceMistakeLimit: false)
        _ = game.toggleNote(5, at: 5)
        game.elapsed = 99
        // Strip the fields the first version didn't have.
        let data = try JSONEncoder().encode(game)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["isHardcore"] = nil
        object["dailyDay"] = nil
        let oldData = try JSONSerialization.data(withJSONObject: object)
        let loaded = try JSONDecoder().decode(GameState.self, from: oldData)
        #expect(loaded == game)
        #expect(!loaded.isHardcore)
        #expect(!loaded.isDaily)
    }

    @Test func newFieldsSurviveSaveAndLoad() throws {
        var game = GameState(
            puzzle: Puzzle(difficulty: .medium, givens: samplePuzzle, solution: sampleSolution),
            isHardcore: true, dailyDay: 2026_11_14
        )
        _ = game.place(4, at: 2, enforceMistakeLimit: false)
        let loaded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(game))
        #expect(loaded == game)
    }

    @Test func exportAndImportRoundTrip() {
        var stats = Statistics()
        stats.recordStarted(.hardcore)
        stats.recordWin(.hardcore, time: 321)
        stats.addPlayTime(321)
        stats.markDailySolved(2026_11_14)
        stats.markDailySolved(2026_11_14)
        stats.addRecord(GameRecord(
            date: Date(timeIntervalSince1970: 1_800_000_000), difficulty: .hard, time: 321,
            mistakes: 2, hints: 0, isHardcore: true, isDaily: false, won: true
        ))
        let text = stats.exportText()
        #expect(text.contains("\"entries\""))
        #expect(Statistics.importing(text) == stats)
        #expect(stats.dailyDays == [2026_11_14])
    }

    @Test func importRejectsTextThatIsNotABackup() {
        #expect(Statistics.importing("") == nil)
        #expect(Statistics.importing("hello") == nil)
        #expect(Statistics.importing("{}") == nil)
        #expect(Statistics.importing("[1, 2, 3]") == nil)
    }

    @Test func streaksAndHistoryLimit() {
        var stats = Statistics()
        stats.recordWin(.easy, time: 100)
        stats.recordWin(.easy, time: 90)
        stats.recordLoss(.easy)
        stats.recordWin(.easy, time: 80)
        #expect(stats[.easy].currentStreak == 1)
        #expect(stats[.easy].bestStreak == 2)
        stats.recordAbandoned(.easy)
        #expect(stats[.easy].currentStreak == 0)

        for index in 0..<(Statistics.historyLimit + 10) {
            stats.addRecord(GameRecord(
                date: Date(timeIntervalSince1970: Double(index)), difficulty: .easy, time: 60,
                mistakes: 0, hints: 0, isHardcore: false, isDaily: false, won: true
            ))
        }
        #expect(stats.history.count == Statistics.historyLimit)
        #expect(stats.history.first?.date == Date(timeIntervalSince1970: 10))
    }
}

@MainActor
@Suite struct SessionTests {
    func temporaryStore() -> GameStore {
        GameStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    @Test func dailyAndRegularGamesLiveSideBySide() async {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let session = GameSession(store: store)

        await session.newGame(.easy)
        session.select(session.game!.values.firstIndex(of: 0)!)
        session.enter(session.game!.puzzle.solution[session.selected!])
        let regular = session.game

        #expect(await session.openDaily())
        #expect(session.game?.isDaily == true)
        #expect(session.game?.difficulty == .medium)
        #expect(session.regularGame == regular)

        session.resumeRegular()
        #expect(session.game == regular)
        #expect(session.dailyGame != nil)

        // Both games are still there after relaunching the app.
        let relaunched = GameSession(store: store)
        #expect(relaunched.regularGame == regular)
        #expect(relaunched.dailyGame?.puzzle == session.dailyGame?.puzzle)
        #expect(relaunched.statistics[.easy].played == 1)
    }

    @Test func hintIsExplainedFirstAndAppliedOnTheSecondTap() async {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let session = GameSession(store: store)
        await session.newGame(.easy)
        let before = session.game!.values

        session.hint()
        let hint = session.activeHint
        #expect(hint != nil)
        #expect(session.game?.values == before)
        #expect(session.game?.hintsUsed == 1)

        session.hint()
        #expect(session.activeHint == nil)
        #expect(session.game?.values[hint!.cell] == hint!.digit)
        #expect(session.game?.hintsUsed == 1)
    }

    @Test func hardcoreGamesHaveNoHintsAndTheirOwnStatistics() async {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let session = GameSession(store: store)
        await session.newGame(.easy, hardcore: true)
        session.hint()
        #expect(session.activeHint == nil)

        let game = session.game!
        for index in 0..<81 where !game.isGiven(index) {
            session.select(index)
            session.enter(game.puzzle.solution[index])
        }
        #expect(session.game?.status == .won)
        #expect(session.statistics[.hardcore].won == 1)
        #expect(session.statistics[.easy].played == 0)
        #expect(session.statistics.history.last?.isHardcore == true)
        #expect(session.cellPulses.allSatisfy { $0 == 0 })
    }

    @Test func solvingTheDailyPuzzleStartsAStreak() async {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let session = GameSession(store: store)
        #expect(await session.openDaily())
        let game = session.game!
        for index in 0..<81 where !game.isGiven(index) {
            session.select(index)
            session.enter(game.puzzle.solution[index])
        }
        #expect(session.isDailySolved)
        #expect(session.dailyStreak == 1)
        #expect(session.statistics[.daily].won == 1)
        #expect(session.statistics.totalPlayed == 1)
    }

    @Test func aWonGameCannotBeReplayedForASecondWin() async {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let session = GameSession(store: store)
        #expect(await session.openDaily())
        let game = session.game!
        for index in 0..<81 where !game.isGiven(index) {
            session.select(index)
            session.enter(game.puzzle.solution[index])
        }
        #expect(session.game?.status == .won)
        #expect(!session.canRestart)

        session.restart()
        #expect(session.game?.status == .won)
        #expect(session.statistics[.daily].played == 1)
        #expect(session.statistics[.daily].won == 1)
    }

    @Test func aLostGameCanStillBeTriedAgain() async {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let session = GameSession(store: store)
        await session.newGame(.easy, hardcore: true)
        let game = session.game!
        let empty = (0..<81).filter { !game.isGiven($0) }
        for index in empty {
            session.select(index)
            let digit = game.puzzle.solution[index]
            // One wrong digit, so the full board is a loss.
            session.enter(index == empty[0] ? digit % 9 + 1 : digit)
        }
        #expect(session.game?.status == .lost)
        #expect(session.canRestart)

        session.restart()
        #expect(session.game?.status == .playing)
        #expect(session.game?.values == game.puzzle.givens)
    }

    @Test func newGameFromTheDailyPuzzleWarnsOnlyWhenItReplacesAStartedGame() async {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let session = GameSession(store: store)

        // An untouched regular game can be replaced without asking.
        await session.newGame(.easy)
        #expect(await session.openDaily())
        #expect(!session.newGameReplacesParkedGame)

        // Once it has been played, starting a game from the daily puzzle would throw it away.
        session.resumeRegular()
        session.select(session.game!.values.firstIndex(of: 0)!)
        session.enter(session.game!.puzzle.solution[session.selected!])
        #expect(!session.newGameReplacesParkedGame) // it's on the board: replacing it is no surprise
        #expect(await session.openDaily())
        #expect(session.newGameReplacesParkedGame)
    }
}
