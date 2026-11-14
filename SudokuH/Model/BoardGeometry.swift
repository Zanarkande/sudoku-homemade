import Foundation

/// Static lookup tables describing the 9x9 Sudoku grid.
/// Cells are indexed 0...80, row by row.
nonisolated enum BoardGeometry {
    static let cellCount = 81

    static func row(of index: Int) -> Int { index / 9 }
    static func column(of index: Int) -> Int { index % 9 }
    static func box(of index: Int) -> Int { (index / 27) * 3 + (index % 9) / 3 }

    /// The 27 units (9 rows, 9 columns, 9 boxes), each a list of 9 cell indices.
    static let units: [[Int]] = {
        var result: [[Int]] = []
        for r in 0..<9 { result.append((0..<9).map { r * 9 + $0 }) }
        for c in 0..<9 { result.append((0..<9).map { $0 * 9 + c }) }
        for b in 0..<9 {
            let r0 = (b / 3) * 3, c0 = (b % 3) * 3
            result.append((0..<9).map { (r0 + $0 / 3) * 9 + c0 + $0 % 3 })
        }
        return result
    }()

    /// For each cell, the 20 other cells sharing its row, column or box.
    static let peers: [[Int]] = (0..<81).map { index in
        (0..<81).filter { $0 != index && arePeers($0, index) }
    }

    static func arePeers(_ a: Int, _ b: Int) -> Bool {
        row(of: a) == row(of: b) || column(of: a) == column(of: b) || box(of: a) == box(of: b)
    }
}
