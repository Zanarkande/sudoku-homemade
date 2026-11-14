import Foundation

/// A hint: which technique applies, which cells to look at, and why.
nonisolated struct Hint: Equatable, Sendable {
    nonisolated enum Technique: String, CaseIterable, Sendable {
        case mistake, lastCell, nakedSingle, hiddenSingle
        case pointingPair, boxLine, nakedPair, hiddenPair, nakedTriple, hiddenTriple, xWing, xyWing
        case trial, reveal

        var title: String {
            switch self {
            case .mistake: "Something's Off"
            case .lastCell: "Last Empty Cell"
            case .nakedSingle: "Naked Single"
            case .hiddenSingle: "Hidden Single"
            case .pointingPair: "Pointing Pair"
            case .boxLine: "Box-Line Reduction"
            case .nakedPair: "Naked Pair"
            case .hiddenPair: "Hidden Pair"
            case .nakedTriple: "Naked Triple"
            case .hiddenTriple: "Hidden Triple"
            case .xWing: "X-Wing"
            case .xyWing: "XY-Wing"
            case .trial: "Trial and Error"
            case .reveal: "Tricky Spot"
            }
        }
    }

    nonisolated enum Action: Sendable {
        /// Applying the hint writes `digit` into `cell`.
        case place
        /// Applying the hint clears the wrong digit in `cell`.
        case erase
    }

    let technique: Technique
    let action: Action
    /// The cell the hint is about (outlined on the board).
    let cell: Int
    let digit: Int
    /// The cells forming the pattern, e.g. the two cells of a pair.
    let patternCells: [Int]
    /// The row, column or box to look at.
    let regionCells: [Int]
    let explanation: String
}

