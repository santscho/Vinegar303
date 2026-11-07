import Foundation

/// Exponential T60 decay envelope with an instantaneous trigger.
///
/// The filter envelope of a 303 is a decay-only contour; the accent step simply
/// pushes it higher. `coefficient` is set once per render block from the Decay
/// parameter, then `process()` is a single multiply per sample. The labelled
/// time is the time to fall by 60 dB, which makes the control readout agree
/// with the audible decay instead of stopping at only −8.7 dB.
struct Vinegar303DecayEnvelope {
    private(set) var value: Float = 0
    private var coefficient: Float = 0

    mutating func configure(seconds: Double, sampleRate: Double) {
        let time = max(seconds, 0.005)
        coefficient = Float(exp(-6.907755278982137 / (time * max(sampleRate, 1))))
    }

    mutating func trigger(_ amount: Float = 1) {
        value = max(amount, 0)
    }

    mutating func reset() {
        value = 0
    }

    @inline(__always)
    mutating func process() -> Float {
        value *= coefficient
        if value < 0.000001 {
            value = 0
        }
        return value
    }
}
