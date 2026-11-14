import Foundation
import Testing
@testable import SudokuH

/// Deterministic random numbers so generator tests are repeatable.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func grid(_ text: String) -> [Int] {
    text.compactMap { $0 == "." ? 0 : $0.wholeNumberValue }
}

let samplePuzzle = grid("""
    53..7....\
    6..195...\
    .98....6.\
    8...6...3\
    4..8.3..1\
    7...2...6\
    .6....28.\
    ...419..5\
    ....8..79
    """)

let sampleSolution = grid("""
    534678912\
    672195348\
    198342567\
    859761423\
    426853791\
    713924856\
    961537284\
    287419635\
    345286179
    """)

@Suite struct SolverTests {
    @Test func solvesKnownPuzzle() {
        #expect(samplePuzzle.count == 81)
        #expect(SudokuSolver.solve(samplePuzzle) == sampleSolution)
    }

    @Test func knownPuzzleHasUniqueSolution() {
        #expect(SudokuSolver.countSolutions(samplePuzzle) == 1)
        #expect(SudokuSolver.hasUniqueSolution(samplePuzzle))
    }

    @Test func detectsMultipleSolutions() {
        // Removing every 1 and 2 from a solved grid lets the two digits be swapped.
        let ambiguous = sampleSolution.map { $0 <= 2 ? 0 : $0 }
        #expect(SudokuSolver.countSolutions(ambiguous, limit: 2) == 2)
        #expect(!SudokuSolver.hasUniqueSolution(ambiguous))
    }

    @Test func emptyGridHasManySolutions() {
        let empty = [Int](repeating: 0, count: 81)
        #expect(SudokuSolver.countSolutions(empty, limit: 5) == 5)
        #expect(SudokuSolver.solve(empty).map(SudokuSolver.isValidSolution) == true)
    }

    @Test func rejectsGridWithDuplicateInRow() {
        var invalid = samplePuzzle
        invalid[1] = 5 // second 5 in the first row
        #expect(SudokuSolver.solve(invalid) == nil)
        #expect(SudokuSolver.countSolutions(invalid) == 0)
    }

    @Test func rejectsUnsolvableGrid() {
        // Valid-looking but impossible: the first cell has no candidate left.
        var unsolvable = [Int](repeating: 0, count: 81)
        for column in 1...8 { unsolvable[column] = column } // 1...8 in row 0
        unsolvable[9] = 9                                   // 9 in the same box/column
        #expect(SudokuSolver.solve(unsolvable) == nil)
        #expect(SudokuSolver.countSolutions(unsolvable) == 0)
    }

    @Test func rejectsMalformedInput() {
        #expect(SudokuSolver.solve([1, 2, 3]) == nil)
        var outOfRange = samplePuzzle
        outOfRange[2] = 12
        #expect(SudokuSolver.solve(outOfRange) == nil)
    }

    @Test func validatesSolutions() {
        #expect(SudokuSolver.isValidSolution(sampleSolution))
        #expect(!SudokuSolver.isValidSolution(samplePuzzle))
        var broken = sampleSolution
        broken.swapAt(0, 1)
        #expect(!SudokuSolver.isValidSolution(broken))
    }

    @Test func singlesSolverAgreesWithUniqueness() {
        #expect(SudokuSolver.isSolvableWithSingles(samplePuzzle))
        #expect(!SudokuSolver.isSolvableWithSingles(sampleSolution.map { $0 <= 2 ? 0 : $0 }))
    }
}

@Suite struct GeneratorTests {
    @Test(arguments: Difficulty.allCases)
    func generatedPuzzlesHaveExactlyOneSolution(difficulty: Difficulty) {
        var rng = SeededGenerator(state: 42)
        for _ in 0..<8 {
            let puzzle = SudokuGenerator.generate(difficulty, using: &rng)
            #expect(puzzle.givens.count == 81)
            #expect(SudokuSolver.isValidSolution(puzzle.solution))
            #expect(SudokuSolver.countSolutions(puzzle.givens, limit: 2) == 1)
            #expect(SudokuSolver.solve(puzzle.givens) == puzzle.solution)
            // Every given must match the solution.
            for index in 0..<81 where puzzle.givens[index] != 0 {
                #expect(puzzle.givens[index] == puzzle.solution[index])
            }
        }
    }

