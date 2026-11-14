import SwiftUI

struct BoardView: View {
    let game: GameState
    let selected: Int?
    /// Hides all digits (used while paused).
    var concealed = false
    /// Per-cell counters: a cell plays the completion animation when its counter changes,
    /// after waiting its entry in `pulseDelays`.
    var pulses: [Int] = []
    var pulseDelays: [Double] = []
    /// The hint being explained: its cells are highlighted instead of the selection.
    var hint: Hint?
    var largeDigits = false
    let onSelect: (Int) -> Void

    @Environment(\.theme) private var theme

    /// Hardcore games show no help at all while they are being played.
    private var assists: Bool { !game.isHardcore || game.status != .playing }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let cell = side / 9
            let selectedValue = assists ? (selected.map { game.values[$0] } ?? 0) : 0
            let hintPattern = Set(hint?.patternCells ?? [])
            let hintRegion = Set(hint?.regionCells ?? [])

            VStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<9, id: \.self) { column in
                            let index = row * 9 + column
                            CellView(
                                value: concealed ? 0 : game.values[index],
                                notes: concealed ? 0 : game.notes[index],
                                isGiven: game.isGiven(index),
                                isMistake: assists && game.isMistake(index),
                                highlightedDigit: selectedValue,
                                background: concealed ? .clear : background(
                                    for: index, selectedValue: selectedValue, pattern: hintPattern, region: hintRegion
                                ),
                                ink: theme.ink,
                                digitScale: largeDigits ? 0.78 : 0.62,
                                pulse: pulses.indices.contains(index) ? pulses[index] : 0,
                                pulseDelay: pulseDelays.indices.contains(index) ? pulseDelays[index] : 0,
                                size: cell
                            )
                            .overlay {
                                if !concealed, hint?.cell == index {
                                    RoundedRectangle(cornerRadius: cell * 0.16, style: .continuous)
                                        .strokeBorder(theme.accent, lineWidth: 3)
                                        .padding(1.5)
                                }
                            }
                            .onTapGesture { onSelect(index) }
                            .accessibilityElement()
                            .accessibilityLabel(accessibilityLabel(for: index))
                            .accessibilityAddTraits(index == selected ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .background(theme.board)
            .overlay { GridLines(color: theme.ink).allowsHitTesting(false) }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(theme.ink.opacity(0.8), lineWidth: 2)
            }
            .shadow(color: theme.shadow, radius: 12, y: 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func background(for index: Int, selectedValue: Int, pattern: Set<Int>, region: Set<Int>) -> Color {
        if let hint {
            if index == hint.cell { return theme.accent.opacity(0.22) }
            if pattern.contains(index) { return theme.warm.opacity(0.45) }
            if region.contains(index) { return theme.fresh.opacity(0.20) }
            return .clear
        }
        guard let selected else { return .clear }
        if index == selected {
            return theme.accent.opacity(0.32)
        }
        guard assists else { return .clear }
        if selectedValue != 0 && game.values[index] == selectedValue {
            return theme.accent.opacity(0.18)
        }
        if BoardGeometry.arePeers(index, selected) {
            return theme.ink.opacity(0.07)
        }
        return .clear
    }

    private func accessibilityLabel(for index: Int) -> String {
        let position = "Row \(index / 9 + 1), column \(index % 9 + 1)"
        if concealed { return position }
        let value = game.values[index]
        if value == 0 { return "\(position), empty" }
        if assists && game.isMistake(index) { return "\(position), \(value), incorrect" }
        return "\(position), \(value)"
    }
}

private struct CellView: View {
    let value: Int
    let notes: UInt16
    let isGiven: Bool
    let isMistake: Bool
    let highlightedDigit: Int
    let background: Color
    let ink: Color
    let digitScale: CGFloat
    let pulse: Int
    let pulseDelay: Double
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct PulseValues {
        var scale: CGFloat = 1
        var flash: Double = 0
    }

    var body: some View {
        KeyframeAnimator(initialValue: PulseValues(), trigger: pulse) { animated in
            ZStack {
                background
                if isMistake && value != 0 {
                    Color.red.opacity(0.14)
                }
                Color.accentColor.opacity(animated.flash)
                if value != 0 {
                    Text("\(value)")
                        .font(.system(size: size * digitScale, weight: isGiven ? .medium : .regular, design: .rounded))
                        .foregroundStyle(isMistake ? Color.red : isGiven ? ink : Color.accentColor)
                        .scaleEffect(reduceMotion ? 1 : animated.scale)
                } else if notes != 0 {
                    notesGrid
                }
            }
        } keyframes: { _ in
            // Each track first holds still for the cell's delay, so the effect ripples outwards.
            KeyframeTrack(\.scale) {
                LinearKeyframe(1, duration: pulseDelay + 0.01)
                SpringKeyframe(1.35, duration: 0.16)
                SpringKeyframe(1, duration: 0.4)
            }
            KeyframeTrack(\.flash) {
                LinearKeyframe(0, duration: pulseDelay + 0.01)
                LinearKeyframe(0.4, duration: 0.12)
                LinearKeyframe(0, duration: 0.45)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
    }

    private var notesGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(1..<4, id: \.self) { column in
                        let digit = row * 3 + column
                        let isHighlighted = digit == highlightedDigit
                        Text("\(digit)")
                            .font(.system(size: size * (digitScale > 0.7 ? 0.29 : 0.25), weight: isHighlighted ? .bold : .regular, design: .rounded))
                            .foregroundStyle(isHighlighted ? Color.accentColor : ink.opacity(0.6))
                            .frame(width: size / 3.3, height: size / 3.3)
                            .opacity(notes & (1 << UInt16(digit - 1)) != 0 ? 1 : 0)
                    }
                }
            }
        }
    }
}

private struct GridLines: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let cell = size.width / 9
            for thick in [false, true] {
                var path = Path()
                for line in 1..<9 where (line % 3 == 0) == thick {
                    let position = CGFloat(line) * cell
                    path.move(to: CGPoint(x: position, y: 0))
                    path.addLine(to: CGPoint(x: position, y: size.height))
                    path.move(to: CGPoint(x: 0, y: position))
                    path.addLine(to: CGPoint(x: size.width, y: position))
                }
                context.stroke(
                    path,
                    with: .color(color.opacity(thick ? 0.8 : 0.2)),
                    lineWidth: thick ? 1.5 : 0.5
                )
            }
        }
    }
}
