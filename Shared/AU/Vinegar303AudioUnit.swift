import AudioToolbox
import AVFoundation
import Foundation

/// AUv3 instrument kernel.
///
/// The audio unit owns the parameter tree, the DSP engine and the render block.
/// There is no licensing, activation, serial-number, network or telemetry path
/// anywhere in this implementation.
public final class Vinegar303AudioUnit: AUAudioUnit {
    public static let componentDescription = AudioComponentDescription(
        componentType: fourCharCode("aumu"),
        componentSubType: fourCharCode("Vg03"),
        componentManufacturer: fourCharCode("Vngr"),
        componentFlags: 0,
        componentFlagsMask: 0
    )

    private let engine = Vinegar303Engine()
    private let hostContext = Vinegar303HostContext()
    private let parameterTreeStorage: AUParameterTree
    private var outputBusArray: AUAudioUnitBusArray?
    private var patternObserverToken: AUParameterObserverToken?

    // MARK: Init

    public override init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = []
    ) throws {
        parameterTreeStorage = Vinegar303ParameterTreeFactory.makeTree()
        try super.init(componentDescription: componentDescription, options: options)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2) else {
            throw NSError(domain: "Vinegar303", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create the default output format."])
        }
        let bus = try AUAudioUnitBus(format: format)
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [bus])
        maximumFramesToRender = 4_096

        parameterTree = parameterTreeStorage

        // Parameter traffic from the host and from editors goes straight into
        // the lock-free engine mirror. The audio thread reads the mirror.
        parameterTreeStorage.implementorValueObserver = { [weak engine] parameter, value in
            engine?.setParameter(address: parameter.address, value: value)
        }
        parameterTreeStorage.implementorValueProvider = { [weak engine] parameter in
            engine?.parameter(address: parameter.address) ?? 0
        }

        seedEngineFromTree()
        observePatternSelection()
    }

    deinit {
        if let patternObserverToken {
            parameterTreeStorage.removeParameterObserver(patternObserverToken)
        }
    }

    // MARK: Busses

    public override var outputBusses: AUAudioUnitBusArray {
        outputBusArray ?? super.outputBusses
    }

    /// The engine is a stereo instrument. Reporting this pair also keeps hosts
    /// and AU validation from trying mono or surround bus layouts.
    public override var channelCapabilities: [NSNumber]? {
        [NSNumber(value: 0), NSNumber(value: 2)]
    }

    public override func allocateRenderResources() throws {
        let busFormat = outputBusses[0].format
        guard busFormat.channelCount == 2 else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(kAudioUnitErr_FormatNotSupported),
                userInfo: [NSLocalizedDescriptionKey: "Vinegar303 supports stereo output only."]
            )
        }

        try super.allocateRenderResources()
        hostContext.musicalContext = musicalContextBlock
        hostContext.transportState = transportStateBlock
        seedEngineFromTree()
        engine.prepare(sampleRate: busFormat.sampleRate)
    }

    public override func deallocateRenderResources() {
        engine.reset()
        super.deallocateRenderResources()
    }

    // MARK: Render

    public override var internalRenderBlock: AUInternalRenderBlock {
        let engine = self.engine
        let host = self.hostContext

        return { actionFlags, timestamp, frameCount, _, outputData, realtimeEventListHead, _ in
            actionFlags.pointee = []

            let frames = Int(frameCount)
            let blockStart = timestamp.pointee.mSampleTime
            let hostSnapshot = host.snapshot()
            let hostTempo = hostSnapshot.tempo
            let hostPlaying = hostSnapshot.playing

            var cursor = 0
            var event = UnsafeMutablePointer(mutating: realtimeEventListHead)

            while let current = event {
                let sampleTime = current.pointee.head.eventSampleTime
                let rawOffset = sampleTime > 0
                    ? Int(Double(sampleTime) - blockStart)
                    : 0
                let offset = min(max(rawOffset, 0), frames)

                if offset > cursor {
                    engine.render(
                        into: outputData,
                        frames: offset - cursor,
                        frameOffset: cursor,
                        hostTempo: hostTempo,
                        hostPlaying: hostPlaying,
                        hostSamplePosition: hostSnapshot.samplePosition,
                        hostBeatPosition: hostSnapshot.beatPosition
                    )
                    cursor = offset
                }

                switch current.pointee.head.eventType {
                case .MIDI:
                    let midi = current.pointee.MIDI
                    engine.handleMIDI(
                        bytes: (midi.data.0, midi.data.1, midi.data.2),
                        length: Int(midi.length)
                    )
                case .parameter, .parameterRamp:
                    let parameter = current.pointee.parameter
                    engine.setParameter(address: parameter.parameterAddress, value: parameter.value)
                default:
                    break
                }

                event = current.pointee.head.next
            }

            if cursor < frames {
                engine.render(
                    into: outputData,
                    frames: frames - cursor,
                    frameOffset: cursor,
                    hostTempo: hostTempo,
                    hostPlaying: hostPlaying,
                    hostSamplePosition: hostSnapshot.samplePosition,
                    hostBeatPosition: hostSnapshot.beatPosition
                )
            }

            return noErr
        }
    }

    // MARK: Host access

    public var editorParameterTree: AUParameterTree {
        parameterTreeStorage
    }

    public var playheadStep: Int {
        engine.playheadStep
    }

    public var sequencerGateOpen: Bool {
        engine.sequencerGateOpen
    }

    public var patterns: [Vinegar303Pattern] {
        get { engine.patterns }
        set { engine.patterns = newValue }
    }

    private func seedEngineFromTree() {
        for parameter in parameterTreeStorage.allParameters {
            engine.setParameter(address: parameter.address, value: parameter.value)
        }
    }

    private func observePatternSelection() {
        patternObserverToken = parameterTreeStorage.token(byAddingParameterObserver: { [weak self] address, _ in
            guard address == Vinegar303Parameter.pattern.rawValue else { return }
            DispatchQueue.main.async {
                self?.synchronizePatternLength()
            }
        })
    }

    /// Keep the active `patternLength` mirror aligned with the selected
    /// pattern. This matters when a host changes the pattern parameter without
    /// the editor being open.
    private func synchronizePatternLength() {
        let patterns = engine.patterns
        let index = min(
            max(Int((parameterTreeStorage.parameter(withAddress: Vinegar303Parameter.pattern.rawValue)?.value ?? 0).rounded()), 0),
            Vinegar303PatternLibrary.patternCount - 1
        )
        guard patterns.indices.contains(index),
              let lengthParameter = parameterTreeStorage.parameter(
                withAddress: Vinegar303Parameter.patternLength.rawValue
              ) else { return }
        let length = patterns[index].length
        guard Int(lengthParameter.value.rounded()) != length else { return }
        lengthParameter.value = AUValue(length)
        engine.setParameter(.patternLength, AUValue(length))
    }

    // MARK: State recall

    public override var fullState: [String: Any]? {
        get {
            var state = super.fullState ?? [:]
            let encodedPatterns: [[[String: Int]]] = patterns.map { pattern in
                pattern.steps.map { step in
                    [
                        "n": step.note,
                        "g": step.gate ? 1 : 0,
                        "a": step.accent ? 1 : 0,
                        "s": step.slide ? 1 : 0,
                    ]
                }
            }
            state["vinegar303.patterns"] = encodedPatterns
            state["vinegar303.patternLengths"] = patterns.map(\.length)
            state["vinegar303.version"] = 2
            return state
        }
        set {
            super.fullState = newValue

            // Run is transport state, not musical state. Always recall a loaded
            // project in Stop so restoring a session cannot start the sequencer.
            parameterTreeStorage.parameter(withAddress: Vinegar303Parameter.run.rawValue)?.value = 0
            engine.setParameter(.run, 0)

            guard let encoded = newValue?["vinegar303.patterns"] as? [[[String: Int]]] else { return }

            let fallbackLength = Int(
                (parameterTreeStorage.parameter(withAddress: Vinegar303Parameter.patternLength.rawValue)?.value ?? 16).rounded()
            )
            let storedLengths = newValue?["vinegar303.patternLengths"] as? [Int]
            let decoded: [Vinegar303Pattern] = encoded.enumerated().map { patternIndex, steps in
                var parsed = [Vinegar303Step]()
                parsed.reserveCapacity(Vinegar303PatternLibrary.stepsPerPattern)
                for index in 0..<Vinegar303PatternLibrary.stepsPerPattern {
                    guard steps.indices.contains(index) else {
                        parsed.append(.rest)
                        continue
                    }
                    let step = steps[index]
                    parsed.append(
                        Vinegar303Step(
                            note: step["n"] ?? 33,
                            gate: (step["g"] ?? 1) != 0,
                            accent: (step["a"] ?? 0) != 0,
                            slide: (step["s"] ?? 0) != 0
                        )
                    )
                }
                let length = storedLengths?.indices.contains(patternIndex) == true
                    ? storedLengths![patternIndex]
                    : fallbackLength
                return Vinegar303Pattern(steps: parsed, length: length)
            }
            patterns = decoded
            synchronizePatternLength()
        }
    }
}

/// Small non-allocating holder for the host callbacks used by the render block.
private final class Vinegar303HostContext {
    var musicalContext: AUHostMusicalContextBlock?
    var transportState: AUHostTransportStateBlock?

    func snapshot() -> (tempo: Double?, playing: Bool?, samplePosition: Double?, beatPosition: Double?) {
        var tempo: Double?
        var beatPosition: Double?
        if let musicalContext {
            var currentTempo: Double = 0
            var currentBeat: Double = 0
            if musicalContext(&currentTempo, nil, nil, &currentBeat, nil, nil) {
                if currentTempo > 0 {
                    tempo = currentTempo
                }
                if currentBeat.isFinite {
                    beatPosition = currentBeat
                }
            }
        }

        var playing: Bool?
        var samplePosition: Double?
        if let transportState {
            var flags: AUHostTransportStateFlags = []
            var currentSample: Double = 0
            if transportState(&flags, &currentSample, nil, nil) {
                playing = flags.contains(.moving)
                if currentSample.isFinite {
                    samplePosition = currentSample
                }
            }
        }

        return (tempo, playing, samplePosition, beatPosition)
    }
}