    @Test(arguments: Difficulty.allCases)
    func generatedPuzzlesMatchTheirDifficulty(difficulty: Difficulty) {
        var rng = SeededGenerator(state: 7)
        for _ in 0..<5 {
            let puzzle = SudokuGenerator.generate(difficulty, using: &rng)
            #expect(puzzle.difficulty == difficulty)
            #expect(puzzle.clueCount >= difficulty.targetClues)
            #expect(puzzle.clueCount <= difficulty.targetClues + 3)
            #expect(SudokuSolver.isSolvableWithSingles(puzzle.givens) == difficulty.solvableWithSinglesOnly)
        }
    }

    @Test func harderPuzzlesHaveFewerClues() {
        let clues = Difficulty.allCases.map(\.targetClues)
        #expect(clues == clues.sorted(by: >))
    }

    @Test(arguments: Difficulty.allCases)
    func generationIsFast(difficulty: Difficulty) {
        let start = Date()
        _ = SudokuGenerator.generate(difficulty)
        #expect(Date().timeIntervalSince(start) < 1)
    }

    @Test func randomSolvedGridsAreValidAndVaried() {
        var rng = SeededGenerator(state: 1)
        let first = SudokuGenerator.randomSolvedGrid(using: &rng)
        let second = SudokuGenerator.randomSolvedGrid(using: &rng)
        #expect(SudokuSolver.isValidSolution(first))
        #expect(SudokuSolver.isValidSolution(second))
        #expect(first != second)
    }
}

@Suite struct GameStateTests {
    let puzzle = Puzzle(difficulty: .easy, givens: samplePuzzle, solution: sampleSolution)

    /// Index of the first empty cell (row 0, column 2; solution 4).
    let cell = 2

    @Test func correctDigitIsPlaced() {
        var game = GameState(puzzle: puzzle)
        #expect(game.place(4, at: cell, enforceMistakeLimit: true) == .changed)
        #expect(game.values[cell] == 4)
        #expect(!game.isMistake(cell))
        #expect(game.mistakes == 0)
        #expect(game.hasStarted)
    }

    @Test func wrongDigitCountsAsMistake() {
        var game = GameState(puzzle: puzzle)
        #expect(game.place(1, at: cell, enforceMistakeLimit: false) == .mistake)
        #expect(game.isMistake(cell))
        #expect(game.mistakes == 1)
    }

    @Test func givenCellsCannotBeChanged() {
        var game = GameState(puzzle: puzzle)
        #expect(game.place(9, at: 0, enforceMistakeLimit: false) == .ignored)
        #expect(game.erase(at: 0) == .ignored)
        #expect(game.toggleNote(9, at: 0) == .ignored)
        #expect(game.values == samplePuzzle)
    }

    @Test func mistakeLimitEndsTheGameOnlyWhenEnabled() {
        var limited = GameState(puzzle: puzzle)
        var unlimited = GameState(puzzle: puzzle)
        let wrongDigits = [1, 2, 6]
        for (count, digit) in wrongDigits.enumerated() {
            let outcome = limited.place(digit, at: cell, enforceMistakeLimit: true)
            #expect(outcome == (count == 2 ? .lost : .mistake))
            #expect(unlimited.place(digit, at: cell, enforceMistakeLimit: false) == .mistake)
        }
        #expect(limited.status == .lost)
        #expect(unlimited.status == .playing)
        #expect(limited.place(4, at: cell, enforceMistakeLimit: true) == .ignored)
    }

    @Test func placingADigitClearsMatchingNotesInRowColumnAndBox() {
        var game = GameState(puzzle: puzzle)
        let sameRow = 3, sameColumn = 29, sameBox = 10, unrelated = 40
        for index in [sameRow, sameColumn, sameBox, unrelated] {
            #expect(game.toggleNote(4, at: index) == .changed)
            #expect(game.toggleNote(7, at: index) == .changed)
        }
        _ = game.place(4, at: cell, enforceMistakeLimit: false)
        for index in [sameRow, sameColumn, sameBox] {
            #expect(!game.hasNote(4, at: index))
            #expect(game.hasNote(7, at: index))
        }
        #expect(game.hasNote(4, at: unrelated))
    }

    @Test func undoRestoresValuesAndNotes() {
        var game = GameState(puzzle: puzzle)
        _ = game.toggleNote(4, at: 3)
        _ = game.toggleNote(2, at: cell)
        let before = game
        _ = game.place(4, at: cell, enforceMistakeLimit: false)
        #expect(game.undo() == .changed)
        #expect(game.values == before.values)
        #expect(game.notes == before.notes)
        #expect(game.undo() == .changed)
        #expect(game.undo() == .changed)
        #expect(game.undo() == .ignored)
        #expect(game.notes.allSatisfy { $0 == 0 })
    }

