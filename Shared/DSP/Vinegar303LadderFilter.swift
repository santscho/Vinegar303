import Foundation

/// Four-pole transistor-ladder style low-pass filter.
///
/// Four cascaded topology-preserving one-pole sections with a saturating
/// feedback path. It behaves like the classic diode ladder: the resonance
/// thins the low end and tips into self-oscillation near maximum.
struct Vinegar303LadderFilter {
    private var s1: Float = 0
    private var s2: Float = 0
    private var s3: Float = 0
    private var s4: Float = 0
    private var lastOutput: Float = 0

    mutating func reset() {
        s1 = 0
        s2 = 0
        s3 = 0
        s4 = 0
        lastOutput = 0
    }

    mutating func process(
        _ input: Float,
        cutoff: Float,
        resonance: Float,
        sampleRate: Float
    ) -> Float {
        let nyquistLimit = sampleRate * 0.45
        let frequency = min(max(cutoff, 20), nyquistLimit)

        // Bilinear-pre-warped one-pole coefficient.
        let g = tanf(.pi * frequency / sampleRate)
        let onePole = g / (1 + g)

        // Feedback amount: ~4 is the self-oscillation threshold for four poles.
        // The reference starts adding audible resonance around 69 % of the
        // control range, so shape the lower half of the travel instead of
        // waiting until the knob reaches 100 %.
        let resonanceAmount = min(max(resonance, 0), 1)
        let feedback = 4.15 * powf(resonanceAmount, 0.65)

        // The one-sample delayed feedback keeps this cheap and stable while a
        // soft saturator supplies the acid character.
        let driven = tanhf(input * 1.15 - lastOutput * feedback)

        var v = (driven - s1) * onePole
        let y1 = v + s1
        s1 = y1 + v

        v = (y1 - s2) * onePole
        let y2 = v + s2
        s2 = y2 + v

        v = (y2 - s3) * onePole
        let y3 = v + s3
        s3 = y3 + v

        v = (y3 - s4) * onePole
        let y4 = v + s4
        s4 = y4 + v

        // Guard against denormals / numerical runaway at extreme settings.
        if !y4.isFinite || abs(y4) > 12 {
            reset()
            return 0
        }

        lastOutput = vinegarClamp(y4, -4, 4)

        // Ladder filters lose body as resonance rises; add a little back so the
        // 303 keeps its weight when squelching.
        let loss = 1 / (1 + feedback * 0.11)
        return y4 * loss
    }
}
