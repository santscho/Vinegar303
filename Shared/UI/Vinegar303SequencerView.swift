import AudioToolbox
import SwiftUI

/// 16-step editor with a pitch lane, per-step note drag and gate/accent/slide
/// toggles. A TimelineView polls the audio unit's playhead so the UI stays in
/// sync without coupling the render thread to SwiftUI.
struct Vinegar303SequencerPanel: View {
    @ObservedObject var model: ParameterModel
    @ObservedObject var patterns: PatternStore
    @ObservedObject var presets: Vinegar303PresetController
    @Binding var showingPresetManager: Bool
    let playhead: (() -> Int)?
    let midi: Vinegar303MIDIController?

    private var patternIndex: Int {
        min(max(Int(model.value(.pattern).rounded()), 0), Vinegar303PatternLibrary.patternCount - 1)
    }

    private var patternLength: Int {
        pattern.length
    }

    private var pattern: Vinegar303Pattern {
        patterns.patterns.indices.contains(patternIndex)
            ? patterns.patterns[patternIndex]
            : .empty()
    }

    var body: some View {
        Vinegar303Panel("SEQUENCER", accent: Vinegar303Theme.acid) {
            VStack(spacing: 12) {
                header

                TimelineView(.periodic(from: .now, by: 0.066)) { _ in
                    let active = playhead?() ?? -1
                    VStack(spacing: 10) {
                        Vinegar303PatternLane(
                            pattern: pattern,
                            length: patternLength,
                            activeStep: active
                        )
                        .frame(height: 74)

                        steps(activeStep: active)
                    }
                }

                legend
            }
        }
        .onAppear {
            synchronizePatternLength()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("PATTERN")
                .font(Vinegar303Theme.monoSmall)
                .tracking(1.2)
                .foregroundStyle(Vinegar303Theme.faint)

            Vinegar303Stepper(
                value: String(format: "%02d", patternIndex + 1),
                onBack: { model.adjust(.pattern, by: -1) },
                onForward: { model.adjust(.pattern, by: 1) }
            )

            Spacer(minLength: 8)

            Text("LENGTH")
                .font(Vinegar303Theme.monoSmall)
                .tracking(1.2)
                .foregroundStyle(Vinegar303Theme.faint)

            Vinegar303Stepper(
                value: "\(patternLength)",
                onBack: { setPatternLength(patternLength - 1) },
                onForward: { setPatternLength(patternLength + 1) }
            )
            .vinegar303LearnBadge(
                for: .patternLengthDecrease,
                midi: midi,
                alignment: .topLeading,
                offset: CGSize(width: -4, height: -3)
            )
            .vinegar303LearnBadge(
                for: .patternLengthIncrease,
                midi: midi,
                alignment: .topTrailing,
                offset: CGSize(width: 4, height: -3)
            )

            if let midi {
                Vinegar303EditModeChip(midi: midi)
                    .vinegar303LearnBadge(for: .editMode, midi: midi)
            }

            Spacer(minLength: 12)

            Vinegar303PresetBrowser(
                presets: presets,
                showingManager: $showingPresetManager
            )
        }
    }

    private func setPatternLength(_ length: Int) {
        let clamped = min(max(length, 1), Vinegar303PatternLibrary.stepsPerPattern)
        patterns.setLength(pattern: patternIndex, length: clamped)
        model.setValueWithGesture(AUValue(clamped), for: .patternLength)
    }

    private func synchronizePatternLength() {
        guard patterns.patterns.indices.contains(patternIndex) else { return }
        let length = patterns.patterns[patternIndex].length
        if Int(model.value(.patternLength).rounded()) != length {
            model.setValue(AUValue(length), for: .patternLength)
        }
    }

    // MARK: Steps

