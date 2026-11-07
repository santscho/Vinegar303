import AudioToolbox
import Foundation

/// The complete monophonic acid voice + 16-step sequencer.
///
/// Realtime contract:
/// - All storage is allocated once in `init`, never in `render`.
/// - `render` performs no allocation, locking, logging or ARC traffic on
///   engine-owned reference types.
/// - UI writes go through `setParameter` / `patterns` and are consumed on the
///   next render quantum.
public final class Vinegar303Engine {
    public static let maxParameters = 160
    public static let maxPatterns = Vinegar303PatternLibrary.patternCount
    public static let stepsPerPattern = Vinegar303PatternLibrary.stepsPerPattern

    // Parameter mirror. Written by the control thread, read by the audio thread.
    private let parameterStorage: UnsafeMutablePointer<Float>

    // Double-buffered pattern banks. Edits are written to the inactive bank and
    // published by flipping `activeBank`, so the render thread never observes a
    // half-written pattern.
    private let bankA: UnsafeMutablePointer<Vinegar303Step>
    private let bankB: UnsafeMutablePointer<Vinegar303Step>
    private let bankALengths: UnsafeMutablePointer<Int32>
    private let bankBLengths: UnsafeMutablePointer<Int32>
    private var activeBank: Int32 = 0

    private var sampleRate: Double = 44_100
    private var prepared = false

    // Publically readable playhead (-1 when stopped).
    private var playheadStorage: Int32 = -1
    public var playheadStep: Int {
        Int(playheadStorage)
    }

    // Sequencer-only gate state for standalone Launchkey pad feedback. This is
    // kept separate from the voice gate so held keyboard notes do not suppress
    // the pattern LEDs.
    private var patternGateOpen = false
    private var patternGateClosePhase: Double = 0.5

    /// True while the current sequencer step's gate is open.
    public var sequencerGateOpen: Bool {
        patternGateOpen
    }

    // MARK: Voice state

    private var oscillator = Vinegar303Oscillator()
    private var filter = Vinegar303LadderFilter()
    private var filterEnvelope = Vinegar303DecayEnvelope()
    private var accentFilterEnvelope = Vinegar303DecayEnvelope()
    private var delayUnits = Array(repeating: Vinegar303DelayUnit(), count: Vinegar303FXSlot.count)
    private var delayUnitActive = Array(repeating: false, count: Vinegar303FXSlot.count)

    private var amplitude: Float = 0
    private var amplitudeAttackActive = false
    private var amplitudeAttackRate: Float = 0
    private var amplitudeDecayCoefficient: Float = 0
    private var amplitudeReleaseCoefficient: Float = 0
    private var gateOpen = false

    private var currentNote: Double = 33
    private var targetNote: Double = 33
    private var glideActive = false
    private var accentVCAValue: Float = 0
    private var accentVCADecayCoefficient: Float = 0
    private var manualNote: Int?

    private var stepIndex = 0
    private var stepSampleCounter: Double = 0
    private var gateClosePhase: Double = 0.5
    private var sequencerWasRunning = false
    private var hostSyncWasActive = false

    // MARK: Smoothed control values

    private var smoothedCutoff: Float = 520
    private var smoothedResonance: Float = 0.25
    private var smoothedVolume: Float = 0.4
    private var smoothedTuningCents: Float = 0
    private var smoothedDrive: Float = 0
    private var smoothedDistortion: Float = 0
    private var smoothedEnvAmount: Float = 0.45

    private var glideCoefficient: Double = 0
    private var driveHighPassState: Float = 0
    private var driveHighPassCoefficient: Float = 0
    private var dcInput: Float = 0
    private var dcOutput: Float = 0

    // MARK: Lifecycle