/// Finds the easiest solving technique that applies to a board and explains it.
///
/// Candidates are worked out from the digits on the board (not from the player's notes).
/// Techniques are tried from easiest to hardest. Those that only rule candidates out
/// (pairs, pointing pairs…) are used when they unlock a cell that can then be filled.
nonisolated enum HintEngine {
    nonisolated struct Single: Equatable, Sendable {
        nonisolated enum Kind: Equatable, Sendable {
            case lastCell(unit: Int)
            case naked
            case hidden(unit: Int)
        }

        let cell: Int
        let digit: Int
        let kind: Kind
    }

    /// A technique that rules candidates out without placing a digit.
    nonisolated struct Elimination: Equatable, Sendable {
        let technique: Hint.Technique
        let patternCells: [Int]
        let regionCells: [Int]
        /// For each affected cell, the candidate bits to remove.
        let removals: [Int: UInt16]
        let reason: String
    }

    // MARK: - Public entry point

    static func hint(values: [Int], solution: [Int], preferred: Int? = nil) -> Hint? {
        let count = BoardGeometry.cellCount
        guard values.count == count, solution.count == count else { return nil }

        // A wrong digit on the board makes every other deduction unreliable: point it out first.
        let wrong = (0..<count).filter { values[$0] != 0 && values[$0] != solution[$0] }
        if let cell = wrong.first(where: { $0 == preferred }) ?? wrong.first {
            return Hint(
                technique: .mistake, action: .erase, cell: cell, digit: values[cell],
                patternCells: [], regionCells: [],
                explanation: "The outlined \(values[cell]) doesn't belong in this cell."
            )
        }
        guard values.contains(0) else { return nil }

        var grid = candidates(for: values)
        if let single = findSingle(in: grid, preferred: preferred), solution[single.cell] == single.digit {
            return hint(for: single)
        }

        // No single: look for a technique whose eliminations unlock one. If none does
        // directly, keep the eliminations and look again (the hint is then a multi-step one).
        var chained = false
        for _ in 0..<40 {
            let found = eliminations(in: grid)
            guard !found.isEmpty else { break }
            for elimination in found {
                let next = applying(elimination, to: grid)
                if let single = findSingle(in: next), solution[single.cell] == single.digit {
                    return hint(for: elimination, unlocking: single, chained: chained)
                }
            }
            for elimination in found { grid = applying(elimination, to: grid) }
            chained = true
        }

        let empty = (0..<count).filter { values[$0] == 0 }

        // Still stuck: find a cell where every digit but one quickly runs into a dead end.
        for cell in empty.sorted(by: { grid[$0].nonzeroBitCount < grid[$1].nonzeroBitCount }) {
            let options = digits(in: grid[cell])
            let wrong = options.filter { $0 != solution[cell] }
            guard options.count > 1, options.count <= 3, wrong.count == options.count - 1 else { continue }
            let deadEnds = wrong.compactMap { deadEnd(assuming: $0, at: cell, values: values, candidates: grid) }
            guard deadEnds.count == wrong.count else { continue }
            let explanation = wrong.count == 1
                ? "The outlined cell can only be \(digitList(grid[cell])). If it were \(wrong[0]), the obvious moves "
                    + "that follow lead to a dead end: \(deadEnds[0]). So it has to be \(solution[cell])."
                : "The outlined cell can only be \(digitList(grid[cell])). Trying \(wrong[0]) or \(wrong[1]) leads to a "
                    + "dead end after a few obvious moves, so it has to be \(solution[cell])."
            return Hint(
                technique: .trial, action: .place, cell: cell, digit: solution[cell],
                patternCells: [], regionCells: [], explanation: explanation
            )
        }

        // Nothing simple applies: offer to reveal a cell.
        let fallback = empty.min { grid[$0].nonzeroBitCount < grid[$1].nonzeroBitCount }
        guard let cell = empty.first(where: { $0 == preferred }) ?? fallback else { return nil }
        return Hint(
            technique: .reveal, action: .place, cell: cell, digit: solution[cell],
            patternCells: [], regionCells: [],
            explanation: "No simple technique cracks this one, so here's a cell for free."
        )
    }

    // MARK: - Candidates

    static func bit(_ digit: Int) -> UInt16 { UInt16(1) << UInt16(digit - 1) }

    static func digits(in mask: UInt16) -> [Int] {
        (1...9).filter { mask & bit($0) != 0 }
    }

    /// For every empty cell, the digits not already used in its row, column or box.
    /// Filled cells get an empty mask.
    static func candidates(for values: [Int]) -> [UInt16] {
        var result = [UInt16](repeating: 0, count: BoardGeometry.cellCount)
        for index in 0..<BoardGeometry.cellCount where values[index] == 0 {
            var used: UInt16 = 0
            for peer in BoardGeometry.peers[index] where values[peer] != 0 {
                used |= bit(values[peer])
            }
            result[index] = ~used & 0x1FF
        }
        return result
    }

    static func applying(_ elimination: Elimination, to candidates: [UInt16]) -> [UInt16] {
        var result = candidates
        for (cell, mask) in elimination.removals { result[cell] &= ~mask }
        return result
    }

    /// Tries `digit` in `cell` and follows the singles that result. If that breaks the puzzle
    /// (a cell with no digit left, or a digit with no place left in a unit), says how; otherwise nil.
    static func deadEnd(assuming digit: Int, at cell: Int, values: [Int], candidates: [UInt16]) -> String? {
        var values = values
        var grid = candidates
        var problem: String?

        func place(_ digit: Int, at cell: Int) {
            values[cell] = digit
            grid[cell] = 0
            for peer in BoardGeometry.peers[cell] where values[peer] == 0 {
                grid[peer] &= ~bit(digit)
                if grid[peer] == 0, problem == nil {
                    problem = "the cell in \(cellName(peer)) would have no digit left"
                }
            }
        }

        place(digit, at: cell)
        var progress = true
        while progress, problem == nil {
            progress = false
            for index in values.indices where values[index] == 0 && grid[index].nonzeroBitCount == 1 {
                place(grid[index].trailingZeroBitCount + 1, at: index)
                progress = true
                if problem != nil { return problem }
            }
            for unit in BoardGeometry.units.indices {
                let cells = BoardGeometry.units[unit]
                for candidate in 1...9 where !cells.contains(where: { values[$0] == candidate }) {
                    let places = cells.filter { values[$0] == 0 && grid[$0] & bit(candidate) != 0 }
                    if places.isEmpty {
                        return "\(unitName(unit)) would have no place left for \(candidate)"
                    }
                    if places.count == 1 {
                        place(candidate, at: places[0])
                        progress = true
                        if problem != nil { return problem }
                    }
                }
            }
        }
        return problem
    }

    // MARK: - Singles

    /// The easiest single on the board: a unit's last empty cell, then a cell with
    /// one candidate, then a digit with one possible cell in a box, row or column.
    /// A single in the `preferred` cell wins over all others.
    static func findSingle(in candidates: [UInt16], preferred: Int? = nil) -> Single? {
        if let preferred, candidates.indices.contains(preferred), candidates[preferred] != 0 {
            let all = lastCells(in: candidates) + nakedSingles(in: candidates) + hiddenSingles(in: candidates)
            if let match = all.first(where: { $0.cell == preferred }) { return match }
        }
        return lastCells(in: candidates).first
            ?? nakedSingles(in: candidates).first
            ?? hiddenSingles(in: candidates).first
    }

    static func lastCells(in candidates: [UInt16]) -> [Single] {
        BoardGeometry.units.indices.compactMap { unit in
            let empty = BoardGeometry.units[unit].filter { candidates[$0] != 0 }
            guard empty.count == 1, candidates[empty[0]].nonzeroBitCount == 1 else { return nil }
            return Single(cell: empty[0], digit: candidates[empty[0]].trailingZeroBitCount + 1, kind: .lastCell(unit: unit))
        }
    }

    static func nakedSingles(in candidates: [UInt16]) -> [Single] {
        candidates.indices.compactMap { cell in
            guard candidates[cell].nonzeroBitCount == 1 else { return nil }
            return Single(cell: cell, digit: candidates[cell].trailingZeroBitCount + 1, kind: .naked)
        }
    }

    static func hiddenSingles(in candidates: [UInt16]) -> [Single] {
        // Boxes first: a hidden single is easiest to see inside a box.
        var result: [Single] = []
        for unit in Array(18..<27) + Array(0..<18) {
            for digit in 1...9 {
                let places = BoardGeometry.units[unit].filter { candidates[$0] & bit(digit) != 0 }
                if places.count == 1 {
                    result.append(Single(cell: places[0], digit: digit, kind: .hidden(unit: unit)))
                }
            }
        }
        return result
    }

    // MARK: - Eliminations

    /// Every elimination technique that currently removes at least one candidate, easiest first.
    static func eliminations(in candidates: [UInt16]) -> [Elimination] {
        pointingPairs(in: candidates)
            + boxLineReductions(in: candidates)
            + nakedPairs(in: candidates)
            + hiddenPairs(in: candidates)
            + nakedTriples(in: candidates)
            + hiddenTriples(in: candidates)
            + xWings(in: candidates)
            + xyWings(in: candidates)
    }

    /// Inside a box, a digit that only fits in one row or column can't be elsewhere in that line.
    static func pointingPairs(in candidates: [UInt16]) -> [Elimination] {
        var result: [Elimination] = []
        for box in 0..<9 {
            let boxCells = BoardGeometry.units[18 + box]
            for digit in 1...9 {
                let mask = bit(digit)
                let cells = boxCells.filter { candidates[$0] & mask != 0 }
                guard (2...3).contains(cells.count) else { continue }
                let rows = Set(cells.map(BoardGeometry.row(of:)))
                let columns = Set(cells.map(BoardGeometry.column(of:)))
                let line: Int
                if rows.count == 1, let row = rows.first {
                    line = row
                } else if columns.count == 1, let column = columns.first {
                    line = 9 + column
                } else {
                    continue
                }
                let targets = BoardGeometry.units[line].filter { !boxCells.contains($0) && candidates[$0] & mask != 0 }
                guard !targets.isEmpty else { continue }
                let name = unitName(line)
                result.append(Elimination(
                    technique: .pointingPair,
                    patternCells: cells,
                    regionCells: merged(boxCells, BoardGeometry.units[line]),
                    removals: Dictionary(uniqueKeysWithValues: targets.map { ($0, mask) }),
                    reason: "In \(unitName(18 + box)), \(digit) can only go in \(name) (the highlighted cells), "
                        + "so \(digit) can't go anywhere else in \(name)."
                ))
            }
        }
        return result
    }

    /// In a row or column, a digit that only fits inside one box can't be elsewhere in that box.
    static func boxLineReductions(in candidates: [UInt16]) -> [Elimination] {
        var result: [Elimination] = []
        for line in 0..<18 {
            let lineCells = BoardGeometry.units[line]
            for digit in 1...9 {
                let mask = bit(digit)
                let cells = lineCells.filter { candidates[$0] & mask != 0 }
                guard (2...3).contains(cells.count) else { continue }
                let boxes = Set(cells.map(BoardGeometry.box(of:)))
                guard boxes.count == 1, let box = boxes.first else { continue }
                let boxCells = BoardGeometry.units[18 + box]
                let targets = boxCells.filter { !lineCells.contains($0) && candidates[$0] & mask != 0 }
                guard !targets.isEmpty else { continue }
                result.append(Elimination(
                    technique: .boxLine,
                    patternCells: cells,
                    regionCells: merged(lineCells, boxCells),
                    removals: Dictionary(uniqueKeysWithValues: targets.map { ($0, mask) }),
                    reason: "In \(unitName(line)), \(digit) can only go inside \(unitName(18 + box)) (the highlighted cells), "
                        + "so \(digit) can't go anywhere else in that box."
                ))
            }
        }
        return result
    }

    /// Two cells of a unit that can only hold the same two digits use those digits up.
    static func nakedPairs(in candidates: [UInt16]) -> [Elimination] {
        var result: [Elimination] = []
        for unit in BoardGeometry.units.indices {
            let unitCells = BoardGeometry.units[unit]
            let pairs = unitCells.filter { candidates[$0].nonzeroBitCount == 2 }
            for (offset, first) in pairs.enumerated() {
                for second in pairs.dropFirst(offset + 1) where candidates[second] == candidates[first] {
                    let mask = candidates[first]
                    if let elimination = nakedSet([first, second], mask: mask, unit: unit, technique: .nakedPair, in: candidates) {
                        result.append(elimination)
                    }
                }
            }
        }
        return result
    }

    /// Three cells of a unit that share only three digits between them use those digits up.
    static func nakedTriples(in candidates: [UInt16]) -> [Elimination] {
        var result: [Elimination] = []
        for unit in BoardGeometry.units.indices {
            let cells = BoardGeometry.units[unit].filter { (2...3).contains(candidates[$0].nonzeroBitCount) }
            guard cells.count >= 3 else { continue }
            for i in 0..<(cells.count - 2) {
                for j in (i + 1)..<(cells.count - 1) {
                    for k in (j + 1)..<cells.count {
                        let mask = candidates[cells[i]] | candidates[cells[j]] | candidates[cells[k]]
                        guard mask.nonzeroBitCount == 3 else { continue }
                        if let elimination = nakedSet(
                            [cells[i], cells[j], cells[k]], mask: mask, unit: unit, technique: .nakedTriple, in: candidates
                        ) {
                            result.append(elimination)
                        }
                    }
                }
            }
        }
        return result
    }

    private static func nakedSet(
        _ cells: [Int], mask: UInt16, unit: Int, technique: Hint.Technique, in candidates: [UInt16]
    ) -> Elimination? {
        let unitCells = BoardGeometry.units[unit]
        var removals: [Int: UInt16] = [:]
        for cell in unitCells where !cells.contains(cell) && candidates[cell] & mask != 0 {
            removals[cell] = candidates[cell] & mask
        }
        guard !removals.isEmpty else { return nil }
        let name = unitName(unit)
        let list = digitList(mask)
        let reason = cells.count == 2
            ? "The two highlighted cells in \(name) can only be \(list). Whichever way round they go, "
                + "no other cell in \(name) can be \(list)."
            : "The three highlighted cells in \(name) can only hold \(list) between them, "
                + "so no other cell in \(name) can use those digits."
        return Elimination(technique: technique, patternCells: cells, regionCells: unitCells, removals: removals, reason: reason)
    }

    /// Two digits that only fit in the same two cells of a unit claim those cells.
    static func hiddenPairs(in candidates: [UInt16]) -> [Elimination] {
        var result: [Elimination] = []
        for unit in BoardGeometry.units.indices {
            let unitCells = BoardGeometry.units[unit]
            let places = (1...9).map { digit in unitCells.filter { candidates[$0] & bit(digit) != 0 } }
            for first in 1...8 where places[first - 1].count == 2 {
                for second in (first + 1)...9 where places[second - 1] == places[first - 1] {
                    let keep = bit(first) | bit(second)
                    var removals: [Int: UInt16] = [:]
                    for cell in places[first - 1] where candidates[cell] & ~keep != 0 {
                        removals[cell] = candidates[cell] & ~keep
                    }
                    guard !removals.isEmpty else { continue }
                    result.append(Elimination(
                        technique: .hiddenPair,
                        patternCells: places[first - 1],
                        regionCells: unitCells,
                        removals: removals,
                        reason: "In \(unitName(unit)), \(first) and \(second) can only go in the two highlighted cells, "
                            + "so those cells can't hold anything else."
                    ))
                }
            }
        }
        return result
    }

    /// Three digits that only fit in the same three cells of a unit claim those cells.
    static func hiddenTriples(in candidates: [UInt16]) -> [Elimination] {
        var result: [Elimination] = []
        for unit in BoardGeometry.units.indices {
            let unitCells = BoardGeometry.units[unit]
            let places = (1...9).map { digit in unitCells.filter { candidates[$0] & bit(digit) != 0 } }
            let usable = (1...9).filter { (2...3).contains(places[$0 - 1].count) }
            guard usable.count >= 3 else { continue }
            for i in 0..<(usable.count - 2) {
                for j in (i + 1)..<(usable.count - 1) {
                    for k in (j + 1)..<usable.count {
                        let digits = [usable[i], usable[j], usable[k]]
                        let cells = unitCells.filter { cell in digits.contains { places[$0 - 1].contains(cell) } }
                        guard cells.count == 3 else { continue }
                        let keep = bit(digits[0]) | bit(digits[1]) | bit(digits[2])
                        var removals: [Int: UInt16] = [:]
                        for cell in cells where candidates[cell] & ~keep != 0 {
                            removals[cell] = candidates[cell] & ~keep
                        }
                        guard !removals.isEmpty else { continue }
                        result.append(Elimination(
                            technique: .hiddenTriple,
                            patternCells: cells,
                            regionCells: unitCells,
                            removals: removals,
                            reason: "In \(unitName(unit)), \(digits[0]), \(digits[1]) and \(digits[2]) can only go in the three "
                                + "highlighted cells, so those cells can't hold anything else."
                        ))
                    }
                }
            }
        }
        return result
    }

    /// A digit that fits in only the same two columns of two rows (or the same two rows of
    /// two columns) forms a rectangle; the digit can't be elsewhere in the crossing lines.
    static func xWings(in candidates: [UInt16]) -> [Elimination] {
        var result: [Elimination] = []
        // Lines 0..<9 are rows and 9..<18 are columns; `crossing` gives the other kind.
        for (lines, crossing, crossIndex) in [
            (Array(0..<9), 9, BoardGeometry.column(of:)),
            (Array(9..<18), 0, BoardGeometry.row(of:)),
        ] as [([Int], Int, (Int) -> Int)] {
            for digit in 1...9 {
                let mask = bit(digit)
                let places = lines.map { line in BoardGeometry.units[line].filter { candidates[$0] & mask != 0 } }
                for first in 0..<8 where places[first].count == 2 {
                    for second in (first + 1)..<9 where places[second].count == 2 {
                        let crossings = places[first].map(crossIndex)
                        guard places[second].map(crossIndex) == crossings else { continue }
                        let corners = places[first] + places[second]
                        let crossCells = crossings.flatMap { BoardGeometry.units[crossing + $0] }
                        let targets = crossCells.filter { !corners.contains($0) && candidates[$0] & mask != 0 }
                        guard !targets.isEmpty else { continue }
                        let lineNames = "\(unitName(lines[first])) and \(unitName(lines[second]))"
                        let crossNames = "\(unitName(crossing + crossings[0])) and \(unitName(crossing + crossings[1]))"
                        result.append(Elimination(
                            technique: .xWing,
                            patternCells: corners,
                            regionCells: merged(crossCells, BoardGeometry.units[lines[first]] + BoardGeometry.units[lines[second]]),
                            removals: Dictionary(uniqueKeysWithValues: targets.map { ($0, mask) }),
                            reason: "In \(lineNames), \(digit) can only go in the highlighted cells, which line up. "
                                + "Between them they take the \(digit) of both \(crossNames), "
                                + "so \(digit) can't go anywhere else in \(crossNames)."
                        ))
                    }
                }
            }
        }
        return result
    }

    /// A cell with two candidates (x, y) that sees a cell with (x, z) and a cell with (y, z):
    /// whichever digit it takes, one of the other two becomes z.
    static func xyWings(in candidates: [UInt16]) -> [Elimination] {
        var result: [Elimination] = []
        let pairs = candidates.indices.filter { candidates[$0].nonzeroBitCount == 2 }
        for pivot in pairs {
            let wings = pairs.filter {
                BoardGeometry.arePeers($0, pivot) && $0 != pivot
                    && (candidates[$0] & candidates[pivot]).nonzeroBitCount == 1
            }
            for (offset, first) in wings.enumerated() {
                for second in wings.dropFirst(offset + 1) {
                    let shared = candidates[first] & candidates[second] & ~candidates[pivot]
                    guard shared.nonzeroBitCount == 1,
                          (candidates[first] | candidates[second]) & candidates[pivot] == candidates[pivot] else { continue }
                    let targets = candidates.indices.filter {
                        $0 != first && $0 != second && $0 != pivot && candidates[$0] & shared != 0
                            && BoardGeometry.arePeers($0, first) && BoardGeometry.arePeers($0, second)
                    }
                    guard !targets.isEmpty else { continue }
                    let digit = shared.trailingZeroBitCount + 1
                    result.append(Elimination(
                        technique: .xyWing,
                        patternCells: [pivot, first, second],
                        regionCells: targets,
                        removals: Dictionary(uniqueKeysWithValues: targets.map { ($0, shared) }),
                        reason: "The highlighted cell in \(cellName(pivot)) can only be \(digitList(candidates[pivot])). "
                            + "Either way, one of the other two highlighted cells becomes \(digit), "
                            + "so a cell that sees both of them can't be \(digit)."
                    ))
                }
            }
        }
        return result
    }

    // MARK: - Wording

    static func cellName(_ cell: Int) -> String {
        "row \(BoardGeometry.row(of: cell) + 1), column \(BoardGeometry.column(of: cell) + 1)"
    }

    static func unitName(_ unit: Int) -> String {
        switch unit {
        case 0..<9: return "row \(unit + 1)"
        case 9..<18: return "column \(unit - 8)"
        default:
            let names = [
                "top-left", "top-middle", "top-right",
                "middle-left", "center", "middle-right",
                "bottom-left", "bottom-middle", "bottom-right",
            ]
            return "the \(names[unit - 18]) box"
        }
    }

    private static func digitList(_ mask: UInt16) -> String {
        let all = digits(in: mask).map(String.init)
        guard let last = all.last, all.count > 1 else { return all.first ?? "" }
        return all.dropLast().joined(separator: ", ") + " or " + last
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    private static func merged(_ first: [Int], _ second: [Int]) -> [Int] {
        first + second.filter { !first.contains($0) }
    }

    private static func hint(for single: Single) -> Hint {
        let digit = single.digit
        switch single.kind {
        case .lastCell(let unit):
            return Hint(
                technique: .lastCell, action: .place, cell: single.cell, digit: digit,
                patternCells: [], regionCells: BoardGeometry.units[unit],
                explanation: "\(capitalized(unitName(unit))) has only one empty cell left, and the only digit missing is \(digit)."
            )
        case .naked:
            return Hint(
                technique: .nakedSingle, action: .place, cell: single.cell, digit: digit,
                patternCells: [], regionCells: BoardGeometry.peers[single.cell],
                explanation: "Every digit except \(digit) already appears in the outlined cell's row, column or box, "
                    + "so it has to be \(digit)."
            )
        case .hidden(let unit):
            return Hint(
                technique: .hiddenSingle, action: .place, cell: single.cell, digit: digit,
                patternCells: [], regionCells: BoardGeometry.units[unit],
                explanation: "In \(unitName(unit)), \(digit) has only one place left to go: every other empty cell "
                    + "there already sees a \(digit) in its row, column or box."
            )
        }
    }

    private static func hint(for elimination: Elimination, unlocking single: Single, chained: Bool) -> Hint {
        let consequence: String
        switch single.kind {
        case .hidden(let unit):
            consequence = "That leaves the outlined cell as the only place for \(single.digit) in \(unitName(unit))."
        case .naked, .lastCell:
            consequence = "That leaves \(single.digit) as the only digit for the outlined cell."
        }
        let preface = chained ? "This one takes a few steps. Once the easier candidates are ruled out: " : ""
        return Hint(
            technique: elimination.technique, action: .place, cell: single.cell, digit: single.digit,
            patternCells: elimination.patternCells, regionCells: elimination.regionCells,
            explanation: preface + elimination.reason + " " + consequence
        )
    }
}
