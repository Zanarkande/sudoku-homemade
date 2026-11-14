import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            SettingsForm()
        }
        .themed()
    }
}

private struct SettingsForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.theme) private var themeChoice = ThemeChoice.automatic
    @AppStorage(SettingsKey.largeDigits) private var largeDigits = false
    @AppStorage(SettingsKey.mistakeLimit) private var mistakeLimit = false
    @AppStorage(SettingsKey.hardcoreDefault) private var hardcoreDefault = false
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.sounds) private var sounds = false
    @AppStorage(SettingsKey.showTimer) private var showTimer = true

    var body: some View {
        Form {
            Section("Theme") {
                ForEach(ThemeChoice.allCases) { choice in
                    Button {
                        themeChoice = choice
                    } label: {
                        HStack(spacing: 12) {
                            ThemeSwatch(choice: choice)
                            Text(choice.title)
                                .foregroundStyle(theme.ink)
                            Spacer()
                            if choice == themeChoice {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(theme.accent)
                            }
                        }
                    }
                    .accessibilityAddTraits(choice == themeChoice ? .isSelected : [])
                }
            }
            .listRowBackground(theme.card)

            Section {
                Toggle("Large Digits", isOn: $largeDigits)
                Toggle("Show Timer", isOn: $showTimer)
            } header: {
                Text("Display")
            }
            .listRowBackground(theme.card)

            Section {
                Toggle("Mistake Limit", isOn: $mistakeLimit)
                Toggle("Hardcore by Default", isOn: $hardcoreDefault)
            } header: {
                Text("Game")
            } footer: {
                Text("With the mistake limit, a game ends after \(GameState.mistakeLimit) mistakes. Hardcore removes all highlights, hints and mistake markers; you can also switch it on for a single game when you start one.")
            }
            .listRowBackground(theme.card)

            Section {
                Toggle("Haptic Feedback", isOn: $haptics)
                Toggle("Tap Sounds", isOn: $sounds)
            } header: {
                Text("Feedback")
            } footer: {
                Text("Sounds are quiet and follow the silent switch.")
            }
            .listRowBackground(theme.card)

            Section {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            } footer: {
                Text("No ads, no tracking, no internet connection. Everything stays on your device.")
            }
            .listRowBackground(theme.card)
        }
        .foregroundStyle(theme.ink)
        .scrollContentBackground(.hidden)
        .background(ThemeBackground())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

/// A small preview of a theme's colors.
private struct ThemeSwatch: View {
    let choice: ThemeChoice

    var body: some View {
        // "Automatic" shows its light theme on the left and its dark theme on the right.
        let left = choice.theme(for: .light)
        let right = choice.theme(for: .dark)
        HStack(spacing: 0) {
            left.backgroundTop
            right.backgroundTop
        }
        .frame(width: 44, height: 30)
        .overlay {
            HStack(spacing: 4) {
                Circle().fill(left.accent)
                Circle().fill(right.warm)
                Circle().fill(right.fresh)
            }
            .frame(height: 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    SettingsView()
}
