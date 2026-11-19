# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

SudokuH is an offline SwiftUI Sudoku app for iPhone and iPad (iOS 17+). No ads, no tracking, no network, no third-party dependencies. Its look is deliberately warm and "cozy" (serif titles, rounded digits, terracotta/amber palette); keep new UI in that style and use the `Theme` colours rather than system colours.

## Commands

There is one scheme, `SudokuH`, with an app target and a unit-test target (`SudokuHTests`). There is no linter and no UI-test target.

```sh
# Build
xcodebuild -project SudokuH.xcodeproj -scheme SudokuH \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# Run all tests (needs a concrete simulator; list them with `xcrun simctl list devices available`)
xcodebuild -project SudokuH.xcodeproj -scheme SudokuH \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# Run one suite or one test (Swift Testing: Target/Suite/function()).
# The trailing "()" is required: without it the run "succeeds" with 0 tests.
xcodebuild ... test -only-testing:SudokuHTests/HintTests
xcodebuild ... test '-only-testing:SudokuHTests/HintTests/nakedSingleIsFound()'

# Regenerate the app icon (light, dark, tinted) into the asset catalog
swift Design/make_icon.swift
```

Tests use Swift Testing (`@Suite`, `@Test`, `#expect`), not XCTest, so xcodebuild's XCTest line "Executed 0 tests" is expected; the real count is in the `Test run with N tests in M suites passed` line.

The project file is `SudokuH.xcodeproj/project.xcproj` and both targets use synchronized folders: a file added under `SudokuH/` or `SudokuHTests/` joins its target automatically, with no project-file edit.

## Concurrency settings that affect every file

The app target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (and approachable concurrency). Any type you declare is main-actor isolated unless you say otherwise. Model types are therefore all marked `nonisolated` and `Sendable` so they can be used from background tasks and tests; do the same for new model code. Puzzle generation runs off the main actor via `Task.detached` in `GameSession`.

## Architecture

Three layers, with a strict direction: views → `GameSession` → model.

**Model (`SudokuH/Model/`)** — pure value types, no SwiftUI, no side effects except `GameStore`.
- `GameState` holds one game and *all the rules*: placing digits, notes, undo, mistakes, win/loss. Its mutating methods return a `MoveOutcome` (`ignored`, `changed`, `mistake`, `won`, `lost`) that the session turns into feedback and statistics. Its `init(from:)` decodes every later-added field with `decodeIfPresent`, so saves from older versions keep loading — follow that pattern when adding stored fields (same for `Statistics`).
- A board is a flat array of 81 `Int`s (0 = empty), indexed `row * 9 + column`. Notes are a `UInt16` bitmask per cell. `BoardGeometry` has the row/column/box units and peers.
- `SudokuSolver` is the bitmask backtracking solver (`solve`, `countSolutions`) that the generator uses for uniqueness checks.
- `SudokuGenerator` builds a solved grid and digs cells out while the puzzle stays unique (and, for Easy/Medium, solvable with singles only — see `Difficulty`). It is time-budgeted for regular games; `DailyPuzzle` instead uses a seeded RNG and a fixed attempt count so every device gets the same puzzle for the same day. Days are identified by `DayKey` (`DailyCalendar.swift`), an `Int` like `20261114`.
- `HintEngine` finds the easiest applicable technique and produces a `Hint` with an explanation and the cells to highlight.
- `Statistics` groups results by `StatCategory` (daily, hardcore, or the difficulty) and supports text export/import.
- `GameStore` persists games and statistics as JSON in Application Support. Tests pass a store pointing at a temporary directory.

**`GameSession` (`SudokuH/GameSession.swift`)** — the single `@Observable` object, created in `MyApp` and injected through the environment. It owns:
- Two game slots side by side, `.regular` and `.daily` (`GameSlot`), with one "active" slot on the board. Starting or switching games goes through `start` / `activate`, which park the current game, account for an abandoned one, and save.
- The clock. `elapsed` ticks every 250 ms, but only while the scene is active, the board is visible, and the game is unpaused and in progress (`updateClock`).
- Statistics updates, auto-saving, the active hint, and counters (`inputFeedback`, `cellPulses`, …) that views watch to trigger haptics, sounds and animations.

**Views (`SudokuH/Views/`)** — `HomeView` owns the `NavigationStack` and pushes `GameView`. Views read the session and call its methods; they contain no game rules. `SoundPlayer` (`SudokuH/SoundPlayer.swift`) synthesises the optional tap sounds in code, so there are no audio files.

### Things that are easy to get wrong

- **Do not read `session.elapsed` (or anything derived from it, like `totalPlayTime` or `elapsed(in:)`) in the body of a large view.** It changes four times a second. Put the read in a small dedicated child view, as `ClockLabel` (GameView) and `HomeTotals` / `ContinueStatus` / `DailyStatus` (HomeView) do. When `HomeView` itself depended on the clock, its navigation stack was rebuilt every tick, which closed menus open in the game screen's toolbar.
- **The clock only knows whether the board is visible through `session.setBoardVisible`.** `GameView` calls it on appear and disappear, but a sheet covers the board without making it disappear, so a sheet shown over the game screen has to call it as well (as the Settings sheet does with `onChange(of: showSettings)`).
- **Starting a new game from the game screen goes through `GameView.requestNewGame`**, not `session.newGame` directly. When the daily puzzle is on the board and a started regular game is parked (`session.newGameReplacesParkedGame`), it asks before replacing that game. `ResultOverlay` gets it as `onNewGame`.
- **A won game can't be restarted** (`session.canRestart`). Playing it again would count a second win, and a daily best time on a grid the player already knows. Lost games can be restarted.
- **The Home screen uses `ViewThatFits`**: a plain page when the content fits and a `ScrollView` only when it doesn't, because a `ScrollView` always rubber-bands, even with `.scrollBounceBehavior(.basedOnSize)`. Keep it in mind when adding cards. The iPhone 15 with a Continue card is close to the limit.
- **Theming.** Colours come from `@Environment(\.theme)` (`Theme.swift`), not from the asset catalog. `.themed()` must be applied at the app root *and on every sheet*, since sheets don't inherit it. Reusable pieces live in `Theme.swift`: `.card()`, `CozyButtonStyle`, `ThemeBackground`, `HardcoreBadge`, `TimeFormat`.
- **Settings** are plain `UserDefaults` values read with `@AppStorage`; the keys are in `SettingsKey` (top of `GameSession.swift`).
- **Hardcore mode** hides every assist (highlights, mistake marks, remaining counts, completion animations, hints) until the game ends. New in-game feedback must respect `game.isHardcore`.
- **The app icon PNGs are generated.** Change `Design/make_icon.swift` and re-run it rather than editing the PNGs in `AppIcon.appiconset`.
