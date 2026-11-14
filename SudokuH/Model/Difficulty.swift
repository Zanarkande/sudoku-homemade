import Foundation

nonisolated enum Difficulty: String, Codable, CaseIterable, Identifiable, Sendable {
    case easy, medium, hard, expert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        case .expert: "Expert"
        }
    }

    /// Number of given cells the generator aims for.
    var targetClues: Int {
        switch self {
        case .easy: 40
        case .medium: 32
        case .hard: 28
        case .expert: 24
        }
    }

    /// Easy and Medium puzzles can always be solved by finding "singles"
    /// (a cell with one possible digit, or a digit with one possible cell).
    /// Hard and Expert puzzles need more advanced reasoning.
    var solvableWithSinglesOnly: Bool {
        switch self {
        case .easy, .medium: true
        case .hard, .expert: false
        }
    }
}
