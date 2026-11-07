import AudioToolbox
import SwiftUI

/// Complete plug-in editor. Used verbatim inside the AUv3 extension and by the
/// host wrapper application.
struct Vinegar303Editor: View {
    @StateObject private var model: ParameterModel
    @ObservedObject private var patterns: PatternStore
    @ObservedObject private var presets: Vinegar303PresetController
    @State private var showingPresetManager = false
    private let playhead: (() -> Int)?
    private let midi: Vinegar303MIDIController?

    init(
        parameterTree: AUParameterTree,
        patterns: PatternStore,
        presets: Vinegar303PresetController,
        playhead: (() -> Int)? = nil,
        midi: Vinegar303MIDIController? = nil
    ) {
        _model = StateObject(wrappedValue: ParameterModel(tree: parameterTree))
        _patterns = ObservedObject(wrappedValue: patterns)
        _presets = ObservedObject(wrappedValue: presets)
        self.playhead = playhead
        self.midi = midi
    }

    /// The Run parameter only describes Free mode. In Host mode the live
    /// playhead is the source of truth, so the button follows actual transport.
    private var isRunning: Bool {
        if let playhead {
            return playhead() >= 0
        }
        return model.value(.run) >= 0.5
    }
    private var isHostSynced: Bool { model.value(.sync) >= 0.5 }
    private var isNoteMode: Bool { model.value(.midiMode) >= 0.5 }
    private var isScaleAware: Bool { model.value(.scaleEnable) >= 0.5 }
    private var isHalfSpeed: Bool { model.value(.halfSpeed) >= 0.5 }

