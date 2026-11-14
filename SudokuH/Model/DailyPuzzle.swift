import Foundation

/// A small, fast random number generator that always produces the same
/// sequence for the same seed (SplitMix64).
nonisolated struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The puzzle of the day: the same date always gives the same puzzle.
nonisolated enum DailyPuzzle {
    static let difficulty = Difficulty.medium

    static func puzzle(for day: Int) -> Puzzle {
        var rng = SeededRandom(seed: UInt64(truncatingIfNeeded: day) &* 0x2545_F491_4F6C_DD1D)
        // A fixed number of attempts (instead of a time limit) keeps the result
        // identical no matter how fast the device is.
        return SudokuGenerator.generate(difficulty, using: &rng, timeBudget: 60, maxAttempts: 12)
    }
}
