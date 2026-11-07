import Foundation

// MARK: - Shared musical types
//
// These types describe the *behaviour* of a 303-style bassline: a monophonic
// voice driven by a 16-step sequencer whose steps carry gate, accent and slide
// flags. Everything here is original clean-room code.

public enum Vinegar303Waveform: Int, CaseIterable {
    case square = 0
    case saw = 1
}

public struct Vinegar303Step: Equatable {
    public var note: Int
    public var gate: Bool
    public var accent: Bool
    public var slide: Bool

    public init(note: Int = 33, gate: Bool = true, accent: Bool = false, slide: Bool = false) {
        self.note = Vinegar303Step.clampNote(note)
        self.gate = gate
        self.accent = accent
        self.slide = slide
    }

    public static func clampNote(_ note: Int) -> Int {
        min(max(note, Vinegar303PatternLibrary.lowestNote), Vinegar303PatternLibrary.highestNote)
    }

    public static let rest = Vinegar303Step(note: 33, gate: false)
}

public struct Vinegar303Pattern: Equatable {
    public var steps: [Vinegar303Step]
    /// Each pattern owns its playback length. The AU's `patternLength`
    /// parameter mirrors the selected pattern's length for hosts and the UI.
    public var length: Int

    public init(steps: [Vinegar303Step], length: Int = Vinegar303PatternLibrary.stepsPerPattern) {
        self.steps = steps
        self.length = min(max(length, 1), Vinegar303PatternLibrary.stepsPerPattern)
    }

    public static func empty() -> Vinegar303Pattern {
        Vinegar303Pattern(steps: Array(repeating: .rest, count: Vinegar303PatternLibrary.stepsPerPattern))
    }

    public subscript(index: Int) -> Vinegar303Step {
        get {
            guard steps.indices.contains(index) else { return .rest }
            return steps[index]
        }
        set {
            guard steps.indices.contains(index) else { return }
            steps[index] = newValue
        }
    }
}

public enum Vinegar303PatternLibrary {
    public static let patternCount = 16
    public static let stepsPerPattern = 16
    public static let lowestNote = 24   // C1
    public static let highestNote = 60  // C4

