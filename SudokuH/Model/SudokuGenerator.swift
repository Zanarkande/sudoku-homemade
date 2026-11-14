import Foundation

nonisolated struct Puzzle: Codable, Equatable, Sendable {
    let difficulty: Difficulty
    /// 81 values, 0 for cells the player must fill.
    let givens: [Int]
    /// The unique solution.
    let solution: [Int]

    var clueCount: Int { givens.count { $0 != 0 } }
}

/// Generates puzzles with exactly one solution.
///
/// A random solved grid is built, then cells are removed one at a time; a removal is kept
/// only if the puzzle still has a single solution (and, for Easy/Medium, is still solvable
/// with singles only).
nonisolated enum SudokuGenerator {
    static func generate(_ difficulty: Difficulty, timeBudget: TimeInterval = 0.5) -> Puzzle {
        var rng = SystemRandomNumberGenerator()
        return generate(difficulty, using: &rng, timeBudget: timeBudget)
    }

    static func generate<R: RandomNumberGenerator>(
        _ difficulty: Difficulty,
        using rng: inout R,
        timeBudget: TimeInterval = 0.5,
        maxAttempts: Int = .max
    ) -> Puzzle {
        let deadline = Date().addingTimeInterval(timeBudget)
        var best: Puzzle?
        var bestScore = Int.max
        var attempts = 0
        repeat {
            attempts += 1
            let solution = randomSolvedGrid(using: &rng)
            let givens = dig(solution, difficulty: difficulty, using: &rng)
            let puzzle = Puzzle(difficulty: difficulty, givens: givens, solution: solution)
            let score = score(puzzle)
            if score < bestScore {
                best = puzzle
                bestScore = score
            }
        } while bestScore > 0 && attempts < maxAttempts && Date() < deadline
        return best!
    }

    /// 0 means the puzzle fully matches its difficulty; lower is better.
    private static func score(_ puzzle: Puzzle) -> Int {
        let difficulty = puzzle.difficulty
        var score = max(0, puzzle.clueCount - difficulty.targetClues)
        if !difficulty.solvableWithSinglesOnly && SudokuSolver.isSolvableWithSingles(puzzle.givens) {
            score += 100
        }
        return score
    }

    static func randomSolvedGrid<R: RandomNumberGenerator>(using rng: inout R) -> [Int] {
        // The three diagonal boxes don't constrain each other, so they can be filled freely.
        var cells = [Int](repeating: 0, count: 81)
        for box in [0, 4, 8] {
            let digits = Array(1...9).shuffled(using: &rng)
            for (offset, index) in BoardGeometry.units[18 + box].enumerated() {
                cells[index] = digits[offset]
            }
        }
        let order = Array(1...9).shuffled(using: &rng)
        return SudokuSolver.solve(cells, digitOrder: order)!
    }

    private static func dig<R: RandomNumberGenerator>(
        _ solution: [Int],
        difficulty: Difficulty,
        using rng: inout R
    ) -> [Int] {
        var cells = solution
        var clues = 81
        let target = difficulty.targetClues

        func isAcceptable(_ candidate: [Int]) -> Bool {
            difficulty.solvableWithSinglesOnly
                ? SudokuSolver.isSolvableWithSingles(candidate)
                : SudokuSolver.hasUniqueSolution(candidate)
        }

        // First pass: remove cells in rotationally symmetric pairs for a balanced look.
        for index in Array(0...40).shuffled(using: &rng) {
            let mirror = 80 - index
            let removed = index == mirror ? 1 : 2
            guard clues - removed >= target else { continue }
            var candidate = cells
            candidate[index] = 0
            candidate[mirror] = 0
            if isAcceptable(candidate) {
                cells = candidate
                clues -= removed
            }
        }
        // Second pass: remove single cells until the target is reached.
        for index in Array(0..<81).shuffled(using: &rng) where cells[index] != 0 {
            guard clues > target else { break }
            var candidate = cells
            candidate[index] = 0
            if isAcceptable(candidate) {
                cells = candidate
                clues -= 1
            }
        }
        return cells
    }
}
