import SwiftUI

struct HomeView: View {
    @Environment(GameSession.self) private var session
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(SettingsKey.hardcoreDefault) private var hardcoreDefault = false
    @AppStorage(SettingsKey.lastDifficulty) private var difficulty = Difficulty.medium
    @State private var hardcore = false
    @State private var showGame = false
    @State private var showStatistics = false
    @State private var showSettings = false
    @State private var confirmReplace = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TimelineView(.everyMinute) { context in
                        header(at: context.date)
                    }
                    totals
                    // Side by side on iPad, stacked on iPhone.
                    let layout = sizeClass == .regular
                        ? AnyLayout(HStackLayout(alignment: .top, spacing: 18))
                        : AnyLayout(VStackLayout(spacing: 18))
                    layout {
                        if session.canContinue, let game = session.regularGame {
                            continueCard(game)
                        }
                        dailyCard
                    }
                    newGameCard
                }
                .frame(maxWidth: sizeClass == .regular ? 760 : 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(ThemeBackground())
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Statistics", systemImage: "chart.bar.fill") { showStatistics = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape.fill") { showSettings = true }
                }
            }
            .navigationDestination(isPresented: $showGame) {
                GameView()
            }
            .sheet(isPresented: $showStatistics) { StatisticsView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .confirmationDialog("Start a new game?", isPresented: $confirmReplace, titleVisibility: .visible) {
                Button("Start New Game") { startNewGame() }
            } message: {
                Text("It will replace the game you have in progress.")
            }
            .onAppear { hardcore = hardcoreDefault }
            .onChange(of: hardcoreDefault) { hardcore = hardcoreDefault }
        }
    }

    // MARK: - Header

    private func header(at date: Date) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(date, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.8)
                    .foregroundStyle(theme.inkSoft)
                Text(Self.greeting(at: date))
                    .font(.system(size: 36, weight: .bold, design: .serif))
                    .foregroundStyle(theme.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("Settle in. No ads, just puzzles.")
                    .font(.subheadline)
                    .foregroundStyle(theme.inkSoft)
            }
            Spacer(minLength: 12)
            LogoMark()
                .frame(width: 54, height: 54)
        }
        .padding(.top, 4)
    }

    static func greeting(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Good night"
        }
    }

    // MARK: - Totals

    private var totals: some View {
        HStack(spacing: 14) {
            totalTile(
                value: "\(session.statistics.totalPlayed)",
                label: "Games played",
                systemImage: "square.grid.3x3.fill",
                color: theme.accent
            )
            totalTile(
                value: TimeFormat.hoursAndMinutes(session.totalPlayTime),
                label: "Time playing",
                systemImage: "hourglass",
                color: theme.fresh
            )
        }
    }

    private func totalTile(value: String, label: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(theme.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Continue

    private func continueCard(_ game: GameState) -> some View {
        Button {
            session.resumeRegular()
            showGame = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Continue")
                            .font(.footnote.weight(.semibold))
                            .textCase(.uppercase)
                            .kerning(0.8)
                            .foregroundStyle(theme.onAccent.opacity(0.8))
                        HStack(spacing: 8) {
                            Text(game.difficulty.title)
                                .font(.system(.title, design: .serif, weight: .bold))
                            if game.isHardcore { HardcoreBadge(compact: true) }
                        }
                        Text("\(TimeFormat.string(session.elapsed(in: .regular))) · \(Int(game.progress * 100))% filled")
                            .font(.subheadline)
                            .monospacedDigit()
                            .opacity(0.9)
                    }
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.title3)
                        .frame(width: 48, height: 48)
                        .background(theme.onAccent.opacity(0.2), in: Circle())
                }
                ProgressView(value: game.progress)
                    .tint(theme.onAccent)
            }
            .foregroundStyle(theme.onAccent)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [theme.accent, theme.warm], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .shadow(color: theme.accent.opacity(0.3), radius: 14, y: 7)
        }
        .buttonStyle(PressableCardStyle())
    }

    // MARK: - Daily puzzle

    private var dailyCard: some View {
        let solved = session.isDailySolved
        let streak = session.dailyStreak
        return Button {
            openDaily()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: solved ? "checkmark.seal.fill" : "calendar")
                    .font(.title2)
                    .foregroundStyle(solved ? theme.fresh : theme.accent)
                    .frame(width: 50, height: 50)
                    .background(
                        (solved ? theme.fresh : theme.accent).opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily Puzzle")
                        .font(.system(.title3, design: .serif, weight: .bold))
                        .foregroundStyle(theme.ink)
                    Text(dailyStatus)
                        .font(.subheadline)
                        .foregroundStyle(solved ? theme.fresh : theme.inkSoft)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                VStack(spacing: 0) {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                        Text("\(streak)")
                            .monospacedDigit()
                    }
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(streak > 0 ? theme.warm : theme.inkSoft.opacity(0.6))
                    Text(streak == 1 ? "day" : "days")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.inkSoft)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Streak: \(streak) days")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(PressableCardStyle())
        .disabled(session.isGenerating)
    }

    private var dailyStatus: String {
        if session.isDailySolved {
            return "Solved today — see you tomorrow"
        }
        if let game = session.dailyGame, game.hasStarted {
            return "In progress · \(TimeFormat.string(session.elapsed(in: .daily)))"
        }
        return "Today's puzzle is waiting"
    }

    private func openDaily() {
        Task {
            if await session.openDaily() { showGame = true }
        }
    }

    // MARK: - New game

    private var newGameCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Game")
                .font(.system(.title3, design: .serif, weight: .bold))
                .foregroundStyle(theme.ink)

            HStack(spacing: 8) {
                ForEach(Difficulty.allCases) { option in
                    let isSelected = option == difficulty
                    Button {
                        difficulty = option
                    } label: {
                        Text(option.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .foregroundStyle(isSelected ? theme.onAccent : theme.ink)
                            .background(
                                isSelected ? theme.accent : theme.tile,
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

            Toggle(isOn: $hardcore) {
                HStack(spacing: 10) {
                    Image(systemName: "eye.slash.fill")
                        .foregroundStyle(theme.inkSoft)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Hardcore")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.ink)
                        Text("No highlights, no hints. Mistakes show only at the end.")
                            .font(.caption)
                            .foregroundStyle(theme.inkSoft)
                    }
                }
            }
            .tint(theme.accent)

            Button {
                if session.canContinue, session.regularGame?.hasStarted == true {
                    confirmReplace = true
                } else {
                    startNewGame()
                }
            } label: {
                if session.isGenerating {
                    ProgressView()
                } else {
                    Text("Start Puzzle")
                }
            }
            .buttonStyle(CozyButtonStyle())
            .disabled(session.isGenerating)
        }
        .card()
    }

    private func startNewGame() {
        Task {
            await session.newGame(difficulty, hardcore: hardcore)
            showGame = true
        }
    }
}

/// Cards that gently shrink while pressed.
private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A small 3x3 grid mark echoing the app icon.
struct LogoMark: View {
    var body: some View {
        GeometryReader { proxy in
            let spacing = proxy.size.width * 0.06
            let tile = (proxy.size.width - spacing * 2) / 3
            VStack(spacing: spacing) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<3, id: \.self) { column in
                            RoundedRectangle(cornerRadius: tile * 0.24, style: .continuous)
                                .fill(Color.accentColor.opacity(row == column ? 1 : 0.22))
                                .frame(width: tile, height: tile)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview {
    HomeView()
        .environment(GameSession())
        .themed()
}
