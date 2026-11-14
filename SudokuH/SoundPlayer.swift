import AVFoundation

/// Plays the optional quiet tap sounds. The tones are generated in code,
/// so the app doesn't need any audio files.
final class SoundPlayer {
    enum Sound: CaseIterable {
        case tap, error, success
    }

    static let shared = SoundPlayer()

    private var players: [Sound: AVAudioPlayer] = [:]
    private var isSessionConfigured = false

    func play(_ sound: Sound) {
        if !isSessionConfigured {
            // "Ambient" respects the silent switch and never interrupts music.
            try? AVAudioSession.sharedInstance().setCategory(.ambient)
            isSessionConfigured = true
        }
        if players[sound] == nil {
            let player = try? AVAudioPlayer(data: Self.wave(for: sound))
            player?.volume = 0.35
            player?.prepareToPlay()
            players[sound] = player
        }
        guard let player = players[sound] else { return }
        player.currentTime = 0
        player.play()
    }

    /// The notes of each sound: pitch (Hz), start (s) and length (s).
    private static func notes(for sound: Sound) -> [(frequency: Double, start: Double, length: Double)] {
        switch sound {
        case .tap: [(620, 0, 0.07)]
        case .error: [(180, 0, 0.16)]
        case .success: [(523, 0, 0.25), (659, 0.10, 0.25), (784, 0.20, 0.40)]
        }
    }

    /// Builds a small mono 16-bit WAV file in memory: soft sine tones that fade out quickly.
    private static func wave(for sound: Sound) -> Data {
        let sampleRate = 44_100.0
        let notes = notes(for: sound)
        let duration = notes.map { $0.start + $0.length }.max() ?? 0
        var samples = [Double](repeating: 0, count: Int(duration * sampleRate))
        for note in notes {
            let first = Int(note.start * sampleRate)
            let count = Int(note.length * sampleRate)
            for offset in 0..<count where first + offset < samples.count {
                let time = Double(offset) / sampleRate
                let attack = min(1, time / 0.004)
                let decay = exp(-time * 5 / note.length)
                samples[first + offset] += sin(2 * .pi * note.frequency * time) * attack * decay * 0.5
            }
        }

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        append(36 + byteCount)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))            // size of the format block
        append(UInt16(1))             // PCM
        append(UInt16(1))             // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate) * 2) // bytes per second
        append(UInt16(2))             // bytes per sample
        append(UInt16(16))            // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(byteCount)
        for sample in samples {
            append(Int16(max(-1, min(1, sample)) * Double(Int16.max)))
        }
        return data
    }
}