    private func steps(activeStep: Int) -> some View {
        HStack(alignment: .top, spacing: 3) {
            ForEach(0..<Vinegar303PatternLibrary.stepsPerPattern, id: \.self) { index in
                let step = pattern.steps.indices.contains(index) ? pattern[index] : .rest
                let isWithinLength = index < patternLength
                let isActive = isWithinLength && activeStep == index

                VStack(spacing: 4) {
                    Text(String(format: "%02d", index + 1))
                        .font(Vinegar303Theme.monoSmall)
                        .foregroundStyle(isActive ? Vinegar303Theme.acid : Vinegar303Theme.faint)

                    Vinegar303NoteCell(
                        note: step.note,
                        isEnabled: step.gate && isWithinLength,
                        onChange: { patterns.setNote(pattern: patternIndex, index: index, note: $0) }
                    )
                    .vinegar303LearnBadge(for: .stepNote(index), midi: midi)

                    Vinegar303ToggleDot(
                        symbol: "G",
                        isOn: step.gate,
                        accent: Vinegar303Theme.acid
                    ) {
                        patterns.toggleGate(pattern: patternIndex, index: index)
                    }
                    .vinegar303LearnBadge(for: .stepGate(index), midi: midi)

                    Vinegar303ToggleDot(
                        symbol: "A",
                        isOn: step.accent,
                        accent: Vinegar303Theme.amber
                    ) {
                        patterns.toggleAccent(pattern: patternIndex, index: index)
                    }
                    .vinegar303LearnBadge(for: .stepAccent(index), midi: midi)

                    Vinegar303ToggleDot(
                        symbol: "S",
                        isOn: step.slide,
                        accent: Vinegar303Theme.cyan
                    ) {
                        patterns.toggleSlide(pattern: patternIndex, index: index)
                    }
                    .vinegar303LearnBadge(for: .stepSlide(index), midi: midi)
                }
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? Vinegar303Theme.acid.opacity(0.10) : Color.white.opacity(0.015))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isActive ? Vinegar303Theme.acid.opacity(0.42) : Vinegar303Theme.border.opacity(0.6),
                            lineWidth: 1
                        )
                )
                .opacity(isWithinLength ? 1 : 0.32)
                .vinegar303LearnBadge(for: .pattern(index), midi: midi)
            }
        }
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("G", "GATE", Vinegar303Theme.acid)
            legendItem("A", "ACCENT", Vinegar303Theme.amber)
            legendItem("S", "SLIDE", Vinegar303Theme.cyan)

            Spacer(minLength: 8)

            Text("DRAG NOTE ▲▼")
                .font(Vinegar303Theme.monoSmall)
                .tracking(0.8)
                .foregroundStyle(Vinegar303Theme.faint)
        }
    }

    private func legendItem(_ badge: String, _ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(badge)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.black)
                .frame(width: 13, height: 13)
                .background(RoundedRectangle(cornerRadius: 3).fill(color))
            Text(title)
                .font(Vinegar303Theme.monoSmall)
                .tracking(0.7)
                .foregroundStyle(Vinegar303Theme.faint)
        }
    }
}

// MARK: - Note cell

struct Vinegar303NoteCell: View {
    let note: Int
    let isEnabled: Bool
    let onChange: (Int) -> Void

    @State private var dragStartNote: Int?
    @State private var hovering = false

    var body: some View {
        Text(Vinegar303PatternLibrary.noteName(for: note))
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(isEnabled ? Vinegar303Theme.text : Vinegar303Theme.faint)
            .frame(maxWidth: .infinity)
            .frame(height: 21)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.black.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(hovering ? Vinegar303Theme.acid.opacity(0.5) : Vinegar303Theme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { gesture in
                        if dragStartNote == nil {
                            dragStartNote = note
                        }
                        let delta = Int((-gesture.translation.height / 9).rounded())
                        onChange(Vinegar303Step.clampNote((dragStartNote ?? note) + delta))
                    }
                    .onEnded { _ in
                        dragStartNote = nil
                    }
            )
            .onHover { hovering = $0 }
            .help("Drag vertically to change pitch")
    }
}

// MARK: - Pitch lane

private struct Vinegar303EditModeChip: View {
    @ObservedObject var midi: Vinegar303MIDIController

    var body: some View {
        Vinegar303Chip(
            caption: "EDIT MODE",
            value: midi.launchkeyEditModeEnabled ? "ON" : "OFF",
            accent: Vinegar303Theme.acid,
            isActive: midi.launchkeyEditModeEnabled
        ) {
            midi.setLaunchkeyEditMode(!midi.launchkeyEditModeEnabled)
        }
        .help(
            midi.launchkeyEditModeEnabled
                ? "Pads edit gates and knobs edit notes; turn off to select patterns"
                : "Pads select patterns 01–16; turn on to edit gates and notes"
        )
    }
}