    public init() {
        parameterStorage = .allocate(capacity: Self.maxParameters)
        parameterStorage.initialize(repeating: 0, count: Self.maxParameters)

        let patternCapacity = Self.maxPatterns * Self.stepsPerPattern
        bankA = .allocate(capacity: patternCapacity)
        bankA.initialize(repeating: Vinegar303Step(), count: patternCapacity)
        bankB = .allocate(capacity: patternCapacity)
        bankB.initialize(repeating: Vinegar303Step(), count: patternCapacity)
        bankALengths = .allocate(capacity: Self.maxPatterns)
        bankALengths.initialize(repeating: Int32(Self.stepsPerPattern), count: Self.maxPatterns)
        bankBLengths = .allocate(capacity: Self.maxPatterns)
        bankBLengths.initialize(repeating: Int32(Self.stepsPerPattern), count: Self.maxPatterns)

        for spec in Vinegar303ParameterCatalog.all {
            parameterStorage[Int(spec.id.rawValue)] = spec.defaultValue
        }
        publishPatterns(Vinegar303PatternLibrary.factory())
    }

    deinit {
        parameterStorage.deinitialize(count: Self.maxParameters)
        parameterStorage.deallocate()

        let capacity = Self.maxPatterns * Self.stepsPerPattern
        bankA.deinitialize(count: capacity)
        bankA.deallocate()
        bankB.deinitialize(count: capacity)
        bankB.deallocate()

        bankALengths.deinitialize(count: Self.maxPatterns)
        bankALengths.deallocate()
        bankBLengths.deinitialize(count: Self.maxPatterns)
        bankBLengths.deallocate()

        for index in delayUnits.indices {
            delayUnits[index].deallocate()
        }
    }

    // MARK: Parameters

    @inline(__always)
    private func p(_ id: Vinegar303Parameter) -> Float {
        parameterStorage[Int(id.rawValue)]
    }

    public func parameter(_ id: Vinegar303Parameter) -> AUValue {
        p(id)
    }

    public func setParameter(_ id: Vinegar303Parameter, _ value: AUValue) {
        let snapped = Vinegar303ParameterCatalog.spec(id).snapped(value)
        parameterStorage[Int(id.rawValue)] = snapped
        updateSelectedPatternLengthIfNeeded(id: id, value: snapped)
    }

    public func setParameter(address: AUParameterAddress, value: AUValue) {
        let index = Int(address)
        guard index > 0,
              index < Self.maxParameters,
              let id = Vinegar303Parameter(rawValue: address) else { return }
        let snapped = Vinegar303ParameterCatalog.spec(id).snapped(value)
        parameterStorage[index] = snapped
        updateSelectedPatternLengthIfNeeded(id: id, value: snapped)
    }

    private func updateSelectedPatternLengthIfNeeded(id: Vinegar303Parameter, value: AUValue) {
        guard id == .patternLength else { return }
        let patternIndex = Int(parameterStorage[Int(Vinegar303Parameter.pattern.rawValue)].rounded())
        setActivePatternLength(Int(value.rounded()), at: patternIndex)
    }

    public func parameter(address: AUParameterAddress) -> AUValue {
        let index = Int(address)
        guard index > 0, index < Self.maxParameters else { return 0 }
        return parameterStorage[index]
    }

    public func applyParameterDefaults() {
        for spec in Vinegar303ParameterCatalog.all {
            parameterStorage[Int(spec.id.rawValue)] = spec.defaultValue
        }
    }

    // MARK: Patterns

    public var patterns: [Vinegar303Pattern] {
        get {
            let source = activeBank == 0 ? bankA : bankB
            let sourceLengths = activeBank == 0 ? bankALengths : bankBLengths
            var result = [Vinegar303Pattern]()
            result.reserveCapacity(Self.maxPatterns)
            for patternIndex in 0..<Self.maxPatterns {
                var steps = [Vinegar303Step]()
                steps.reserveCapacity(Self.stepsPerPattern)
                for step in 0..<Self.stepsPerPattern {
                    steps.append(source[patternIndex * Self.stepsPerPattern + step])
                }
                result.append(
                    Vinegar303Pattern(
                        steps: steps,
                        length: Int(sourceLengths[patternIndex])
                    )
                )
            }
            return result
        }
        set {
            publishPatterns(newValue)
        }
    }

    /// Read the active bank's stored length without allocating. Used by the
    /// parameter observer when the host changes the selected pattern.
    public func patternLength(at index: Int) -> Int? {
        guard index >= 0, index < Self.maxPatterns else { return nil }
        let lengths = activeBank == 0 ? bankALengths : bankBLengths
        return Int(lengths[index])
    }

