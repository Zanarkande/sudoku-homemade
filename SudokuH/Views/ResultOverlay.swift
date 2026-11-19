import SwiftUI

/// Shown over the board when the game is won or lost.
struct ResultOverlay: View {
    @Environment(GameSession.self) private var session
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let game: GameState
    /// Hides the card so the final board can be looked at.
    let onReviewBoard: () -> Void

    private var won: Bool { game.status == .won }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: won ? "trophy.fill" : "xmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(won ? theme.warm : Color.red)

                VStack(spacing: 6) {
                    Text(won ? "Solved!" : "Game Over")
                        .font(.system(.title, design: .serif, weight: .bold))
                        .foregroundStyle(theme.ink)
                    subtitle
                    if game.isHardcore { HardcoreBadge() }
                }

                VStack(spacing: 0) {
                    row("Puzzle", game.isDaily ? "Daily · \(game.difficulty.title)" : game.difficulty.title)
                    Divider()
                    row("Time", TimeFormat.string(session.elapsed))
                    Divider()
                    row("Mistakes", "\(game.mistakes)")
                    if won && game.hintsUsed > 0 {
                        Divider()
                        row("Hints", "\(game.hintsUsed)")
                    }
                }
                .background(theme.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(spacing: 10) {
                    if !won {
                        Button("Try Again") { session.restart() }
                            .buttonStyle(CozyButtonStyle())
                    }

                    Button {
                        newGame(game.difficulty)
                    } label: {
                        if session.isGenerating {
                            ProgressView()
                        } else {
                            Text("New Game")
                        }
                    }
                    .buttonStyle(CozyButtonStyle(prominent: won))

                    // Equal-width thirds, so "Difficulty" sits exactly under the
                    // centre of the buttons above whatever the side labels' widths.
                    HStack(spacing: 0) {
                        Button("View Board", action: onReviewBoard)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Menu("Difficulty") {
                            ForEach(Difficulty.allCases) { difficulty in
                                Button(difficulty.title) { newGame(difficulty) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        Button("Home") { dismiss() }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.top, 4)
                }
                .disabled(session.isGenerating)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
            .padding(24)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if won {
            if game.isDaily {
                Label("\(session.dailyStreak)-day streak", systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.warm)
            }
            if session.lastWinWasBestTime {
                Text("New best time")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.accent)
            }
        } else if game.isHardcore {
            let wrong = game.wrongCellCount
            Text(wrong == 1 ? "1 cell was wrong. It's marked in red on the board." : "\(wrong) cells were wrong. They're marked in red on the board.")
                .font(.subheadline)
                .foregroundStyle(theme.inkSoft)
                .multilineTextAlignment(.center)
        } else {
            Text("You made \(GameState.mistakeLimit) mistakes.")
                .font(.subheadline)
                .foregroundStyle(theme.inkSoft)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(theme.inkSoft)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(theme.ink)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func newGame(_ difficulty: Difficulty) {
        Task { await session.newGame(difficulty, hardcore: session.hardcoreForNextGame) }
    }
}