struct Vinegar303PatternLane: View {
    let pattern: Vinegar303Pattern
    let length: Int
    let activeStep: Int

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 2
            let lane = CGRect(
                x: inset,
                y: inset,
                width: max(size.width - inset * 2, 1),
                height: max(size.height - inset * 2, 1)
            )

            context.fill(
                Path(roundedRect: lane, cornerRadius: 6),
                with: .color(Color.black.opacity(0.34))
            )

            // Horizontal grid.
            for row in 0...4 {
                let y = lane.minY + lane.height * CGFloat(row) / 4
                var line = Path()
                line.move(to: CGPoint(x: lane.minX, y: y))
                line.addLine(to: CGPoint(x: lane.maxX, y: y))
                context.stroke(line, with: .color(Color.white.opacity(0.04)), lineWidth: 1)
            }

            // Vertical step grid.
            for step in 0...Vinegar303PatternLibrary.stepsPerPattern {
                let x = lane.minX + lane.width * CGFloat(step) / CGFloat(Vinegar303PatternLibrary.stepsPerPattern)
                var line = Path()
                line.move(to: CGPoint(x: x, y: lane.minY))
                line.addLine(to: CGPoint(x: x, y: lane.maxY))
                context.stroke(line, with: .color(Color.white.opacity(0.035)), lineWidth: 1)
            }

            let stepWidth = lane.width / CGFloat(Vinegar303PatternLibrary.stepsPerPattern)
            let noteSpan = CGFloat(Vinegar303PatternLibrary.highestNote - Vinegar303PatternLibrary.lowestNote)

            func yPosition(for note: Int) -> CGFloat {
                let normalized = CGFloat(note - Vinegar303PatternLibrary.lowestNote) / noteSpan
                return lane.maxY - 10 - normalized * (lane.height - 20)
            }

            func xPosition(for index: Int) -> CGFloat {
                lane.minX + stepWidth * (CGFloat(index) + 0.5)
            }

            for index in 0..<Vinegar303PatternLibrary.stepsPerPattern {
                let step = pattern.steps.indices.contains(index) ? pattern[index] : .rest
                let enabled = index < length
                let x = xPosition(for: index)
                let y = yPosition(for: step.note)

                if step.slide, enabled, index + 1 < length {
                    let next = pattern.steps.indices.contains(index + 1) ? pattern[index + 1] : .rest
                    var glide = Path()
                    glide.move(to: CGPoint(x: x + 3, y: y))
                    glide.addLine(to: CGPoint(x: xPosition(for: index + 1) - 3, y: yPosition(for: next.note)))
                    context.stroke(
                        glide,
                        with: .color(Vinegar303Theme.cyan.opacity(0.55)),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round)
                    )
                }

                if enabled && step.gate {
                    let dot = CGRect(x: x - 3.2, y: y - 3.2, width: 6.4, height: 6.4)
                    context.fill(Path(ellipseIn: dot), with: .color(Vinegar303Theme.acid.opacity(0.92)))
                } else {
                    let dot = CGRect(x: x - 2.2, y: y - 2.2, width: 4.4, height: 4.4)
                    context.fill(Path(ellipseIn: dot), with: .color(Vinegar303Theme.faint.opacity(0.6)))
                }

                if step.accent, enabled {
                    let ring = CGRect(x: x - 6.5, y: y - 6.5, width: 13, height: 13)
                    context.stroke(
                        Path(ellipseIn: ring),
                        with: .color(Vinegar303Theme.amber.opacity(0.9)),
                        lineWidth: 1.2
                    )
                }
            }

            if activeStep >= 0, activeStep < Vinegar303PatternLibrary.stepsPerPattern {
                let x = xPosition(for: activeStep)
                var playhead = Path()
                playhead.move(to: CGPoint(x: x, y: lane.minY + 3))
                playhead.addLine(to: CGPoint(x: x, y: lane.maxY - 3))
                context.stroke(
                    playhead,
                    with: .color(Vinegar303Theme.acid.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.012))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Vinegar303Theme.border, lineWidth: 1)
        )
    }
}