    /// Update the active bank's stored length without reallocating. This keeps
    /// a host-automated `patternLength` attached to the selected pattern so
    /// state recall does not revert it.
    public func setActivePatternLength(_ length: Int, at index: Int) {
        guard index >= 0, index < Self.maxPatterns else { return }
        let clamped = min(max(length, 1), Self.stepsPerPattern)
        let lengths = activeBank == 0 ? bankALengths : bankBLengths
        lengths[index] = Int32(clamped)
    }

    private func publishPatterns(_ newPatterns: [Vinegar303Pattern]) {
        let target = activeBank == 0 ? bankB : bankA
        let targetLengths = activeBank == 0 ? bankBLengths : bankALengths
        for patternIndex in 0..<Self.maxPatterns {
            let pattern = newPatterns.indices.contains(patternIndex) ? newPatterns[patternIndex] : .empty()
            targetLengths[patternIndex] = Int32(pattern.length)
            for stepIndex in 0..<Self.stepsPerPattern {
                target[patternIndex * Self.stepsPerPattern + stepIndex] = pattern[stepIndex]
            }
        }
        activeBank = activeBank == 0 ? 1 : 0
    }

    // MARK: Preparation

    public func prepare(sampleRate: Double) {
        self.sampleRate = max(sampleRate, 8_000)
        prepared = true

        oscillator.reset()
        filter.reset()
        filterEnvelope.reset()
        filterEnvelope.configure(seconds: 0.3, sampleRate: self.sampleRate)
        accentFilterEnvelope.reset()
        accentFilterEnvelope.configure(seconds: 0.18, sampleRate: self.sampleRate)
        accentVCAValue = 0
        accentVCADecayCoefficient = Float(exp(-1.0 / (0.045 * self.sampleRate)))
        driveHighPassCoefficient = Float(1.0 - exp(-2.0 * Double.pi * 320.0 / self.sampleRate))

        amplitude = 0
        amplitudeAttackActive = false
        amplitudeAttackRate = Float(1.0 / (0.0022 * self.sampleRate))
        amplitudeDecayCoefficient = Float(exp(-1.0 / (0.34 * self.sampleRate)))
        amplitudeReleaseCoefficient = Float(exp(-1.0 / (0.045 * self.sampleRate)))
        glideCoefficient = 1.0 - exp(-1.0 / (0.030 * self.sampleRate))

        gateOpen = false
        patternGateOpen = false
        patternGateClosePhase = 0.5
        glideActive = false
        manualNote = nil
        stepIndex = 0
        stepSampleCounter = 0
        sequencerWasRunning = false
        hostSyncWasActive = false
        playheadStorage = -1

        smoothedCutoff = p(.cutoff)
        smoothedResonance = min(max(p(.resonance) / 100, 0), 1)
        smoothedVolume = powf(10, p(.volume) / 20)
        smoothedTuningCents = p(.tuning)
        smoothedDrive = p(.drive)
        smoothedDistortion = p(.distortion) / 100
        smoothedEnvAmount = p(.envmod) / 100

        driveHighPassState = 0
        dcInput = 0
        dcOutput = 0

        for index in delayUnits.indices {
            delayUnits[index].prepare(sampleRate: self.sampleRate)
            delayUnitActive[index] = false
        }
    }

    public func reset() {
        prepare(sampleRate: sampleRate)
    }

    // MARK: MIDI (audio thread only)

    public func handleMIDI(bytes: (UInt8, UInt8, UInt8), length: Int) {
        guard length >= 2 else { return }
        switch bytes.0 & 0xF0 {
        case 0x90:
            if bytes.2 == 0 {
                noteOff(midi: Int(bytes.1))
            } else {
                noteOn(midi: Int(bytes.1), velocity: Int(bytes.2))
            }
        case 0x80:
            noteOff(midi: Int(bytes.1))
        case 0xB0:
            // All Notes Off / All Sound Off.
            if bytes.1 == 123 || bytes.1 == 120 {
                manualNote = nil
                gateOpen = false
            }
        default:
            break
        }
    }

