import AudioToolbox
import AVFoundation
import Combine
import Foundation

/// Miniature host application for the AUv3 kernel.
///
/// It instantiates the audio unit directly (no plug-in registration required),
/// asks it to allocate render resources, then pulls audio through the unit's
/// host-facing render block with an AVAudioSourceNode. That block injects
/// scheduled MIDI into the internal block, just as a DAW does, while remaining
/// trivially runnable from Xcode.
final class Vinegar303Host: ObservableObject {
    let audioUnit: Vinegar303AudioUnit
    let patterns: PatternStore
    let presets: Vinegar303PresetController
    let midi: Vinegar303MIDIController

    @Published private(set) var status = "STARTING"
    @Published private(set) var sampleRate: Double = 0

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var renderBlock: AURenderBlock?
    private var midiEventBlock: AUScheduleMIDIEventBlock?
    private var coreMIDI: Vinegar303CoreMIDIInput?
    private var padLEDOutput: Vinegar303LaunchkeyLEDOutput?
    private var padLEDTimer: Timer?
    private var padLEDStates = Array(
        repeating: Vinegar303LaunchkeyPadColor.off,
        count: Vinegar303LaunchkeyPadMap.allNotes.count
    )
    private var padLEDConnectionID = 0

    init() {
        Vinegar303BundledContent.installFromAppBundle()

        let unit: Vinegar303AudioUnit
        do {
            unit = try Vinegar303AudioUnit(componentDescription: Vinegar303AudioUnit.componentDescription)
        } catch {
            fatalError("Could not create the Vinegar303 audio unit: \(error)")
        }
        audioUnit = unit
        let patternStore = PatternStore(patterns: unit.patterns) { [weak unit] patterns in
            unit?.patterns = patterns
        }
        patterns = patternStore
        presets = Vinegar303PresetController(
            library: Vinegar303PresetLibrary(),
            parameterTree: unit.editorParameterTree,
            patterns: patternStore
        )
        let midiController = Vinegar303MIDIController()
        midi = midiController
        coreMIDI = Vinegar303CoreMIDIInput(controller: midiController)
        midiController.noteForStep = { [weak self] index in
            guard let self else { return nil }
            return self.patterns.step(
                pattern: self.currentPatternIndex,
                index: index
            ).note
        }
        midiController.onAction = { [weak self] action in
            self?.applyMIDIAction(action)
        }
        midiController.onUnmappedNote = { [weak self] message in
            self?.forwardUnmappedMIDINote(message)
        }
        padLEDOutput = Vinegar303LaunchkeyLEDOutput()
        startAudio()
        startPadLEDFeedback()
    }

    deinit {
        padLEDTimer?.invalidate()
        padLEDOutput?.shutdown()
    }

    // MARK: Launchkey pad LEDs

