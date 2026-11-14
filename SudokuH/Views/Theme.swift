import SwiftUI

/// The colors of one of the app's warm themes.
nonisolated struct Theme: Equatable, Sendable {
    let isDark: Bool
    let backgroundTop: Color
    let backgroundBottom: Color
    /// Cards and sheets.
    let card: Color
    /// Smaller surfaces sitting on a card or on the background (number keys, tiles).
    let tile: Color
    let board: Color
    /// Main text and given digits.
    let ink: Color
    let inkSoft: Color
    /// Buttons, the player's digits, the selection.
    let accent: Color
    /// Streaks and highlights.
    let warm: Color
    /// Success and "done" states.
    let fresh: Color

    var shadow: Color { .black.opacity(isDark ? 0.35 : 0.10) }
    /// Text on top of `accent`.
    var onAccent: Color { isDark ? Color(hex: 0x2A1A12) : Color(hex: 0xFFF9EE) }

    static let cozyCream = Theme(
        isDark: false,
        backgroundTop: Color(hex: 0xFAF3E6), backgroundBottom: Color(hex: 0xF0E2CB),
        card: Color(hex: 0xFFFBF2), tile: Color(hex: 0xF4E8D4), board: Color(hex: 0xFFFDF7),
        ink: Color(hex: 0x4A3728), inkSoft: Color(hex: 0x8C7662),
        accent: Color(hex: 0xC2603A), warm: Color(hex: 0xD9942F), fresh: Color(hex: 0x76946E)
    )

    static let sageGarden = Theme(
        isDark: false,
        backgroundTop: Color(hex: 0xF1F4E6), backgroundBottom: Color(hex: 0xDDE7CF),
        card: Color(hex: 0xFBFCF4), tile: Color(hex: 0xE7EEDB), board: Color(hex: 0xFDFEF8),
        ink: Color(hex: 0x2F3E30), inkSoft: Color(hex: 0x6C7F67),
        accent: Color(hex: 0x4F7D57), warm: Color(hex: 0xC8862F), fresh: Color(hex: 0xB5683F)
    )

    static let fireplace = Theme(
        isDark: true,
        backgroundTop: Color(hex: 0x321B14), backgroundBottom: Color(hex: 0x1A0E0B),
        card: Color(hex: 0x41251B), tile: Color(hex: 0x543024), board: Color(hex: 0x38201A),
        ink: Color(hex: 0xF8E6D2), inkSoft: Color(hex: 0xC59E84),
        accent: Color(hex: 0xF27F45), warm: Color(hex: 0xF4B550), fresh: Color(hex: 0xB3C088)
    )

    static let midnightCocoa = Theme(
        isDark: true,
        backgroundTop: Color(hex: 0x2E2622), backgroundBottom: Color(hex: 0x1C1715),
        card: Color(hex: 0x3B312C), tile: Color(hex: 0x4A3E38), board: Color(hex: 0x342B27),
        ink: Color(hex: 0xF1E6D8), inkSoft: Color(hex: 0xB5A494),
        accent: Color(hex: 0xE2906A), warm: Color(hex: 0xE4B366), fresh: Color(hex: 0x9FB591)
    )
}

/// The theme setting. "Automatic" follows the iPhone's light or dark appearance.
nonisolated enum ThemeChoice: String, CaseIterable, Identifiable, Sendable {
    case automatic, cozyCream, sageGarden, fireplace, midnightCocoa

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .cozyCream: "Cozy Cream"
        case .sageGarden: "Sage Garden"
        case .fireplace: "Fireplace"
        case .midnightCocoa: "Midnight Cocoa"
        }
    }

    func theme(for scheme: ColorScheme) -> Theme {
        switch self {
        case .automatic: scheme == .dark ? .midnightCocoa : .cozyCream
        case .cozyCream: .cozyCream
        case .sageGarden: .sageGarden
        case .fireplace: .fireplace
        case .midnightCocoa: .midnightCocoa
        }
    }

    /// Light or dark appearance forced by the theme, nil to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: nil
        case .cozyCream, .sageGarden: .light
        case .fireplace, .midnightCocoa: .dark
        }
    }
}

extension Color {
    nonisolated init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension EnvironmentValues {
    @Entry var theme = Theme.cozyCream
}

/// Applies the chosen theme to a whole screen (the app's root and every sheet).
private struct Themed: ViewModifier {
    @AppStorage(SettingsKey.theme) private var choice = ThemeChoice.automatic
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let theme = choice.theme(for: colorScheme)
        content
            .environment(\.theme, theme)
            .tint(theme.accent)
            .fontDesign(.rounded)
            .preferredColorScheme(choice.colorScheme)
    }
}

extension View {
    func themed() -> some View { modifier(Themed()) }

    /// The standard soft, rounded card.
    func card(padding: CGFloat = 18) -> some View { modifier(CardStyle(padding: padding)) }
}

private struct CardStyle: ViewModifier {
    @Environment(\.theme) private var theme
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: theme.shadow, radius: 14, y: 6)
    }
}

/// The soft paper-like backdrop used behind every screen.
struct ThemeBackground: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.backgroundTop, theme.backgroundBottom], startPoint: .top, endPoint: .bottom)
            // Two faint pools of warm light, like lamps in a cozy room.
            RadialGradient(
                colors: [theme.warm.opacity(theme.isDark ? 0.16 : 0.20), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 420
            )
            RadialGradient(
                colors: [theme.accent.opacity(theme.isDark ? 0.10 : 0.09), .clear],
                center: .bottomLeading, startRadius: 0, endRadius: 480
            )
        }
        .ignoresSafeArea()
    }
}

/// A big, friendly filled button.
struct CozyButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(prominent ? theme.onAccent : theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                prominent ? theme.accent : theme.accent.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The small label marking hardcore games.
struct HardcoreBadge: View {
    @Environment(\.theme) private var theme
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "eye.slash.fill")
            if !compact { Text("HARDCORE") }
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .foregroundStyle(theme.onAccent)
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, 3)
        .background(theme.ink.opacity(theme.isDark ? 1 : 0.85), in: Capsule())
        .accessibilityLabel("Hardcore")
    }
}

nonisolated enum TimeFormat {
    /// Clock style, e.g. "4:07" or "1:02:45".
    static func string(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600, minutes = (total / 60) % 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    /// Long durations, e.g. "12h 34m" or "34m".
    static func hoursAndMinutes(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