    @Test func reenteringADigitClearsOnlyMistakes() {
        var game = GameState(puzzle: puzzle)
        _ = game.place(4, at: cell, enforceMistakeLimit: false)
        #expect(game.place(4, at: cell, enforceMistakeLimit: false) == .ignored)
        #expect(game.values[cell] == 4)
        _ = game.place(1, at: 3, enforceMistakeLimit: false)
        #expect(game.place(1, at: 3, enforceMistakeLimit: false) == .changed)
        #expect(game.values[3] == 0)
        #expect(game.mistakes == 1)
    }

    @Test func eraseClearsValueAndNotes() {
        var game = GameState(puzzle: puzzle)
        _ = game.place(1, at: cell, enforceMistakeLimit: false)
        #expect(game.erase(at: cell) == .changed)
        #expect(game.values[cell] == 0)
        #expect(game.erase(at: cell) == .ignored)
    }

    @Test func hintRevealsACorrectCell() {
        var game = GameState(puzzle: puzzle)
        let result = game.hint(preferring: cell)
        #expect(result.index == cell)
        #expect(game.values[cell] == sampleSolution[cell])
        #expect(game.hintsUsed == 1)

        let other = game.hint(preferring: 0) // a given: falls back to another cell
        #expect(other.index != nil && other.index != 0)
        #expect(game.values[other.index!] == sampleSolution[other.index!])
    }

    @Test func fillingTheBoardWinsTheGame() {
        var game = GameState(puzzle: puzzle)
        let empty = (0..<81).filter { samplePuzzle[$0] == 0 }
        for index in empty.dropLast() {
            #expect(game.place(sampleSolution[index], at: index, enforceMistakeLimit: true) == .changed)
        }
        #expect(game.place(sampleSolution[empty.last!], at: empty.last!, enforceMistakeLimit: true) == .won)
        #expect(game.status == .won)
        #expect((1...9).allSatisfy(game.isDigitComplete))
    }

    @Test func completedUnitsTracksCorrectlyFilledRowsColumnsAndBoxes() {
        var game = GameState(puzzle: puzzle)
        #expect(game.completedUnits.isEmpty)

        // Fill row 0, leaving its last cell wrong.
        let empty = (0..<9).filter { !game.isGiven($0) }
        for index in empty.dropLast() {
            _ = game.place(sampleSolution[index], at: index, enforceMistakeLimit: false)
        }
        let last = empty.last!
        _ = game.place(sampleSolution[last] % 9 + 1, at: last, enforceMistakeLimit: false)
        #expect(game.completedUnits.isEmpty)

        _ = game.place(sampleSolution[last], at: last, enforceMistakeLimit: false)
        #expect(game.completedUnits == [0])
    }

    @Test func remainingCountsOnlyCorrectDigits() {
        var game = GameState(puzzle: puzzle)
        let before = game.remaining(4)
        _ = game.place(4, at: cell, enforceMistakeLimit: false)
        #expect(game.remaining(4) == before - 1)
        let ones = game.remaining(1)
        _ = game.place(1, at: 3, enforceMistakeLimit: false) // wrong: solution is 6
        #expect(game.remaining(1) == ones)
    }
}

@Suite struct PersistenceTests {
    func temporaryStore() -> GameStore {
        GameStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    @Test func gameSurvivesSaveAndLoad() {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(store.loadGame() == nil)

        var game = GameState(puzzle: Puzzle(difficulty: .hard, givens: samplePuzzle, solution: sampleSolution))
        _ = game.place(4, at: 2, enforceMistakeLimit: false)
        _ = game.place(1, at: 3, enforceMistakeLimit: false)
        _ = game.toggleNote(5, at: 5)
        game.elapsed = 123.5
        store.save(game)

        #expect(store.loadGame() == game)
        store.save(nil as GameState?)
        #expect(store.loadGame() == nil)
    }

    @Test func statisticsTrackPlayedWonAndBestTime() {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }

        var stats = store.loadStatistics()
        stats.recordStarted(.medium)
        stats.recordStarted(.medium)
        let first = stats.recordWin(.medium, time: 300)
        let slower = stats.recordWin(.medium, time: 400)
        let faster = stats.recordWin(.medium, time: 250)
        #expect(first)
        #expect(!slower)
        #expect(faster)
        store.save(stats)

        let loaded = store.loadStatistics()
        #expect(loaded[.medium] == DifficultyStats(
            played: 2, won: 3, bestTime: 250, totalWinTime: 950, timedWins: 3, currentStreak: 3, bestStreak: 3
        ))
        #expect(loaded[.medium].averageTime == 950.0 / 3)
        #expect(loaded[.expert] == DifficultyStats())
    }
}
