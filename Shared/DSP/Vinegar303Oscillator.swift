import Foundation

/// Band-limited saw / square oscillator using PolyBLEP.
///
/// The TB-303 has a single oscillator with a saw and a square position. We
/// implement both shapes with a polynomial band-limited step so that high
/// notes do not fold down into audible aliasing.
struct Vinegar303Oscillator {
    private static let squareDuty = 0.488
    private static let squareSecondHarmonic = 0.202

    private var phase: Double = 0

    mutating func reset(phase: Double = 0) {
        self.phase = phase.truncatingRemainder(dividingBy: 1)
    }

    mutating func next(frequency: Double, sampleRate: Double, waveform: Vinegar303Waveform) -> Float {
        let increment = max(0, min(frequency / max(sampleRate, 1), 0.45))

        let saw = 2.0 * phase - 1.0 - Self.polyBLEP(phase, increment)
        let squarePhase = (phase + (1.0 - Self.squareDuty)).truncatingRemainder(dividingBy: 1)
        var square = (phase < Self.squareDuty ? 1.0 : -1.0)
            + Self.polyBLEP(phase, increment)
            - Self.polyBLEP(squarePhase, increment)

        // The reference square is not a perfect 50 % pulse: its even-order
        // content is stronger than the measured duty error alone explains.
        // Add a small, band-limited second harmonic so the square keeps the
        // asymmetric edge character instead of sounding like a mathematically
        // ideal pulse.
        if 2.0 * frequency < sampleRate * 0.48 {
            square += Self.squareSecondHarmonic * sin(4.0 * .pi * phase)
        }

        let value = waveform == .saw ? saw : square

        phase += increment
        if phase >= 1 {
            phase -= 1
        }

        return Float(value) * 0.7
    }

    @inline(__always)
    private static func polyBLEP(_ t: Double, _ dt: Double) -> Double {
        guard dt > 0 else { return 0 }
        if t < dt {
            let x = t / dt
            return x + x - x * x - 1.0
        }
        if t > 1.0 - dt {
            let x = (t - 1.0) / dt
            return x * x + x + x + 1.0
        }
        return 0
    }
}