    var body: some View {
        VStack(spacing: 14) {
            header

            Vinegar303SequencerPanel(
                model: model,
                patterns: patterns,
                presets: presets,
                showingPresetManager: $showingPresetManager,
                playhead: playhead,
                midi: midi
            )
            .frame(maxWidth: .infinity)

            HStack(alignment: .top, spacing: 14) {
                filterPanel
                    .frame(maxWidth: .infinity)
                voicePanel
                    .frame(maxWidth: .infinity)
            }

            HStack(alignment: .top, spacing: 14) {
                scalePanel
                    .frame(maxWidth: .infinity)
                outputPanel
                    .frame(maxWidth: .infinity)
            }

            if let midi {
                Vinegar303MIDIPanel(midi: midi)
            }

            footer
        }
        .padding(16)
        .background(background)
        .frame(minWidth: 1_020, minHeight: 640)
        .preferredColorScheme(.dark)
        .environment(\.vinegar303MIDIController, midi)
        .sheet(isPresented: $showingPresetManager) {
            Vinegar303PresetManagerView(presets: presets)
        }
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            Vinegar303Theme.background
            RadialGradient(
                colors: [Vinegar303Theme.acid.opacity(0.055), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 640
            )
            RadialGradient(
                colors: [Color(red: 0.15, green: 0.45, blue: 0.65).opacity(0.05), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("VINEGAR")
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(Vinegar303Theme.text)
                    Text("303")
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .foregroundStyle(Vinegar303Theme.acid)
                }
                Text("CLEAN-ROOM ACID BASSLINE")
                    .font(Vinegar303Theme.monoSmall)
                    .tracking(2.2)
                    .foregroundStyle(Vinegar303Theme.dim)
            }

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    Vinegar303RunButton(isRunning: isRunning) {
                        model.toggle(.run)
                    }
                }
                .fixedSize()
                .vinegar303LearnBadge(for: .run, midi: midi)

                Vinegar303Chip(
                    caption: "HALF",
                    value: isHalfSpeed ? "1:2" : "1:1",
                    accent: Vinegar303Theme.amber,
                    isActive: isHalfSpeed
                ) {
                    model.toggle(.halfSpeed)
                }
                .vinegar303LearnBadge(for: .halfSpeed, midi: midi)

                Vinegar303ParameterKnob(model: model, id: .tempo, accent: Vinegar303Theme.acid, size: 38)

                Vinegar303Chip(
                    caption: "SYNC",
                    value: isHostSynced ? "HOST" : "FREE",
                    accent: Vinegar303Theme.acid,
                    isActive: isHostSynced
                ) {
                    model.toggle(.sync)
                }
                .vinegar303LearnBadge(for: .sync, midi: midi)

                Vinegar303Chip(
                    caption: "MIDI",
                    value: isNoteMode ? "NOTE" : "PATTERN",
                    accent: Vinegar303Theme.cyan,
                    isActive: isNoteMode
                ) {
                    model.toggle(.midiMode)
                }
                .vinegar303LearnBadge(for: .midiMode, midi: midi)
            }
        }
    }

    // MARK: Panels

    private var filterPanel: some View {
        Vinegar303Panel("FILTER", accent: Vinegar303Theme.acid) {
            HStack(spacing: 14) {
                Vinegar303ParameterKnob(
                    model: model,
                    id: .pitchTranspose,
                    accent: Vinegar303Theme.acid,
                    size: 48,
                    labelOverride: "TRANSPOSE"
                )
                .opacity(isScaleAware ? 0.35 : 1)
                .allowsHitTesting(!isScaleAware)
                .help(
                    isScaleAware
                        ? "Transpose is bypassed while Scale Aware is on"
                        : "Pitch Transpose: \(model.displayValue(.pitchTranspose))"
                )

                Vinegar303ParameterKnob(model: model, id: .cutoff, accent: Vinegar303Theme.acid)
                Vinegar303ParameterKnob(model: model, id: .resonance, accent: Vinegar303Theme.acid)
                Vinegar303ParameterKnob(model: model, id: .envmod, accent: Vinegar303Theme.acid)
                Vinegar303ParameterKnob(model: model, id: .decay, accent: Vinegar303Theme.acid)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var voicePanel: some View {
        Vinegar303Panel("VOICE", accent: Vinegar303Theme.cyan) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WAVEFORM")
                        .font(Vinegar303Theme.monoSmall)
                        .tracking(1.0)
                        .foregroundStyle(Vinegar303Theme.faint)
                    Vinegar303WaveformSwitch(isSaw: model.value(.waveform) >= 0.5) { saw in
                        model.setValueWithGesture(saw ? 1 : 0, for: .waveform)
                    }
                    .vinegar303LearnBadge(for: .waveform, midi: midi)
                    Text("SINGLE OSC · MONO VOICE")
                        .font(Vinegar303Theme.monoSmall)
                        .tracking(0.6)
                        .foregroundStyle(Vinegar303Theme.faint)
                }

                Spacer(minLength: 0)

                Vinegar303ParameterKnob(
                    model: model,
                    id: .tuning,
                    accent: Vinegar303Theme.cyan,
                    size: 48
                )
            }
        }
    }

    private var outputPanel: some View {
        Vinegar303Panel("OUTPUT", accent: Vinegar303Theme.amber) {
            HStack(spacing: 14) {
                Vinegar303ParameterKnob(model: model, id: .accent, accent: Vinegar303Theme.amber)
                Vinegar303ParameterKnob(model: model, id: .volume, accent: Vinegar303Theme.amber)
                Vinegar303ParameterKnob(model: model, id: .distortion, accent: Vinegar303Theme.amber)
                Vinegar303ParameterKnob(model: model, id: .drive, accent: Vinegar303Theme.amber)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var scalePanel: some View {
        Vinegar303Panel(
            "SCALE AWARE",
            accent: isScaleAware ? Vinegar303Theme.acid : Vinegar303Theme.dim
        ) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Vinegar303Chip(
                        caption: "SCALE AWARE",
                        value: isScaleAware ? "ON" : "OFF",
                        accent: Vinegar303Theme.acid,
                        isActive: isScaleAware
                    ) {
                        model.toggle(.scaleEnable)
                    }
                    .vinegar303LearnBadge(for: .scaleEnable, midi: midi)

                    Spacer(minLength: 8)

                    Vinegar303MenuChip(
                        caption: "KEY",
                        value: model.displayValue(.scaleKey),
                        accent: Vinegar303Theme.acid,
                        isActive: isScaleAware,
                        options: Vinegar303Scale.keyNames,
                        selectedIndex: Int(model.value(.scaleKey).rounded())
                    ) { index in
                        model.setValueWithGesture(AUValue(index), for: .scaleKey)
                    }
                    .vinegar303LearnBadge(for: .scaleKey, midi: midi)

                    Vinegar303MenuChip(
                        caption: "MODE",
                        value: model.displayValue(.scaleType),
                        accent: Vinegar303Theme.acid,
                        isActive: isScaleAware,
                        options: Vinegar303Scale.modeNames,
                        selectedIndex: Int(model.value(.scaleType).rounded())
                    ) { index in
                        model.setValueWithGesture(AUValue(index), for: .scaleType)
                    }
                    .vinegar303LearnBadge(for: .scaleType, midi: midi)
                }

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    Circle()
                        .fill(isScaleAware ? Vinegar303Theme.acid : Vinegar303Theme.faint)
                        .frame(width: 3, height: 3)
                    Text(isScaleAware ? "TRANSPOSE BYPASSED" : "CHROMATIC PLAYBACK")
                        .font(Vinegar303Theme.monoSmall)
                        .tracking(0.7)
                        .foregroundStyle(isScaleAware ? Vinegar303Theme.acid.opacity(0.8) : Vinegar303Theme.faint)
                }
                .lineLimit(1)
            }
            // Match the labeled tuning knob in VOICE so the paired panels
            // share the same height while keeping their controls horizontal.
            .frame(maxWidth: .infinity, minHeight: 82)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Vinegar303Theme.acid)
                .frame(width: 4, height: 4)
            Text("AUv3 · aumu/Vg03")
                .font(Vinegar303Theme.monoSmall)
                .foregroundStyle(Vinegar303Theme.dim)
            Text("·")
                .foregroundStyle(Vinegar303Theme.faint)
            Text("UNLOCKED — NO LICENSE CHECK")
                .font(Vinegar303Theme.monoSmall)
                .foregroundStyle(Vinegar303Theme.acid.opacity(0.8))
            Text("·")
                .foregroundStyle(Vinegar303Theme.faint)
            Text("NO TELEMETRY")
                .font(Vinegar303Theme.monoSmall)
                .foregroundStyle(Vinegar303Theme.dim)

            Spacer(minLength: 8)

            Text("v1.0 · MIT")
                .font(Vinegar303Theme.monoSmall)
                .foregroundStyle(Vinegar303Theme.faint)
        }
        .padding(.top, 2)
    }
}
