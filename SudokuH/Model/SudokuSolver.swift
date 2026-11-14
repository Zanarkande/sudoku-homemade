import Foundation

/// Backtracking Sudoku solver using bitmasks and a "fewest candidates first" heuristic.
/// Grids are arrays of 81 integers, 0 meaning empty.
nonisolated enum SudokuSolver {
    /// Returns a solution of the grid, or nil if the grid is invalid or unsolvable.
    /// `digitOrder` controls the order in which digits are tried (used to randomise generated grids).
    static func solve(_ cells: [Int], digitOrder: [Int] = Array(1...9)) -> [Int]? {
        guard var search = Search(cells: cells, limit: 1, digitOrder: digitOrder) else { return nil }
        search.run()
        return search.firstSolution
    }

    /// Counts solutions, stopping as soon as `limit` have been found.
    static func countSolutions(_ cells: [Int], limit: Int = 2) -> Int {
        guard var search = Search(cells: cells, limit: limit, digitOrder: Array(1...9)) else { return 0 }
        search.run()
        return search.solutionCount
    }

    static func hasUniqueSolution(_ cells: [Int]) -> Bool {
        countSolutions(cells, limit: 2) == 1
    }

    /// True if the grid is completely filled and breaks no Sudoku rule.
    static func isValidSolution(_ cells: [Int]) -> Bool {
        guard cells.count == BoardGeometry.cellCount, !cells.contains(0) else { return false }
        return Search(cells: cells, limit: 1, digitOrder: []) != nil
    }

    /// True if the puzzle can be completed using only naked and hidden singles,
    /// i.e. without guessing or advanced techniques. Implies a unique solution.
    static func isSolvableWithSingles(_ cells: [Int]) -> Bool {
        guard var search = Search(cells: cells, limit: 1, digitOrder: []) else { return false }
        return search.propagateSingles()
    }
}

nonisolated private struct Search {
    var cells: [Int]
    var rows = [UInt16](repeating: 0, count: 9)
    var columns = [UInt16](repeating: 0, count: 9)
    var boxes = [UInt16](repeating: 0, count: 9)
    let limit: Int
    let digitOrder: [Int]
    var solutionCount = 0
    var firstSolution: [Int]?

    /// Fails if the grid has the wrong size, out-of-range values, or duplicate digits in a unit.
    init?(cells: [Int], limit: Int, digitOrder: [Int]) {
        guard cells.count == BoardGeometry.cellCount else { return nil }
        self.cells = cells
        self.limit = limit
        self.digitOrder = digitOrder
        for index in 0..<81 where cells[index] != 0 {
            let digit = cells[index]
            guard (1...9).contains(digit) else { return nil }
            let bit = UInt16(1) << UInt16(digit - 1)
            guard candidates(at: index) & bit != 0 else { return nil }
            mark(index, bit)
        }
    }

    func candidates(at index: Int) -> UInt16 {
        ~(rows[index / 9] | columns[index % 9] | boxes[BoardGeometry.box(of: index)]) & 0x1FF
    }

    mutating func mark(_ index: Int, _ bit: UInt16) {
        rows[index / 9] |= bit
        columns[index % 9] |= bit
        boxes[BoardGeometry.box(of: index)] |= bit
    }

    mutating func unmark(_ index: Int, _ bit: UInt16) {
        rows[index / 9] &= ~bit
        columns[index % 9] &= ~bit
        boxes[BoardGeometry.box(of: index)] &= ~bit
    }

    mutating func run() {
        var bestIndex = -1
        var bestMask: UInt16 = 0
        var bestCount = 10
        for index in 0..<81 where cells[index] == 0 {
            let mask = candidates(at: index)
            let count = mask.nonzeroBitCount
            if count == 0 { return }
            if count < bestCount {
                bestIndex = index
                bestMask = mask
                bestCount = count
                if count == 1 { break }
            }
        }
        if bestIndex < 0 {
            solutionCount += 1
            if firstSolution == nil { firstSolution = cells }
            return
        }
        for digit in digitOrder {
            let bit = UInt16(1) << UInt16(digit - 1)
            guard bestMask & bit != 0 else { continue }
            cells[bestIndex] = digit
            mark(bestIndex, bit)
            run()
            unmark(bestIndex, bit)
            cells[bestIndex] = 0
            if solutionCount >= limit { return }
        }
    }

    mutating func place(_ index: Int, _ bit: UInt16) {
        cells[index] = bit.trailingZeroBitCount + 1
        mark(index, bit)
    }

    mutating func propagateSingles() -> Bool {
        var progress = true
        while progress {
            progress = false
            // Naked singles: a cell with exactly one candidate.
            for index in 0..<81 where cells[index] == 0 {
                let mask = candidates(at: index)
                if mask == 0 { return false }
                if mask.nonzeroBitCount == 1 {
                    place(index, mask)
                    progress = true
                }
            }
            // Hidden singles: a digit that fits in exactly one cell of a unit.
            for unit in BoardGeometry.units {
                var once: UInt16 = 0
                var twice: UInt16 = 0
                for index in unit where cells[index] == 0 {
                    let mask = candidates(at: index)
                    twice |= once & mask
                    once |= mask
                }
                let hidden = once & ~twice
                guard hidden != 0 else { continue }
                for index in unit where cells[index] == 0 {
                    let mask = candidates(at: index) & hidden
                    if mask != 0 {
                        place(index, mask & ~(mask - 1))
                        progress = true
                    }
                }
            }
        }
        return !cells.contains(0)
    }
}