    private func startPadLEDFeedback() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updatePadLEDs()
        }
        RunLoop.main.add(timer, forMode: .common)
        padLEDTimer = timer
    }

    private func updatePadLEDs() {
        guard let padLEDOutput else { return }

        // A reconnect clears the controller and resets our LED state.
        if padLEDOutput.connectionID != padLEDConnectionID {
            padLEDConnectionID = padLEDOutput.connectionID
            padLEDStates = Array(
                repeating: .off,
                count: Vinegar303LaunchkeyPadMap.allNotes.count
            )
        }
        guard padLEDOutput.connectionID != 0 else { return }

        let pattern = patterns.patterns[currentPatternIndex]
        let noneActive = midi.profile.name == Vinegar303MIDIProfile.noneName
        var desired: [Vinegar303LaunchkeyPadColor]

        if noneActive {
            desired = Array(
                repeating: .off,
                count: Vinegar303LaunchkeyPadMap.allNotes.count
            )
        } else if midi.launchkeyEditModeEnabled {
            desired = (0..<Vinegar303LaunchkeyPadMap.allNotes.count).map { gate in
                guard pattern.steps.indices.contains(gate), pattern.steps[gate].gate else {
                    return Vinegar303LaunchkeyPadColor.off
                }
                return Vinegar303LaunchkeyPadColor.green
            }
        } else {
            desired = Array(
                repeating: .off,
                count: Vinegar303LaunchkeyPadMap.allNotes.count
            )
            if desired.indices.contains(currentPatternIndex) {
                desired[currentPatternIndex] = .green
            }
        }

        let step = audioUnit.playheadStep
        if !noneActive, step >= 0, audioUnit.sequencerGateOpen {
            let pads = Vinegar303LaunchkeyPadMap.transportGateIndices(
                forStep: step,
                bindings: midi.profile.bindings
            )
            for pad in pads where desired.indices.contains(pad) {
                desired[pad] = .red
            }
        }

        for gate in desired.indices where desired[gate] != padLEDStates[gate] {
            padLEDOutput.setLED(gate: gate, color: desired[gate])
            padLEDStates[gate] = desired[gate]
        }
    }

    // MARK: MIDI

    private func applyMIDIAction(_ action: Vinegar303MIDIAction) {
        switch action {
        case .parameter(let id, let value):
            audioUnit.editorParameterTree.parameter(
                withAddress: id.rawValue
            )?.value = value

        case .pattern(let index):
            let clamped = min(max(index, 0), Vinegar303PatternLibrary.patternCount - 1)
            audioUnit.editorParameterTree.parameter(
                withAddress: Vinegar303Parameter.pattern.rawValue
            )?.value = AUValue(clamped)

        case .stepGate(let index):
            patterns.toggleGate(pattern: currentPatternIndex, index: index)

        case .stepAccent(let index):
            patterns.toggleAccent(pattern: currentPatternIndex, index: index)

        case .stepSlide(let index):
            patterns.toggleSlide(pattern: currentPatternIndex, index: index)

        case .stepNote(let index, let note):
            patterns.setNote(pattern: currentPatternIndex, index: index, note: note)

        case .adjustPatternLength(let delta):
            adjustPatternLength(by: delta)
        }
    }

    private func adjustPatternLength(by delta: Int) {
        let index = currentPatternIndex
        guard patterns.patterns.indices.contains(index) else { return }
        let current = patterns.patterns[index].length
        let next = min(
            max(current + delta, 1),
            Vinegar303PatternLibrary.stepsPerPattern
        )
        guard next != current else { return }
        patterns.setLength(pattern: index, length: next)
        audioUnit.editorParameterTree.parameter(
            withAddress: Vinegar303Parameter.patternLength.rawValue
        )?.value = AUValue(next)
    }

    private var currentPatternIndex: Int {
        let raw = audioUnit.editorParameterTree.parameter(
            withAddress: Vinegar303Parameter.pattern.rawValue
        )?.value ?? 0
        return min(max(Int(raw.rounded()), 0), Vinegar303PatternLibrary.patternCount - 1)
    }

    private func forwardUnmappedMIDINote(_ message: Vinegar303MIDIMessage) {
        switch message {
        case .noteOn(_, let note, let velocity):
            sendMIDI([0x90, UInt8(note & 0x7F), UInt8(velocity & 0x7F)])
        case .noteOff(_, let note):
            sendMIDI([0x80, UInt8(note & 0x7F), 0])
        default:
            break
        }
    }

    private func startAudio() {
        let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let rate = hardwareRate > 0 ? hardwareRate : 48_000

        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
            status = "NO OUTPUT FORMAT"
            return
        }
        sampleRate = rate

        do {
            try audioUnit.outputBusses[0].setFormat(format)
            audioUnit.maximumFramesToRender = 4_096
            // Hosts should cache these before allocating render resources.
            renderBlock = audioUnit.renderBlock
            midiEventBlock = audioUnit.scheduleMIDIEventBlock
            try audioUnit.allocateRenderResources()
            if midiEventBlock == nil {
                midiEventBlock = audioUnit.scheduleMIDIEventBlock
            }
        } catch {
            status = "AU ERROR: \(error.localizedDescription)"
            return
        }

        guard let renderBlock else {
            status = "NO RENDER BLOCK"
            return
        }
        let node = AVAudioSourceNode(format: format) { _, timestamp, frameCount, audioBufferList in
            var flags: AudioUnitRenderActionFlags = []
            var timeStamp = timestamp.pointee
            return renderBlock(&flags, &timeStamp, frameCount, 0, audioBufferList, nil)
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()

        do {
            try engine.start()
            status = "AUDIO RUNNING"
        } catch {
            status = "AUDIO ERROR: \(error.localizedDescription)"
        }

        sourceNode = node
    }

    // MARK: Auditioning

    func auditionOn(note: UInt8 = 48) {
        sendMIDI([0x90, note, 100])
    }

    func auditionOff(note: UInt8 = 48) {
        sendMIDI([0x80, note, 0])
    }

    /// Toggle the same Run parameter used by the editor's play/stop button.
    func toggleRun() {
        guard let run = audioUnit.editorParameterTree.parameter(
            withAddress: Vinegar303Parameter.run.rawValue
        ) else { return }
        run.value = run.value >= 0.5 ? 0 : 1
    }

    func sendMIDI(_ bytes: [UInt8]) {
        let block = midiEventBlock ?? audioUnit.scheduleMIDIEventBlock
        bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            block?(AUEventSampleTimeImmediate, 0, bytes.count, base)
        }
    }
}
