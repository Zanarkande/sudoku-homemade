import Charts
import SwiftUI
import UIKit

struct StatisticsView: View {
    var body: some View {
        NavigationStack {
            StatisticsContent()
        }
        .themed()
    }
}

private struct StatisticsContent: View {
    @Environment(GameSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var confirmReset = false
    @State private var showImport = false
    @State private var copied = false
    /// nil shows every kind of game in the chart.
    @State private var chartFilter: StatCategory?

    private var statistics: Statistics { session.statistics }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                totals
                chartCard
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 18)], spacing: 18) {
                    ForEach(StatCategory.allCases) { category in
                        categoryCard(category)
                    }
                }
                historyCard
                backupCard
                Button("Reset Statistics", role: .destructive) { confirmReset = true }
                    .font(.subheadline)
                    .disabled(statistics == Statistics())
                    .padding(.top, 4)
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(ThemeBackground())
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .confirmationDialog("Reset all statistics?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { session.resetStatistics() }
        } message: {
            Text("This also clears your history and daily streak. Export a backup first if you might want them back.")
        }
        .sheet(isPresented: $showImport) { ImportSheet() }
    }

    // MARK: - Totals

    private var totals: some View {
        HStack(spacing: 0) {
            total("\(statistics.totalPlayed)", "Played")
            Divider().frame(height: 36)
            total("\(statistics.totalWon)", "Won")
            Divider().frame(height: 36)
            total(TimeFormat.hoursAndMinutes(session.totalPlayTime), "Time playing")
        }
        .card(padding: 16)
    }

    private func total(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(theme.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Chart

    private var recentWins: [GameRecord] {
        Array(
            statistics.history
                .filter { $0.won && (chartFilter == nil || $0.category == chartFilter) }
                .suffix(20)
        )
    }

    private var chartCard: some View {
        let wins = recentWins
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    cardTitle("Recent Solve Times")
                    Text(wins.isEmpty ? "Oldest to newest" : "Last \(wins.count) wins, oldest to newest")
                        .font(.caption)
                        .foregroundStyle(theme.inkSoft)
                }
                Spacer()
                Picker("Show", selection: $chartFilter) {
                    Text("All Games").tag(StatCategory?.none)
                    ForEach(StatCategory.allCases) { category in
                        Text(category.title).tag(StatCategory?.some(category))
                    }
                }
                .pickerStyle(.menu)
            }

            if wins.isEmpty {
                Text("Solved puzzles will show up here.")
                    .font(.subheadline)
                    .foregroundStyle(theme.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(Array(wins.enumerated()), id: \.element.id) { index, record in
                    LineMark(
                        x: .value("Game", index + 1),
                        y: .value("Minutes", record.time / 60)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(theme.accent)
                    PointMark(
                        x: .value("Game", index + 1),
                        y: .value("Minutes", record.time / 60)
                    )
                    .symbolSize(60)
                    .foregroundStyle(theme.accent)
                    .accessibilityLabel(record.date.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue(TimeFormat.string(record.time))
                }
                .chartXScale(domain: 0.5...(Double(max(wins.count, 2)) + 0.5))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(theme.ink.opacity(0.10))
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text(TimeFormat.string(minutes * 60))
                                    .foregroundStyle(theme.inkSoft)
                            }
                        }
                    }
                }
                .frame(height: 170)
            }
        }
        .card()
    }

    // MARK: - Categories

    private func categoryCard(_ category: StatCategory) -> some View {
        let stats = statistics[category]
        // The daily puzzle counts streaks in days rather than in wins.
        let currentStreak = category == .daily ? session.dailyStreak : stats.currentStreak
        let bestStreak = category == .daily ? statistics.bestDailyStreak : stats.bestStreak
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                cardTitle(category.title)
                if category == .hardcore { HardcoreBadge(compact: true) }
                if category == .daily {
                    Image(systemName: "flame.fill").foregroundStyle(theme.warm)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    metric("Played", "\(stats.played)")
                    metric("Won", "\(stats.won)")
                    metric("Win rate", stats.winRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                }
                GridRow {
                    metric("Best time", stats.bestTime.map(TimeFormat.string) ?? "–")
                    metric("Average", stats.averageTime.map(TimeFormat.string) ?? "–")
                    metric(category == .daily ? "Day streak" : "Streak", "\(currentStreak) · best \(bestStreak)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(theme.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - History

    private var historyCard: some View {
        let records = Array(statistics.history.suffix(60).reversed())
        return VStack(alignment: .leading, spacing: 12) {
            cardTitle("History")
            if records.isEmpty {
                Text("Finished games will be listed here.")
                    .font(.subheadline)
                    .foregroundStyle(theme.inkSoft)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(records) { record in
                        historyRow(record)
                        if record.id != records.last?.id { Divider() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func historyRow(_ record: GameRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: record.won ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(record.won ? theme.fresh : theme.inkSoft.opacity(0.6))
                .accessibilityLabel(record.won ? "Won" : "Lost")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.isDaily ? "Daily · \(record.difficulty.title)" : record.difficulty.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.ink)
                    if record.isHardcore { HardcoreBadge(compact: true) }
                }
                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(theme.inkSoft)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(TimeFormat.string(record.time))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.ink)
                Text(record.mistakes == 1 ? "1 mistake" : "\(record.mistakes) mistakes")
                    .font(.caption)
                    .foregroundStyle(theme.inkSoft)
            }
            .monospacedDigit()
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Backup

    private var backupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("Backup")
            Text("Export your statistics, history and streak as text you can keep anywhere, and import them again later.")
                .font(.subheadline)
                .foregroundStyle(theme.inkSoft)
            HStack(spacing: 10) {
                ShareLink(item: statistics.exportText()) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(CozyButtonStyle(prominent: false))
                Button {
                    UIPasteboard.general.string = statistics.exportText()
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(CozyButtonStyle(prominent: false))
                Button {
                    showImport = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(CozyButtonStyle(prominent: false))
            }
            .labelStyle(.titleOnly)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func cardTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(.title3, design: .serif, weight: .bold))
            .foregroundStyle(theme.ink)
    }
}

/// Lets the player paste a backup and replace the current statistics with it.
private struct ImportSheet: View {
    var body: some View {
        NavigationStack {
            ImportForm()
        }
        .themed()
    }
}

private struct ImportForm: View {
    @Environment(GameSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var text = ""
    @State private var confirmImport = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paste a backup made with Export. It replaces the statistics currently on this device.")
                .font(.subheadline)
                .foregroundStyle(theme.inkSoft)
            TextEditor(text: $text)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(theme.ink)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(8)
                .background(theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(spacing: 10) {
                PasteButton(payloadType: String.self) { strings in
                    text = strings.first ?? ""
                }
                .buttonBorderShape(.capsule)
                Spacer()
                Button("Import") { confirmImport = true }
                    .buttonStyle(CozyButtonStyle())
                    .frame(maxWidth: 160)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .background(ThemeBackground())
        .navigationTitle("Import Backup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .confirmationDialog("Replace your statistics with this backup?", isPresented: $confirmImport, titleVisibility: .visible) {
            Button("Replace Statistics", role: .destructive) {
                if session.importStatistics(from: text) {
                    dismiss()
                } else {
                    failed = true
                }
            }
        }
        .alert("That doesn't look like a backup", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was changed. Paste the complete text produced by Export and try again.")
        }
    }
}

#Preview {
    StatisticsView()
        .environment(GameSession())
}
