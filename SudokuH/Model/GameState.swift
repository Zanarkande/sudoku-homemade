import Foundation

nonisolated enum MoveOutcome: Equatable, Sendable {
    /// Nothing happened (given cell, game over, nothing to undo…).
    case ignored
    /// The board changed and the game goes on.
    case changed
    /// A wrong digit was placed.
    case mistake
    case won
    case lost
}

/// The full state of a game in progress. Pure value type: all rules live here.
nonisolated struct GameState: Codable, Equatable, Sendable {
    nonisolated enum Status: String, Codable, Sendable {
        case playing, won, lost
    }

    nonisolated struct CellChange: Codable, Equatable, Sendable {
        let index: Int
        let oldValue: Int
        let oldNotes: UInt16
    }

    static let mistakeLimit = 3

    let puzzle: Puzzle
    private(set) var values: [Int]
    /// Pencil marks: bit (d - 1) set means digit d is noted in the cell.
    private(set) var notes: [UInt16]
    private(set) var mistakes = 0
    private(set) var hintsUsed = 0
    private(set) var status = Status.playing
    private(set) var hasStarted = false
    private(set) var undoStack: [[CellChange]] = []
    var elapsed: TimeInterval = 0
    /// Hardcore games give no visual help and only reveal mistakes once the board is full.
    private(set) var isHardcore = false
    /// Set for daily puzzles: the day (see `DayKey`) the puzzle belongs to.
    private(set) var dailyDay: Int?

    init(puzzle: Puzzle, isHardcore: Bool = false, dailyDay: Int? = nil) {
        self.puzzle = puzzle
        self.isHardcore = isHardcore
        self.dailyDay = dailyDay
        values = puzzle.givens
        notes = [UInt16](repeating: 0, count: BoardGeometry.cellCount)
    }

    /// Reads a saved game. Fields added in later versions are optional so that
    /// games saved by older versions of the app keep loading.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        puzzle = try container.decode(Puzzle.self, forKey: .puzzle)
        values = try container.decode([Int].self, forKey: .values)
        notes = try container.decode([UInt16].self, forKey: .notes)
        mistakes = try container.decodeIfPresent(Int.self, forKey: .mistakes) ?? 0
        hintsUsed = try container.decodeIfPresent(Int.self, forKey: .hintsUsed) ?? 0
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .playing
        hasStarted = try container.decodeIfPresent(Bool.self, forKey: .hasStarted) ?? false
        undoStack = try container.decodeIfPresent([[CellChange]].self, forKey: .undoStack) ?? []
        elapsed = try container.decodeIfPresent(TimeInterval.self, forKey: .elapsed) ?? 0
        isHardcore = try container.decodeIfPresent(Bool.self, forKey: .isHardcore) ?? false
        dailyDay = try container.decodeIfPresent(Int.self, forKey: .dailyDay)
        let count = BoardGeometry.cellCount
        guard values.count == count, notes.count == count,
              puzzle.givens.count == count, puzzle.solution.count == count else {
            throw DecodingError.dataCorruptedError(
                forKey: .values, in: container, debugDescription: "A saved board must have 81 cells."
            )
        }
    }

    var difficulty: Difficulty { puzzle.difficulty }
    var isDaily: Bool { dailyDay != nil }

    /// How many filled cells currently hold a wrong digit.
    var wrongCellCount: Int { (0..<BoardGeometry.cellCount).count { isMistake($0) } }

    /// Share of the cells the player has to fill that are filled so far (0...1).
    var progress: Double {
        let toFill = puzzle.givens.count { $0 == 0 }
        guard toFill > 0 else { return 1 }
        let filled = (0..<BoardGeometry.cellCount).count { puzzle.givens[$0] == 0 && values[$0] != 0 }
        return Double(filled) / Double(toFill)
    }
    var canUndo: Bool { status == .playing && !undoStack.isEmpty }

    func isGiven(_ index: Int) -> Bool { puzzle.givens[index] != 0 }

    func isMistake(_ index: Int) -> Bool {
        values[index] != 0 && values[index] != puzzle.solution[index]
    }

    func hasNote(_ digit: Int, at index: Int) -> Bool {
        notes[index] & Self.bit(digit) != 0
    }

    /// How many more cells still need this digit.
    func remaining(_ digit: Int) -> Int {
        9 - (0..<81).count { values[$0] == digit && puzzle.solution[$0] == digit }
    }

    func isDigitComplete(_ digit: Int) -> Bool { remaining(digit) == 0 }

    /// Indices into `BoardGeometry.units` of the rows, columns and boxes that are correctly filled.
    var completedUnits: Set<Int> {
        Set(BoardGeometry.units.indices.filter { unit in
            BoardGeometry.units[unit].allSatisfy { values[$0] == puzzle.solution[$0] }
        })
    }

    // MARK: - Moves

    /// Places a digit. Re-entering a wrong digit clears it; re-entering a correct one does nothing.
    /// In hardcore mode nothing reveals whether a digit is right: re-entering any digit clears it,
    /// notes are never tidied up automatically, and the verdict only comes once the board is full.
    mutating func place(_ digit: Int, at index: Int, enforceMistakeLimit: Bool) -> MoveOutcome {
        guard (1...9).contains(digit), isEditable(index) else { return .ignored }
        if values[index] == digit {
            return isHardcore || isMistake(index) ? erase(at: index) : .ignored
        }

        var changes = [change(at: index)]
        values[index] = digit
        notes[index] = 0
        let isCorrect = digit == puzzle.solution[index]
        if isCorrect && !isHardcore { clearPeerNotes(of: digit, around: index, recordingIn: &changes) }
        undoStack.append(changes)
        hasStarted = true

        if isHardcore {
            if !isCorrect { mistakes += 1 }
            guard !values.contains(0) else { return .changed }
            status = values == puzzle.solution ? .won : .lost
            return status == .won ? .won : .lost
        }
        guard isCorrect else {
            mistakes += 1
            if enforceMistakeLimit && mistakes >= Self.mistakeLimit {
                status = .lost
                return .lost
            }
            return .mistake
        }
        return finishIfSolved()
    }

    mutating func toggleNote(_ digit: Int, at index: Int) -> MoveOutcome {
        guard (1...9).contains(digit), isEditable(index), values[index] == 0 else { return .ignored }
        undoStack.append([change(at: index)])
        notes[index] ^= Self.bit(digit)
        hasStarted = true
        return .changed
    }

    mutating func erase(at index: Int) -> MoveOutcome {
        guard isEditable(index), values[index] != 0 || notes[index] != 0 else { return .ignored }
        undoStack.append([change(at: index)])
        values[index] = 0
        notes[index] = 0
        hasStarted = true
        return .changed
    }

    /// Reveals one correct cell: the preferred one if it still needs solving, otherwise a random one.
    /// Returns the revealed cell so the UI can select it.
    /// `countsAsHint` is false when the hint was already counted by `registerHint()`.
    mutating func hint(preferring preferred: Int?, countsAsHint: Bool = true) -> (outcome: MoveOutcome, index: Int?) {
        guard status == .playing else { return (.ignored, nil) }
        let unsolved = (0..<81).filter { values[$0] != puzzle.solution[$0] }
        let target: Int
        if let preferred, unsolved.contains(preferred) {
            target = preferred
        } else if let random = unsolved.randomElement() {
            target = random
        } else {
            return (.ignored, nil)
        }
        let digit = puzzle.solution[target]
        var changes = [change(at: target)]
        values[target] = digit
        notes[target] = 0
        clearPeerNotes(of: digit, around: target, recordingIn: &changes)
        undoStack.append(changes)
        if countsAsHint { hintsUsed += 1 }
        hasStarted = true
        return (finishIfSolved(), target)
    }

    /// Counts a hint whose explanation was shown to the player.
    mutating func registerHint() {
        guard status == .playing else { return }
        hintsUsed += 1
        hasStarted = true
    }

    mutating func undo() -> MoveOutcome {
        guard status == .playing, let changes = undoStack.popLast() else { return .ignored }
        for change in changes {
            values[change.index] = change.oldValue
            notes[change.index] = change.oldNotes
        }
        return .changed
    }

    /// Starts the same puzzle over from scratch.
    mutating func restart() {
        self = GameState(puzzle: puzzle, isHardcore: isHardcore, dailyDay: dailyDay)
    }

    // MARK: - Helpers

    private static func bit(_ digit: Int) -> UInt16 { UInt16(1) << UInt16(digit - 1) }

    private func isEditable(_ index: Int) -> Bool {
        status == .playing && (0..<BoardGeometry.cellCount).contains(index) && !isGiven(index)
    }

    private func change(at index: Int) -> CellChange {
        CellChange(index: index, oldValue: values[index], oldNotes: notes[index])
    }

    private mutating func clearPeerNotes(of digit: Int, around index: Int, recordingIn changes: inout [CellChange]) {
        let bit = Self.bit(digit)
        for peer in BoardGeometry.peers[index] where notes[peer] & bit != 0 {
            changes.append(change(at: peer))
            notes[peer] &= ~bit
        }
    }

    private mutating func finishIfSolved() -> MoveOutcome {
        guard values == puzzle.solution else { return .changed }
        status = .won
        return .won
    }
}