    public func noteOn(midi: Int, velocity: Int) {
        // A second note while the first is still gated is a legato slide: keep
        // the running envelope and glide to the new pitch instead of retriggering.
        let legato = gateOpen && manualNote != nil
        manualNote = midi
        gateOpen = true
        gateClosePhase = 1.0
        trigger(note: Double(midi), accent: velocity >= 110, glide: legato)
    }

    public func noteOff(midi: Int) {
        guard manualNote == midi else { return }
        manualNote = nil
        gateOpen = false
    }

    // MARK: Rendering

    /// Renders `frames` samples into `outputData`, starting at `frameOffset`.
    /// Called only from the audio thread, possibly several times per render
    /// quantum when MIDI events split the block.
    public func render(
        into outputData: UnsafeMutablePointer<AudioBufferList>,
        frames: Int,
        frameOffset: Int,
        hostTempo: Double?,
        hostPlaying: Bool?,
        hostSamplePosition: Double? = nil,
        hostBeatPosition: Double? = nil
    ) {
        guard frames > 0 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(outputData)

        guard prepared else {
            silence(buffers: buffers, frames: frames, frameOffset: frameOffset)
            return
        }

        let sr = sampleRate
        let baseTempo = min(max(hostTempo ?? Double(p(.tempo)), 20), 300)
        let halfSpeed = p(.halfSpeed) >= 0.5
        let tempoScale = halfSpeed ? 0.5 : 1.0
        let tempo = baseTempo * tempoScale
        let syncEnabled = p(.sync) >= 0.5
        let patternMode = p(.midiMode) < 0.5
        let runEnabled = p(.run) >= 0.5
        let hostRunning = hostPlaying == true
        let patternLength = vinegarClamp(Int(p(.patternLength).rounded()), 1, Self.stepsPerPattern)
        let patternIndex = vinegarClamp(Int(p(.pattern).rounded()), 0, Self.maxPatterns - 1)
        let samplesPerStep = max(1.0, sr * 60.0 / (tempo * 4.0))

        // When host transport state is available, Host sync is authoritative:
        // Run is left over from Free mode and must not override a host stop.
        // Without a transport callback, Run remains the manual fallback.
        let hostTransportAvailable = hostPlaying != nil
        let hostSyncActive = patternMode && syncEnabled && hostRunning
        let hostSyncStarted = hostSyncActive && !hostSyncWasActive
        let hostControlledRun = hostTransportAvailable ? hostRunning : runEnabled
        let sequencerRunning = patternMode && (syncEnabled ? hostControlledRun : runEnabled)

        if hostSyncStarted {
            // Re-entering Host mode during playback must pick up the host's
            // current musical position instead of continuing the Free phase.
            let hostStepPosition: Double?
            if let samplePosition = hostSamplePosition, samplePosition.isFinite {
                hostStepPosition = samplePosition / samplesPerStep
            } else if let beatPosition = hostBeatPosition, beatPosition.isFinite {
                hostStepPosition = beatPosition * 4.0 * tempoScale
            } else {
                hostStepPosition = nil
            }

            if let hostStepPosition {
                alignSequence(
                    toStepPosition: hostStepPosition,
                    patternIndex: patternIndex,
                    length: patternLength,
                    samplesPerStep: samplesPerStep
                )
            } else {
                startSequence()
            }
        } else if sequencerRunning && !sequencerWasRunning {
            startSequence()
        } else if !sequencerRunning && sequencerWasRunning {
            stopSequence()
        }
        sequencerWasRunning = sequencerRunning
        hostSyncWasActive = hostSyncActive

        let smoothing = Float(1.0 - exp(-1.0 / (0.008 * sr)))
        let cutoffTarget = max(p(.cutoff), 20)
        let resonanceTarget = min(max(p(.resonance) / 100, 0), 1)
        let volumeTarget = powf(10, p(.volume) / 20)
        let tuningTarget = p(.tuning)
        let scaleEnabled = p(.scaleEnable) >= 0.5
        let pitchTranspose = scaleEnabled
            ? 0
            : vinegarClamp(Int(p(.pitchTranspose).rounded()), -12, 12)
        let driveTarget = max(p(.drive), 0)
        let distortionTarget = min(max(p(.distortion) / 100, 0), 1)
        let envTarget = min(max(p(.envmod) / 100, 0), 1)

        let decayMilliseconds = Double(min(max(p(.decay), 40), 1_600))
        filterEnvelope.configure(seconds: decayMilliseconds / 1_000.0, sampleRate: sr)

        let waveform: Vinegar303Waveform = p(.waveform) >= 0.5 ? .saw : .square
        let accentAmount = min(max(p(.accent) / 100, 0), 1)

        for frame in 0..<frames {
            if sequencerRunning {
                // Sample-domain accumulator: subtract a whole step instead of
                // resetting, so fractional remainders carry across steps and
                // long runs do not accumulate tempo drift. The step index
                // itself stays strictly integer.
                stepSampleCounter += 1.0
                while stepSampleCounter >= samplesPerStep {
                    stepSampleCounter -= samplesPerStep
                    advanceStep(patternIndex: patternIndex, length: patternLength)
                }
                if patternGateOpen
                    && stepSampleCounter >= samplesPerStep * patternGateClosePhase {
                    patternGateOpen = false
                }
                if gateOpen && manualNote == nil
                    && stepSampleCounter >= samplesPerStep * gateClosePhase {
                    gateOpen = false
                }
            }

            // Control-rate smoothing (still per sample for zipper-free sweeps).
            smoothedCutoff += (cutoffTarget - smoothedCutoff) * smoothing
            smoothedResonance += (resonanceTarget - smoothedResonance) * smoothing
            smoothedVolume += (volumeTarget - smoothedVolume) * smoothing
            smoothedTuningCents += (tuningTarget - smoothedTuningCents) * smoothing
            smoothedDrive += (driveTarget - smoothedDrive) * smoothing
            smoothedDistortion += (distortionTarget - smoothedDistortion) * smoothing
            smoothedEnvAmount += (envTarget - smoothedEnvAmount) * smoothing

            let currentDriveGain = powf(10, smoothedDrive / 20)

            if glideActive {
                currentNote += (targetNote - currentNote) * glideCoefficient
            } else {
                currentNote = targetNote
            }

            let note = currentNote
                + Double(pitchTranspose)
                + Double(smoothedTuningCents) / 100.0
            let frequency = 440.0 * exp2((note - 69.0) / 12.0)

            let oscillatorSample = oscillator.next(
                frequency: frequency,
                sampleRate: sr,
                waveform: waveform
            )

            let filterEnvelopeValue = filterEnvelope.process()
            let accentFilterValue = accentFilterEnvelope.process()
            let modulatedCutoff = smoothedCutoff
                * exp2f(
                    filterEnvelopeValue * smoothedEnvAmount * 5.2
                        + accentFilterValue * accentAmount * 1.0
                )

            let filtered = filter.process(
                oscillatorSample,
                cutoff: modulatedCutoff,
                resonance: smoothedResonance,
                sampleRate: Float(sr)
            )

            var sample = filtered

            // Drive is a post-filter asymmetric saturator with a fixed tone
            // lift. Keeping it after the ladder prevents the filter's input
            // saturator from swallowing the added harmonics.
            if smoothedDrive > 0.01 {
                let driveBias: Float = 0.14
                let saturated = tanhf(sample * currentDriveGain + driveBias) - tanhf(driveBias)
                driveHighPassState += (saturated - driveHighPassState) * driveHighPassCoefficient
                let highPassed = saturated - driveHighPassState
                let driveNorm = min(max(smoothedDrive / 24.0, 0), 1)
                sample = (saturated + highPassed * driveNorm * 2.0)
                    / (1 + smoothedDrive * 0.028)
            }

            if amplitudeAttackActive {
                amplitude += amplitudeAttackRate
                if amplitude >= 1 {
                    amplitude = 1
                    amplitudeAttackActive = false
                }
            } else {
                amplitude *= gateOpen ? amplitudeDecayCoefficient : amplitudeReleaseCoefficient
            }

            if smoothedDistortion > 0.0001 {
                let shaped = tanhf(sample * (1 + smoothedDistortion * 7))
                sample += (shaped - sample) * smoothedDistortion
                sample *= 1 / (1 + smoothedDistortion * 0.55)
            }

            let accentGain = 1 + accentVCAValue * accentAmount * 6.0
            accentVCAValue *= accentVCADecayCoefficient

            // The delay chain sits after the VCA and distortion but before the
            // master volume and final limiter. This keeps tails alive after
            // note-off while still letting the output stage catch peaks.
            sample *= amplitude * accentGain

            // DC blocker for the asymmetric waveshaper and envelope.
            let dcBlocked = sample - dcInput + 0.9995 * dcOutput
            dcInput = sample
            dcOutput = dcBlocked

            var left = dcBlocked
            var right = dcBlocked

            for rawSlot in 0..<Vinegar303FXSlot.count {
                guard let slot = Vinegar303FXSlot(rawValue: rawSlot) else { continue }

                let isActive = p(slot.parameter(.type)) >= 0.5
                    && p(slot.parameter(.enabled)) >= 0.5
                guard isActive else {
                    if delayUnitActive[rawSlot] {
                        delayUnits[rawSlot].reset()
                        delayUnitActive[rawSlot] = false
                    }
                    continue
                }
                delayUnitActive[rawSlot] = true

                let sync = p(slot.parameter(.sync)) >= 0.5
                let divisionIndex = Int(
                    vinegarClamp(
                        p(slot.parameter(.division)).rounded(),
                        0,
                        AUValue(Vinegar303FXDivision.allCases.count - 1)
                    )
                )
                let delaySeconds: Double
                if sync {
                    delaySeconds = Vinegar303FXDivision(rawValue: divisionIndex)?
                        .seconds(tempo: baseTempo) ?? 0.25
                } else {
                    delaySeconds = Double(p(slot.parameter(.time))) / 1_000.0
                }

                let wetDry = delayUnits[rawSlot].process(
                    inputLeft: left,
                    inputRight: right,
                    targetDelaySamples: Float(max(1.0, delaySeconds * sr)),
                    feedback: min(max(p(slot.parameter(.feedback)) / 100.0, 0), 0.9),
                    tone: min(max(p(slot.parameter(.tone)) / 100.0, 0), 1),
                    mix: min(max(p(slot.parameter(.mix)) / 100.0, 0), 1),
                    pingPong: p(slot.parameter(.pingPong)) >= 0.5
                )
                left = wetDry.left
                right = wetDry.right
            }

            left *= smoothedVolume
            right *= smoothedVolume

            let limitedLeft = tanhf(left * 1.05) * 0.98
            let limitedRight = tanhf(right * 1.05) * 0.98

            write(
                left: limitedLeft,
                right: limitedRight,
                buffers: buffers,
                frameIndex: frameOffset + frame
            )
        }
    }

