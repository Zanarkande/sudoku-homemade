import Foundation

/// The app keeps two games side by side: the regular one and today's daily puzzle.
nonisolated enum GameSlot: String, CaseIterable, Sendable {
    case regular, daily
}

/// Saves the current games and the statistics as small JSON files on the device.
nonisolated struct GameStore: Sendable {
    let directory: URL

    static let `default` = GameStore(
        directory: URL.applicationSupportDirectory.appending(path: "SudokuH", directoryHint: .isDirectory)
    )

    private func gameURL(_ slot: GameSlot) -> URL {
        directory.appending(path: slot == .regular ? "current-game.json" : "daily-game.json")
    }
    private var statisticsURL: URL { directory.appending(path: "statistics.json") }

    func loadGame(_ slot: GameSlot = .regular) -> GameState? {
        load(GameState.self, from: gameURL(slot))
    }

    func save(_ game: GameState?, slot: GameSlot = .regular) {
        if let game {
            write(game, to: gameURL(slot))
        } else {
            try? FileManager.default.removeItem(at: gameURL(slot))
        }
    }

    func loadStatistics() -> Statistics {
        load(Statistics.self, from: statisticsURL) ?? Statistics()
    }

    func save(_ statistics: Statistics) {
        write(statistics, to: statisticsURL)
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            assertionFailure("Could not save \(url.lastPathComponent): \(error)")
        }
    }
}
