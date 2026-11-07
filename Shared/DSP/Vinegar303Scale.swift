import Foundation

/// Musical scale data and trigger-time note quantization.
///
/// The interval table is immutable. `quantize` is a pure integer operation, so
/// it can be called from the note-trigger path without allocating or touching
/// the per-sample render loop.
public enum Vinegar303Scale {
    public static let keyNames = [
        "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
    ]

    public static let modeNames = [
        "Major",
        "Natural Minor",
        "Dorian",
        "Phrygian",
        "Lydian",
        "Mixolydian",
        "Locrian",
    ]

    /// Semitone offsets from the selected key root for each supported mode.
    public static let intervals: [[Int]] = [
        [0, 2, 4, 5, 7, 9, 11], // Major / Ionian
        [0, 2, 3, 5, 7, 8, 10], // Natural Minor / Aeolian
        [0, 2, 3, 5, 7, 9, 10], // Dorian
        [0, 1, 3, 5, 7, 8, 10], // Phrygian
        [0, 2, 4, 6, 7, 9, 11], // Lydian
        [0, 2, 4, 5, 7, 9, 10], // Mixolydian
        [0, 1, 3, 5, 6, 8, 10], // Locrian
    ]

    /// Returns the nearest in-scale MIDI note.
    ///
    /// Exact ties resolve upward. For example, F natural in E Minor is one
    /// semitone between E and F#, and therefore becomes F#.
    public static func quantize(note: Int, key: Int, mode: Int) -> Int {
        let root = wrapped12(key)
        let modeIndex = min(max(mode, 0), intervals.count - 1)
        let scaleIntervals = intervals[modeIndex]
        let relativePitchClass = wrapped12(wrapped12(note) - root)

        var bestNote = note
        var bestDistance = Int.max

        for interval in scaleIntervals {
            var delta = interval - relativePitchClass
            if delta > 6 {
                delta -= 12
            } else if delta < -6 {
                delta += 12
            }

            var candidate = note + delta
            // Keep the result inside the MIDI range. At the extreme edges this
            // may select the nearest valid scale note in the other octave.
            if candidate < 0 {
                candidate += 12
            } else if candidate > 127 {
                candidate -= 12
            }

            let distance = abs(candidate - note)
            if distance < bestDistance || (distance == bestDistance && candidate > bestNote) {
                bestNote = candidate
                bestDistance = distance
            }
        }

        return bestNote
    }

    @inline(__always)
    private static func wrapped12(_ value: Int) -> Int {
        ((value % 12) + 12) % 12
    }
}