    // MARK: Sequencer

    private func activePatternBank() -> UnsafeMutablePointer<Vinegar303Step> {
        activeBank == 0 ? bankA : bankB
    }

    private func startSequence() {
        stepIndex = 0
        stepSampleCounter = 0
        fireStep(patternIndex: vinegarClamp(Int(p(.pattern).rounded()), 0, Self.maxPatterns - 1), index: 0)
    }

    private func alignSequence(
        toStepPosition position: Double,
        patternIndex: Int,
        length: Int,
        samplesPerStep: Double
    ) {
        let validPosition = position.isFinite ? max(position, 0) : 0
        let wholeSteps = validPosition.rounded(.down)
        let stepPositionInPattern = validPosition.truncatingRemainder(dividingBy: Double(max(length, 1)))
        let index = min(max(Int(stepPositionInPattern.rounded(.down)), 0), length - 1)

        stepSampleCounter = (validPosition - wholeSteps) * samplesPerStep
        fireStep(patternIndex: patternIndex, index: index)
    }

    private func stopSequence() {
        stepSampleCounter = 0
        gateOpen = false
        patternGateOpen = false
        manualNote = nil
        glideActive = false
        playheadStorage = -1
    }

    private func fireStep(patternIndex: Int, index: Int) {
        stepIndex = index
        playheadStorage = Int32(index)

        let base = activePatternBank() + patternIndex * Self.stepsPerPattern
        let step = base[index]
        patternGateOpen = step.gate
        patternGateClosePhase = step.slide ? 0.9 : 0.5

        guard manualNote == nil else { return }
        if step.gate {
            gateOpen = true
            gateClosePhase = step.slide ? 0.9 : 0.5
            trigger(note: Double(step.note), accent: step.accent, glide: false)
        } else {
            gateOpen = false
        }
    }