    /// A complete original factory bank. Patterns are ordinary musical data
    /// and are stored with the AU state so hosts can recall them.
    ///
    /// The voicings follow common 303 practice: a repeated root anchors the
    /// groove, octave and fifth jumps provide movement, and accents and slides
    /// are placed on gated steps. The lines are original; they are not
    /// transcriptions of commercial patterns.
    public static func factory() -> [Vinegar303Pattern] {
        var bank = (0..<patternCount).map { _ in Vinegar303Pattern.empty() }

        bank[0] = pattern(
            notes: [33, 33, 45, 33, 36, 33, 45, 33, 33, 40, 33, 45, 36, 33, 48, 43],
            accents: [0, 3, 6, 10, 14],
            slides: [2, 8, 12]
        )

        bank[1] = pattern(
            notes: [33, 45, 33, 36, 33, 33, 48, 45, 33, 36, 33, 40, 45, 33, 36, 33],
            accents: [1, 5, 9, 13],
            slides: [4, 10],
            rests: [7, 15]
        )

        bank[2] = pattern(
            notes: [36, 36, 48, 36, 39, 36, 48, 36, 36, 43, 36, 48, 39, 36, 51, 46],
            accents: [0, 7, 8, 15],
            slides: [3, 11, 14]
        )

        bank[3] = pattern(
            notes: [33, 40, 45, 33, 43, 33, 50, 45, 33, 38, 45, 33, 36, 43, 48, 40],
            accents: [2, 6, 9, 12],
            slides: [1, 5, 9, 13],
            rests: [4, 11]
        )

        // 05 · A minor root pulse
        bank[4] = pattern(
            notes: [33, 33, 45, 33, 33, 45, 33, 36, 33, 33, 45, 33, 43, 33, 45, 36],
            accents: [0, 4, 8, 12],
            slides: [2, 10, 13],
            rests: [7, 15]
        )

        // 06 · A minor roller with a looping slide
        bank[5] = pattern(
            notes: [33, 36, 33, 45, 33, 36, 45, 33, 33, 40, 33, 45, 36, 33, 43, 45],
            accents: [1, 5, 9, 13],
            slides: [3, 7, 11, 15],
            rests: [2, 10]
        )

        // 07 · C minor stomp
        bank[6] = pattern(
            notes: [36, 36, 48, 36, 39, 36, 48, 36, 36, 43, 36, 48, 39, 36, 46, 43],
            accents: [0, 3, 6, 10, 14],
            slides: [2, 8, 12, 15],
            rests: [7, 11]
        )

        // 08 · C minor offbeat
        bank[7] = pattern(
            notes: [36, 48, 36, 39, 36, 43, 36, 48, 36, 39, 36, 46, 36, 48, 43, 39],
            accents: [0, 4, 8, 12],
            slides: [2, 7, 11, 15],
            rests: [1, 5, 9, 13]
        )

        // 09 · E minor drive
        bank[8] = pattern(
            notes: [40, 40, 52, 40, 43, 40, 47, 40, 40, 52, 40, 47, 45, 40, 52, 43],
            accents: [0, 4, 8, 12],
            slides: [1, 5, 9, 13],
            rests: [3, 11]
        )

        // 10 · E minor high-register answers
        bank[9] = pattern(
            notes: [40, 43, 40, 52, 40, 47, 43, 40, 40, 45, 40, 52, 43, 40, 47, 45],
            accents: [1, 5, 9, 13],
            slides: [3, 7, 8, 15],
            rests: [6, 12]
        )

        // 11 · G minor bounce
        bank[10] = pattern(
            notes: [43, 43, 55, 43, 46, 43, 50, 43, 43, 55, 43, 50, 48, 43, 55, 46],
            accents: [0, 4, 8, 12],
            slides: [2, 5, 10, 13],
            rests: [7, 15]
        )

        // 12 · G minor turnaround
        bank[11] = pattern(
            notes: [43, 46, 43, 55, 43, 50, 43, 46, 43, 55, 43, 50, 48, 43, 55, 46],
            accents: [1, 4, 9, 13],
            slides: [1, 3, 7, 15],
            rests: [5, 12]
        )

        // 13 · D minor pulse
        bank[12] = pattern(
            notes: [38, 38, 50, 38, 41, 38, 45, 38, 38, 50, 38, 45, 43, 38, 50, 41],
            accents: [0, 4, 8, 12],
            slides: [2, 5, 10, 13],
            rests: [7, 15]
        )

        // 14 · F minor high-register line
        bank[13] = pattern(
            notes: [41, 53, 41, 56, 41, 53, 44, 41, 41, 53, 51, 41, 44, 53, 56, 51],
            accents: [0, 3, 6, 10, 14],
            slides: [1, 5, 9, 13],
            rests: [7, 15]
        )

        // 15 · A minor acid-house shuffle
        bank[14] = pattern(
            notes: [33, 33, 33, 45, 33, 36, 33, 45, 33, 33, 43, 33, 45, 36, 33, 45],
            accents: [0, 4, 8, 12],
            slides: [3, 5, 9, 14],
            rests: [2, 7, 11]
        )

        // 16 · C minor finale
        bank[15] = pattern(
            notes: [36, 39, 36, 48, 36, 43, 39, 36, 36, 48, 36, 43, 39, 48, 46, 43],
            accents: [0, 4, 8, 12],
            slides: [2, 5, 10, 13],
            rests: [7, 15]
        )

        return bank
    }

    public static func noteName(for midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let clamped = min(max(midi, 0), 127)
        let octave = clamped / 12 - 1
        return names[clamped % 12] + "\(octave)"
    }

    private static func pattern(
        notes: [Int],
        accents: [Int],
        slides: [Int],
        rests: [Int] = []
    ) -> Vinegar303Pattern {
        var steps = [Vinegar303Step]()
        steps.reserveCapacity(stepsPerPattern)
        for index in 0..<stepsPerPattern {
            let note = notes.indices.contains(index) ? notes[index] : 33
            steps.append(
                Vinegar303Step(
                    note: note,
                    gate: !rests.contains(index),
                    accent: accents.contains(index),
                    slide: slides.contains(index)
                )
            )
        }
        return Vinegar303Pattern(steps: steps)
    }
}

// MARK: - Small numeric helpers

@inline(__always)
func vinegarClamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
}

@inline(__always)
func fourCharCode(_ string: String) -> UInt32 {
    var result: UInt32 = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) | (scalar.value & 0xFF)
    }
    return result
}
