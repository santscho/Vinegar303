import AudioToolbox
import SwiftUI
import UniformTypeIdentifiers

/// Complete plug-in editor. Used verbatim inside the AUv3 extension and by the
/// host wrapper application.
struct Vinegar303Editor: View {
    @StateObject private var model: ParameterModel
    @ObservedObject private var patterns: PatternStore
    @ObservedObject private var presets: Vinegar303PresetController
    @State private var showingPresetManager = false
    @State private var selectedFXSlot: Int?
    @State private var draggingFXSlot: Int?
    @AppStorage(Vinegar303AppearanceMode.storageKey)
    private var appearanceRawValue = Vinegar303AppearanceMode.system.rawValue
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
    private var appearanceMode: Vinegar303AppearanceMode {
        Vinegar303AppearanceMode(rawValue: appearanceRawValue) ?? .system
    }

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
                fxPanel
                    .frame(width: 500)
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
        .preferredColorScheme(appearanceMode.colorScheme)
        .environment(\.vinegar303MIDIController, midi)
        .sheet(isPresented: $showingPresetManager) {
            Vinegar303PresetManagerView(presets: presets)
                .preferredColorScheme(appearanceMode.colorScheme)
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

            Vinegar303AppearanceSwitcher(
                selection: Binding(
                    get: { appearanceMode },
                    set: { appearanceRawValue = $0.rawValue }
                )
            )

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
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
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
            .frame(maxWidth: .infinity, minHeight: 126)
        }
    }

    // MARK: FX

    private var activeFXSlots: [Vinegar303FXSlot] {
        model.fxActiveSlots
    }

    private var selectedFX: Vinegar303FXSlot? {
        let active = activeFXSlots
        if let raw = selectedFXSlot,
           let slot = Vinegar303FXSlot(rawValue: raw),
           active.contains(slot) {
            return slot
        }
        return active.first
    }

    private var fxPanel: some View {
        Vinegar303Panel("FX", accent: Vinegar303Theme.cyan) {
            VStack(alignment: .leading, spacing: 8) {
                fxChain
                if let selected = selectedFX {
                    fxParameterDrawer(selected)
                } else {
                    Text("ADD AN EFFECT TO THE CHAIN")
                        .font(Vinegar303Theme.monoSmall)
                        .tracking(0.8)
                        .foregroundStyle(Vinegar303Theme.faint)
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        }
    }

    private var fxChain: some View {
        HStack(spacing: 4) {
            if activeFXSlots.isEmpty {
                Text("NO EFFECTS")
                    .font(Vinegar303Theme.monoSmall)
                    .tracking(0.8)
                    .foregroundStyle(Vinegar303Theme.faint)
                addFXMenu(showLabel: true)
            } else {
                ForEach(activeFXSlots) { slot in
                    if let index = activeFXSlots.firstIndex(of: slot), index > 0 {
                        fxChainArrow
                    }
                    fxChip(slot)
                }

                fxChainArrow
                addFXMenu(showLabel: false)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fxChainArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(Vinegar303Theme.faint)
    }

    private func fxChip(_ slot: Vinegar303FXSlot) -> some View {
        let isSelected = selectedFX == slot
        let isEnabled = model.value(slot.parameter(.enabled)) >= 0.5
        let effectType = model.fxEffectType(for: slot)

        return HStack(spacing: 3) {
            Toggle("", isOn: Binding(
                get: { model.value(slot.parameter(.enabled)) >= 0.5 },
                set: { model.setValueWithGesture($0 ? 1 : 0, for: slot.parameter(.enabled)) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Vinegar303Theme.cyan)
            .help("Turn \(effectType.title) \(isEnabled ? "off" : "on")")

            Text(effectType.title.uppercased())
                .font(Vinegar303Theme.monoSmall)
                .tracking(0.6)
                .foregroundStyle(isEnabled ? Vinegar303Theme.text : Vinegar303Theme.faint)

            Button {
                removeFX(slot)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Vinegar303Theme.faint)
                    .frame(width: 13, height: 15)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove \(effectType.title)")

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Vinegar303Theme.faint)
                .frame(width: 10, height: 15)
                .contentShape(Rectangle())
                .help("Drag to reorder")
                .onDrag {
                    draggingFXSlot = slot.rawValue
                    return NSItemProvider(object: NSString(string: "\(slot.rawValue)"))
                }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Vinegar303Theme.cyan.opacity(0.14) : Vinegar303Theme.controlFillSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? Vinegar303Theme.cyan.opacity(0.55) : Vinegar303Theme.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedFXSlot = slot.rawValue
        }
        .onDrop(
            of: [.text],
            delegate: Vinegar303FXDropDelegate(
                target: slot,
                model: model,
                dragging: $draggingFXSlot
            )
        )
    }

    private func addFXMenu(showLabel: Bool) -> some View {
        Menu {
            Button("Delay") {
                addDelay()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
                if showLabel {
                    Text("ADD EFFECT")
                        .font(Vinegar303Theme.monoSmall)
                        .tracking(0.8)
                }
            }
            .foregroundStyle(Vinegar303Theme.cyan)
            .padding(.horizontal, showLabel ? 7 : 4)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Vinegar303Theme.cyan.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Vinegar303Theme.cyan.opacity(0.35), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(activeFXSlots.count >= Vinegar303FXSlot.count)
        .help(
            activeFXSlots.count >= Vinegar303FXSlot.count
                ? "Maximum \(Vinegar303FXSlot.count) effects"
                : "Add an effect"
        )
    }

    private func fxParameterDrawer(_ slot: Vinegar303FXSlot) -> some View {
        let sync = model.value(slot.parameter(.sync)) >= 0.5

        return HStack(alignment: .top, spacing: 7) {
            fxKnob(slot.parameter(.time), label: "TIME", accent: Vinegar303Theme.cyan)
                .opacity(sync ? 0.35 : 1)
                .allowsHitTesting(!sync)
                .help(sync ? "Time is set by the host-synced division" : "Delay time")

            fxKnob(slot.parameter(.feedback), label: "FEEDBACK", accent: Vinegar303Theme.cyan)
            fxKnob(slot.parameter(.tone), label: "TONE", accent: Vinegar303Theme.cyan)
            fxKnob(slot.parameter(.mix), label: "MIX", accent: Vinegar303Theme.cyan)

            VStack(alignment: .leading, spacing: 6) {
                Vinegar303Chip(
                    caption: "SYNC",
                    value: sync ? "HOST" : "FREE",
                    accent: Vinegar303Theme.cyan,
                    isActive: sync
                ) {
                    model.toggle(slot.parameter(.sync))
                }

                Vinegar303MenuChip(
                    caption: "DIVISION",
                    value: model.displayValue(slot.parameter(.division)),
                    accent: Vinegar303Theme.cyan,
                    isActive: sync,
                    options: Vinegar303FXDivision.allCases.map(\.title),
                    selectedIndex: Int(model.value(slot.parameter(.division)).rounded())
                ) { index in
                    model.setValueWithGesture(
                        AUValue(index),
                        for: slot.parameter(.division)
                    )
                }
                .opacity(sync ? 1 : 0.45)
                .allowsHitTesting(sync)

                Vinegar303Chip(
                    caption: "PING-PONG",
                    value: model.value(slot.parameter(.pingPong)) >= 0.5 ? "ON" : "OFF",
                    accent: Vinegar303Theme.cyan,
                    isActive: model.value(slot.parameter(.pingPong)) >= 0.5
                ) {
                    model.toggle(slot.parameter(.pingPong))
                }
            }
        }
        .frame(height: 96, alignment: .topLeading)
    }

    private func fxKnob(
        _ id: Vinegar303Parameter,
        label: String,
        accent: Color
    ) -> some View {
        let spec = Vinegar303ParameterCatalog.spec(id)
        return Vinegar303Knob(
            label: label,
            valueText: model.displayValue(id),
            normalized: Binding(
                get: { model.normalized(id) },
                set: { model.setNormalized($0, for: id) }
            ),
            defaultNormalized: spec.normalized(spec.defaultValue),
            accent: accent,
            size: 44,
            onEditingChanged: { editing in
                if editing {
                    model.beginGesture(id)
                } else {
                    model.endGesture(id)
                }
            }
        )
    }

    private func addDelay() {
        guard let slot = model.addFX(.delay) else { return }
        selectedFXSlot = slot.rawValue
    }

    private func removeFX(_ slot: Vinegar303FXSlot) {
        model.removeFX(slot)
        selectedFXSlot = model.fxActiveSlots.first?.rawValue
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

private struct Vinegar303FXDropDelegate: DropDelegate {
    let target: Vinegar303FXSlot
    let model: ParameterModel
    @Binding var dragging: Int?

    func dropEntered(info: DropInfo) {
        guard let dragging,
              dragging != target.rawValue,
              let source = Vinegar303FXSlot(rawValue: dragging)
        else { return }

        let active = model.fxActiveSlots
        guard let sourceIndex = active.firstIndex(of: source),
              let destinationIndex = active.firstIndex(of: target)
        else { return }

        model.moveFX(from: sourceIndex, to: destinationIndex)
        self.dragging = target.rawValue
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