    private func advanceStep(patternIndex: Int, length: Int) {
        let base = activePatternBank() + patternIndex * Self.stepsPerPattern
        let previous = base[stepIndex]
        let nextIndex = (stepIndex + 1) % max(length, 1)
        let step = base[nextIndex]

        stepIndex = nextIndex
        playheadStorage = Int32(nextIndex)
        patternGateOpen = step.gate
        patternGateClosePhase = step.slide ? 0.9 : 0.5

        guard manualNote == nil else { return }

        if step.gate {
            gateOpen = true
            gateClosePhase = step.slide ? 0.9 : 0.5
            trigger(note: Double(step.note), accent: step.accent, glide: previous.slide)
        } else {
            gateOpen = false
        }
    }

    /// Resolve scale awareness only when a note is triggered. The render loop
    /// deliberately never runs the quantizer, so held notes cannot retune when
    /// scale parameters change.
    private func resolvedNote(_ rawNote: Double) -> Double {
        guard p(.scaleEnable) >= 0.5 else { return rawNote }

        let key = Int(vinegarClamp(p(.scaleKey).rounded(), 0, 11))
        let mode = Int(vinegarClamp(p(.scaleType).rounded(), 0, 6))
        return Double(Vinegar303Scale.quantize(note: Int(rawNote.rounded()), key: key, mode: mode))
    }

