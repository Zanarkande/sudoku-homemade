import SwiftUI

struct GameView: View {
    @Environment(GameSession.self) private var session
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.sounds) private var sounds = false
    @AppStorage(SettingsKey.mistakeLimit) private var mistakeLimit = false
    @AppStorage(SettingsKey.showTimer) private var showTimer = true
    @AppStorage(SettingsKey.largeDigits) private var largeDigits = false
    @State private var showSettings = false
    @State private var confirmRestart = false
    /// After a game ends, lets the player look at the final board instead of the result card.
    @State private var reviewingBoard = false

    var body: some View {
        Group {
            if let game = session.game {
                content(game)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeBackground())
        .navigationTitle(session.game.map { $0.isDaily ? "Daily Puzzle" : $0.difficulty.title } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { optionsMenu }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .confirmationDialog("Restart this puzzle?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Restart", role: .destructive) { session.restart() }
        } message: {
            Text("Your progress on this puzzle will be cleared.")
        }
        .onAppear { session.setBoardVisible(true) }
        .onDisappear { session.setBoardVisible(false) }
        .sensoryFeedback(trigger: session.inputFeedback) { _, _ in
            haptics ? .impact(weight: .light) : nil
        }
        .sensoryFeedback(trigger: session.errorFeedback) { _, _ in
            haptics ? .error : nil
        }
        .sensoryFeedback(trigger: session.successFeedback) { _, _ in
            haptics ? .success : nil
        }
        .onChange(of: session.inputFeedback) { play(.tap) }
        .onChange(of: session.errorFeedback) { play(.error) }
        .onChange(of: session.successFeedback) { play(.success) }
    }

    private func play(_ sound: SoundPlayer.Sound) {
        if sounds { SoundPlayer.shared.play(sound) }
    }

    private func content(_ game: GameState) -> some View {
        GeometryReader { proxy in
            // iPad in landscape: board on the left, controls on the right.
            let sideBySide = proxy.size.width >= 700 && proxy.size.width > proxy.size.height
            Group {
                if sideBySide {
                    // The board is as large as the height allows; the status row matches its width.
                    let boardSide = max(200, min(proxy.size.width - 380, proxy.size.height - 84))
                    HStack(spacing: 32) {
                        VStack(spacing: 10) {
                            statusRow(game)
                            board(game)
                        }
                        .frame(width: boardSide)
                        VStack(spacing: 20) {
                            if let hint = session.activeHint {
                                HintCard(hint: hint)
                            }
                            ActionBar(game: game)
                            NumberPad(game: game, columns: 3, largeDigits: largeDigits)
                        }
                        .frame(width: 300)
                    }
                    .padding(24)
                } else {
                    VStack(spacing: 0) {
                        statusRow(game)
                            .padding(.bottom, 10)
                        board(game)
                        Spacer(minLength: 12)
                        ActionBar(game: game)
                        Spacer(minLength: 12)
                        // While a hint is explained, it takes the place of the number pad.
                        if let hint = session.activeHint {
                            HintCard(hint: hint)
                        } else {
                            NumberPad(game: game, columns: 9, largeDigits: largeDigits)
                        }
                        Spacer(minLength: 8)
                    }
                    .frame(maxWidth: 640)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .disabled(game.status != .playing)
        .overlay {
            if game.status != .playing {
                if reviewingBoard {
                    backToResultButton
                } else {
                    ResultOverlay(game: game) { reviewingBoard = true }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: game.status)
        .animation(.easeOut(duration: 0.25), value: reviewingBoard)
        .onChange(of: game.status) { reviewingBoard = false }
    }

    private func board(_ game: GameState) -> some View {
        BoardView(
            game: game,
            selected: session.selected,
            concealed: session.isPaused,
            pulses: session.cellPulses,
            pulseDelays: session.cellPulseDelays,
            hint: session.activeHint,
            largeDigits: largeDigits
        ) { index in
            session.select(index)
        }
        .overlay {
            if session.isPaused { pausedOverlay }
        }
    }

    private func statusRow(_ game: GameState) -> some View {
        HStack {
            if game.isHardcore {
                // Hardcore games keep the mistake count secret until the end.
                HardcoreBadge()
            } else {
                Label {
                    Text(mistakeLimit ? "\(game.mistakes)/\(GameState.mistakeLimit)" : "\(game.mistakes)")
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "xmark.circle")
                }
                .foregroundStyle(game.mistakes > 0 ? Color.red : theme.inkSoft)
                .accessibilityLabel("Mistakes: \(game.mistakes)")
            }

            Spacer()

            Button {
                session.togglePause()
            } label: {
                HStack(spacing: 6) {
                    if showTimer { ClockLabel() }
                    Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                }
            }
            .foregroundStyle(theme.inkSoft)
            .accessibilityLabel(session.isPaused ? "Resume" : "Pause")
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 4)
    }

    private var pausedOverlay: some View {
        Button {
            session.togglePause()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 64))
                Text("Paused")
                    .font(.headline)
                    .foregroundStyle(theme.inkSoft)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.accent)
        .accessibilityLabel("Resume")
    }

    private var backToResultButton: some View {
        VStack {
            Spacer()
            Button("Back to Result") { reviewingBoard = false }
                .buttonStyle(CozyButtonStyle())
                .frame(maxWidth: 320)
                .shadow(color: theme.shadow, radius: 12, y: 5)
                .padding(24)
        }
    }

    private var optionsMenu: some View {
        Menu {
            Menu("New Game", systemImage: "plus") {
                ForEach(Difficulty.allCases) { difficulty in
                    Button(difficulty.title) {
                        Task { await session.newGame(difficulty, hardcore: session.hardcoreForNextGame) }
                    }
                }
            }
            Button("Restart Puzzle", systemImage: "arrow.counterclockwise") { confirmRestart = true }
            Button("Settings", systemImage: "gearshape") { showSettings = true }
        } label: {
            Label("Options", systemImage: "ellipsis.circle")
        }
    }
}

/// Kept as its own view so the ticking clock doesn't redraw the board.
private struct ClockLabel: View {
    @Environment(GameSession.self) private var session

    var body: some View {
        Text(TimeFormat.string(session.elapsed))
            .monospacedDigit()
            .accessibilityLabel("Time \(TimeFormat.string(session.elapsed))")
    }
}

/// Explains the current hint. Tapping "Hint" again (or the button here) applies it.
private struct HintCard: View {
    @Environment(GameSession.self) private var session
    @Environment(\.theme) private var theme
    let hint: Hint

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(theme.warm)
                Text(hint.technique.title)
                    .font(.headline)
                    .foregroundStyle(theme.ink)
                Spacer()
                Button("Close Hint", systemImage: "xmark.circle.fill") { session.dismissHint() }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(theme.inkSoft)
            }
            Text(hint.explanation)
                .font(.subheadline)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(hint.action == .place ? "Tap Hint again to fill it in." : "Tap Hint again to clear it.")
                    .font(.caption)
                    .foregroundStyle(theme.inkSoft)
                Spacer()
                Button(hint.action == .place ? "Fill It In" : "Clear It") { session.hint() }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .foregroundStyle(theme.onAccent)
            }
        }
        .buttonStyle(.plain)
        .card(padding: 14)
        .transition(.opacity)
    }
}