    private func trigger(note rawNote: Double, accent: Bool, glide: Bool) {
        let note = resolvedNote(rawNote)
        targetNote = note

        if accent {
            accentVCAValue = 1
            accentFilterEnvelope.trigger(1)
        } else {
            accentVCAValue = 0
            accentFilterEnvelope.reset()
        }

        if glide {
            glideActive = true
            return
        }

        glideActive = false
        currentNote = note
        filterEnvelope.trigger(1)
        amplitude = 0
        amplitudeAttackActive = true
    }

    // MARK: Output helpers

    @inline(__always)
    private func write(
        left: Float,
        right: Float,
        buffers: UnsafeMutableAudioBufferListPointer,
        frameIndex: Int
    ) {
        if buffers.count == 1, let buffer = buffers.first, buffer.mNumberChannels > 1 {
            guard let raw = buffer.mData else { return }
            let channels = Int(buffer.mNumberChannels)
            let data = raw.assumingMemoryBound(to: Float.self)
            let base = frameIndex * channels
            data[base] = left
            if channels > 1 {
                data[base + 1] = right
            }
            return
        }

        for (channel, buffer) in buffers.enumerated() {
            guard let raw = buffer.mData else { continue }
            let data = raw.assumingMemoryBound(to: Float.self)
            data[frameIndex] = channel == 0 ? left : right
        }
    }

    private func silence(
        buffers: UnsafeMutableAudioBufferListPointer,
        frames: Int,
        frameOffset: Int
    ) {
        for buffer in buffers {
            guard let raw = buffer.mData else { continue }
            let data = raw.assumingMemoryBound(to: Float.self)
            let channels = max(Int(buffer.mNumberChannels), 1)
            memset(data + frameOffset * channels, 0, frames * channels * MemoryLayout<Float>.size)
        }
    }
}

/// Stereo delay line with smoothed time, feedback and mix controls. The maximum
/// delay capacity is allocated in `prepare`, never in the render block.
struct Vinegar303DelayUnit {
    private var leftBuffer: UnsafeMutablePointer<Float>?
    private var rightBuffer: UnsafeMutablePointer<Float>?
    private var capacity = 0
    private var writeIndex = 0
    private var sampleRate: Double = 44_100
    private var smoothingCoefficient: Float = 0
    private var smoothedDelaySamples: Float = 1
    private var smoothedFeedback: Float = 0
    private var smoothedTone: Float = 0
    private var smoothedMix: Float = 0
    private var toneStateLeft: Float = 0
    private var toneStateRight: Float = 0