private struct ActionBar: View {
    @Environment(GameSession.self) private var session
    @Environment(\.theme) private var theme
    let game: GameState

    var body: some View {
        HStack(spacing: 0) {
            action("Undo", systemImage: "arrow.uturn.backward") { session.undo() }
                .disabled(!game.canUndo)
            action("Erase", systemImage: "eraser") { session.erase() }
            action(
                session.notesMode ? "Notes On" : "Notes Off",
                systemImage: session.notesMode ? "pencil.circle.fill" : "pencil",
                tint: session.notesMode ? theme.accent : theme.inkSoft
            ) {
                session.notesMode.toggle()
            }
            if game.isHardcore {
                action("No Hints", systemImage: "lightbulb.slash") {}
                    .disabled(true)
            } else if session.activeHint != nil {
                action("Apply", systemImage: "lightbulb.fill", tint: theme.warm) { session.hint() }
            } else {
                action("Hint", systemImage: "lightbulb") { session.hint() }
            }
        }
        .disabled(session.isPaused)
    }

    private func action(
        _ title: String,
        systemImage: String,
        tint: Color? = nil,
        perform: @escaping () -> Void
    ) -> some View {
        ActionButton(title: title, systemImage: systemImage, tint: tint ?? theme.inkSoft, perform: perform)
    }
}

private struct ActionButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let systemImage: String
    let tint: Color
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 22))
                    .frame(height: 26)
                Text(title)
                    .font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private struct NumberPad: View {
    @Environment(GameSession.self) private var session
    @Environment(\.theme) private var theme
    let game: GameState
    /// 9 for a single row of keys, 3 for a square pad (iPad in landscape).
    let columns: Int
    let largeDigits: Bool

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: columns), spacing: 5) {
            ForEach(1...9, id: \.self) { digit in
                // Hardcore games don't show how many of each digit are left.
                let remaining = game.isHardcore ? nil : game.remaining(digit)
                Button {
                    session.enter(digit)
                } label: {
                    VStack(spacing: 0) {
                        Text("\(digit)")
                            .font(.system(size: largeDigits ? 34 : 28, weight: .medium, design: .rounded))
                        if let remaining {
                            Text("\(remaining)")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(theme.inkSoft)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: columns == 9 ? 62 : 76)
                    .background(theme.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .shadow(color: theme.shadow.opacity(0.5), radius: 3, y: 2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
                .disabled(remaining == 0)
                .opacity(remaining == 0 ? 0.3 : 1)
                .accessibilityLabel(remaining.map { "\(digit), \($0) remaining" } ?? "\(digit)")
            }
        }
        .disabled(session.isPaused)
    }
}

#Preview {
    NavigationStack {
        GameView()
            .environment(GameSession())
    }
    .themed()
}