    mutating func prepare(sampleRate: Double) {
        self.sampleRate = max(sampleRate, 8_000)
        let requiredCapacity = max(Int(self.sampleRate * 2.0) + 4, 8)

        if capacity != requiredCapacity || leftBuffer == nil || rightBuffer == nil {
            deallocate()
            leftBuffer = .allocate(capacity: requiredCapacity)
            leftBuffer?.initialize(repeating: 0, count: requiredCapacity)
            rightBuffer = .allocate(capacity: requiredCapacity)
            rightBuffer?.initialize(repeating: 0, count: requiredCapacity)
            capacity = requiredCapacity
        } else {
            reset()
        }

        writeIndex = 0
        smoothedDelaySamples = 1
        smoothedFeedback = 0
        smoothedTone = 0
        smoothedMix = 0
        toneStateLeft = 0
        toneStateRight = 0
        smoothingCoefficient = Float(1.0 - exp(-1.0 / (0.02 * self.sampleRate)))
    }

    mutating func reset() {
        guard let leftBuffer, let rightBuffer, capacity > 0 else { return }
        for index in 0..<capacity {
            leftBuffer[index] = 0
            rightBuffer[index] = 0
        }
        writeIndex = 0
        smoothedDelaySamples = 1
        smoothedFeedback = 0
        smoothedTone = 0
        smoothedMix = 0
        toneStateLeft = 0
        toneStateRight = 0
    }

    mutating func deallocate() {
        leftBuffer?.deallocate()
        rightBuffer?.deallocate()
        leftBuffer = nil
        rightBuffer = nil
        capacity = 0
    }

    mutating func process(
        inputLeft: Float,
        inputRight: Float,
        targetDelaySamples: Float,
        feedback: Float,
        tone: Float,
        mix: Float,
        pingPong: Bool
    ) -> (left: Float, right: Float) {
        guard let leftBuffer, let rightBuffer, capacity > 4 else {
            return (inputLeft, inputRight)
        }

        let target = min(max(targetDelaySamples, 1), Float(capacity - 2))
        smoothedDelaySamples += (target - smoothedDelaySamples) * smoothingCoefficient
        smoothedFeedback += (feedback - smoothedFeedback) * smoothingCoefficient
        smoothedTone += (tone - smoothedTone) * smoothingCoefficient
        smoothedMix += (mix - smoothedMix) * smoothingCoefficient

        let delay = min(max(smoothedDelaySamples, 1), Float(capacity - 2))
        let readPosition = Float(writeIndex) - delay
        var readIndex = Int(readPosition.rounded(.down))
        let fraction = readPosition - Float(readIndex)
        while readIndex < 0 { readIndex += capacity }
        if readIndex >= capacity { readIndex -= capacity }
        let nextIndex = readIndex + 1 == capacity ? 0 : readIndex + 1

        let wetLeft = leftBuffer[readIndex]
            + (leftBuffer[nextIndex] - leftBuffer[readIndex]) * fraction
        let wetRight = rightBuffer[readIndex]
            + (rightBuffer[nextIndex] - rightBuffer[readIndex]) * fraction

        // A simple one-pole low-pass in the feedback path. Higher tone values
        // keep more high-frequency content in the repeats.
        let toneCoefficient = 0.02 + smoothedTone * 0.9
        toneStateLeft += (wetLeft - toneStateLeft) * toneCoefficient
        toneStateRight += (wetRight - toneStateRight) * toneCoefficient

        let feedbackLeft = toneStateLeft * smoothedFeedback
        let feedbackRight = toneStateRight * smoothedFeedback

        if pingPong {
            // Sum both channels into one side, then cross the feedback so
            // repeats alternate between the channels without dropping input.
            let monoInput = (inputLeft + inputRight) * 0.5
            leftBuffer[writeIndex] = monoInput + feedbackRight
            rightBuffer[writeIndex] = feedbackLeft
        } else {
            leftBuffer[writeIndex] = inputLeft + feedbackLeft
            rightBuffer[writeIndex] = inputRight + feedbackRight
        }

        writeIndex += 1
        if writeIndex >= capacity { writeIndex = 0 }

        let dryGain = 1 - smoothedMix
        let wetGain = smoothedMix
        return (
            left: inputLeft * dryGain + wetLeft * wetGain,
            right: inputRight * dryGain + wetRight * wetGain
        )
    }
}
