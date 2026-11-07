import SwiftUI

// MARK: - Environment

private struct Vinegar303MIDIControllerKey: EnvironmentKey {
    static let defaultValue: Vinegar303MIDIController? = nil
}

extension EnvironmentValues {
    var vinegar303MIDIController: Vinegar303MIDIController? {
        get { self[Vinegar303MIDIControllerKey.self] }
        set { self[Vinegar303MIDIControllerKey.self] = newValue }
    }
}

// MARK: - Learn badge

struct Vinegar303MIDILearnBadge: View {
    @ObservedObject var midi: Vinegar303MIDIController
    let target: Vinegar303MIDILearnTarget

    private var isArmed: Bool {
        midi.learnTarget == target
    }

    var body: some View {
        Button {
            midi.armLearn(target)
        } label: {
            Text("L")
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundStyle(isArmed ? Vinegar303Theme.onAccent : Vinegar303Theme.amber)
                .frame(width: 14, height: 14)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isArmed ? Vinegar303Theme.amber : Vinegar303Theme.insetStrong)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Vinegar303Theme.amber.opacity(isArmed ? 0.9 : 0.45), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(
            isArmed
                ? "Waiting for a MIDI CC or pad note..."
                : "MIDI learn: bind the next CC or pad note to \(target.label)"
        )
    }
}

/// Observes the controller so showing or hiding Learn badges does not require
/// the entire editor to redraw.
private struct Vinegar303MIDILearnBadgeAnchor: View {
    @ObservedObject var midi: Vinegar303MIDIController
    let target: Vinegar303MIDILearnTarget

    var body: some View {
        if midi.learnBadgesVisible {
            Vinegar303MIDILearnBadge(midi: midi, target: target)
        }
    }
}

extension View {
    func vinegar303LearnBadge(
        for parameter: Vinegar303Parameter,
        midi: Vinegar303MIDIController?
    ) -> some View {
        vinegar303LearnBadge(for: .parameter(parameter), midi: midi)
    }

    func vinegar303LearnBadge(
        for target: Vinegar303MIDILearnTarget,
        midi: Vinegar303MIDIController?,
        alignment: Alignment = .topTrailing,
        offset: CGSize = CGSize(width: 4, height: -3)
    ) -> some View {
        overlay(alignment: alignment) {
            if let midi {
                Vinegar303MIDILearnBadgeAnchor(midi: midi, target: target)
                    .offset(offset)
            }
        }
    }
}

// MARK: - Standalone MIDI panel

struct Vinegar303MIDIPanel: View {
    @ObservedObject var midi: Vinegar303MIDIController

    @State private var profileName: String
    @State private var showingAllBindings = false
    @State private var isSavingProfile = false
    @State private var showingDeleteConfirmation = false
    @FocusState private var profileNameFocused: Bool

    private let channelOptions = ["OMNI"] + (1...16).map(String.init)

    init(midi: Vinegar303MIDIController) {
        self.midi = midi
        _profileName = State(initialValue: Self.editableName(for: midi.profile.name))
    }

    private var selectedProfileIndex: Int? {
        midi.profileNames.firstIndex(of: midi.profile.name)
    }

    private var learnLabel: String {
        guard midi.learnBadgesVisible else { return "LEARN: OFF" }
        guard let target = midi.learnTarget else { return "LEARN: ON" }
        return "LEARN: \(target.label)"
    }

    private var canDeleteProfile: Bool {
        let name = midi.profile.name
        return name != Vinegar303MIDIProfile.noneName
            && name != Vinegar303MIDIProfile.launchkeyMiniName
    }

    private static func editableName(for profileName: String) -> String {
        profileName == Vinegar303MIDIProfile.noneName ? "" : profileName
    }

    var body: some View {
        Vinegar303Panel("MIDI", accent: Vinegar303Theme.cyan) {
            HStack(alignment: .top, spacing: 14) {
                inputColumn
                    .frame(width: 430, alignment: .leading)

                Rectangle()
                    .fill(Vinegar303Theme.border)
                    .frame(width: 1)
                    .padding(.vertical, 2)

                mappingsColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: midi.profile.name) { newName in
            profileName = Self.editableName(for: newName)
            isSavingProfile = false
            showingDeleteConfirmation = false
        }
        .alert("Delete MIDI profile?", isPresented: $showingDeleteConfirmation) {
            Button("DELETE", role: .destructive) {
                _ = midi.deleteProfile(named: midi.profile.name)
            }
            Button("CANCEL", role: .cancel) {}
        } message: {
            Text("Remove “\(midi.profile.name)”? This deletes its JSON mapping file; sound presets are unaffected.")
        }
    }

    private var inputColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(midi.connectedDeviceNames.isEmpty ? Vinegar303Theme.amber : Vinegar303Theme.acid)
                    .frame(width: 4, height: 4)
                Text(midi.inputStatus.uppercased())
                    .font(Vinegar303Theme.monoSmall)
                    .tracking(0.8)
                    .foregroundStyle(
                        midi.connectedDeviceNames.isEmpty
                            ? Vinegar303Theme.amber
                            : Vinegar303Theme.dim
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                Button {
                    midi.setLearnBadgesVisible(!midi.learnBadgesVisible)
                } label: {
                    Text(learnLabel)
                        .font(Vinegar303Theme.monoSmall)
                        .tracking(0.6)
                        .foregroundStyle(
                            midi.learnBadgesVisible
                                ? (midi.isLearning ? Vinegar303Theme.amber : Vinegar303Theme.acid)
                                : Vinegar303Theme.faint
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(
                                    midi.learnBadgesVisible
                                        ? Vinegar303Theme.acid.opacity(0.10)
                                        : Vinegar303Theme.controlFillSubtle
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(
                                    midi.learnBadgesVisible
                                        ? Vinegar303Theme.acid.opacity(0.35)
                                        : Vinegar303Theme.border,
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .help("Show or hide MIDI Learn badges on the mapped controls")
            }

            HStack(spacing: 5) {
                Text(
                    midi.launchkeyEditModeEnabled
                        ? "EDIT MODE: GATES + NOTE KNOBS · SHIFT = BOTTOM"
                        : "PATTERN PADS: 01–16 · RECORD = EDIT"
                )
                .font(Vinegar303Theme.monoSmall)
                .tracking(0.6)
                .foregroundStyle(
                    midi.launchkeyEditModeEnabled
                        ? Vinegar303Theme.acid
                        : Vinegar303Theme.faint
                )
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                Spacer(minLength: 4)

                if midi.learnBadgesVisible {
                    Text("SHIFT")
                        .font(Vinegar303Theme.monoSmall)
                        .tracking(0.6)
                        .foregroundStyle(Vinegar303Theme.faint)
                    Vinegar303MIDILearnBadge(midi: midi, target: .shift)
                }
            }

            HStack(spacing: 8) {
                Vinegar303MenuChip(
                    caption: "CHANNEL",
                    value: midi.profile.channelLabel,
                    accent: Vinegar303Theme.cyan,
                    isActive: true,
                    options: channelOptions,
                    selectedIndex: midi.profile.channel
                ) { index in
                    midi.setChannel(index)
                }

                Vinegar303MenuChip(
                    caption: "PROFILE",
                    value: midi.profile.name,
                    accent: Vinegar303Theme.cyan,
                    options: midi.profileNames,
                    selectedIndex: selectedProfileIndex
                ) { index in
                    guard midi.profileNames.indices.contains(index) else { return }
                    midi.loadProfile(named: midi.profileNames[index])
                }

                if midi.isLearning {
                    Button("CANCEL") {
                        midi.cancelLearn()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Vinegar303Theme.amber)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Vinegar303Theme.amber.opacity(0.10))
                    )
                }
            }

            HStack(spacing: 6) {
                if isSavingProfile {
                    TextField("Profile name", text: $profileName)
                        .textFieldStyle(.plain)
                        .font(Vinegar303Theme.monoSmall)
                        .padding(.horizontal, 7)
                        .frame(minWidth: 110, maxWidth: 160, minHeight: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Vinegar303Theme.track)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Vinegar303Theme.border, lineWidth: 1)
                        )
                        .focused($profileNameFocused)
                        .onSubmit { saveProfile() }

                    Button("SAVE AS") { saveProfile() }
                        .buttonStyle(.plain)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Vinegar303Theme.acid)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Vinegar303Theme.acid.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Vinegar303Theme.acid.opacity(0.3), lineWidth: 1)
                        )

                    Button("CANCEL") {
                        profileName = Self.editableName(for: midi.profile.name)
                        isSavingProfile = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Vinegar303Theme.faint)
                    .frame(height: 24)
                } else {
                    Button("SAVE PROFILE...") {
                        profileName = Self.editableName(for: midi.profile.name)
                        isSavingProfile = true
                        DispatchQueue.main.async {
                            profileNameFocused = true
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Vinegar303Theme.acid)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Vinegar303Theme.acid.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Vinegar303Theme.acid.opacity(0.3), lineWidth: 1)
                    )
                    .help("Save the current MIDI mapping as a controller profile")
                }

                Spacer(minLength: 2)

                if canDeleteProfile {
                    Button("DELETE") {
                        showingDeleteConfirmation = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Vinegar303Theme.amber)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Vinegar303Theme.amber.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Vinegar303Theme.amber.opacity(0.3), lineWidth: 1)
                    )
                    .help("Delete the current MIDI mapping profile")
                }

                Button("LAUNCHKEY") {
                    midi.resetToLaunchkeyMini()
                }
                .buttonStyle(.plain)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Vinegar303Theme.dim)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Vinegar303Theme.controlFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Vinegar303Theme.border, lineWidth: 1)
                )
            }

            Text(
                midi.learnBadgesVisible
                    ? "CLICK AN L BADGE, THEN MOVE A CC OR PRESS A PAD"
                    : "ENABLE LEARN TO MAP MIDI CONTROLS"
            )
            .font(Vinegar303Theme.monoSmall)
            .tracking(0.6)
            .foregroundStyle(Vinegar303Theme.faint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
    }

    private var mappingsColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("MAPPINGS")
                    .font(Vinegar303Theme.monoSmall)
                    .tracking(1.0)
                    .foregroundStyle(Vinegar303Theme.faint)
                Text("\(midi.profile.bindings.count)")
                    .font(Vinegar303Theme.monoSmall)
                    .foregroundStyle(Vinegar303Theme.faint)
                Spacer(minLength: 6)
                Text("CC + NOTES + PITCH BEND")
                    .font(Vinegar303Theme.monoSmall)
                    .tracking(0.6)
                    .foregroundStyle(Vinegar303Theme.faint)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(visibleBindings) { binding in
                        bindingChip(binding)
                    }
                }
            }
            .frame(height: 28)

            Button(showingAllBindings ? "SHOW LESS" : "SHOW ALL \(midi.profile.bindings.count)") {
                showingAllBindings.toggle()
            }
            .buttonStyle(.plain)
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .foregroundStyle(Vinegar303Theme.faint)
        }
    }

    private var visibleBindings: [Vinegar303MIDIBinding] {
        if showingAllBindings {
            return midi.profile.bindings
        }
        return Array(midi.profile.bindings.prefix(14))
    }

    private func saveProfile() {
        let saved = midi.saveProfile(named: profileName)
        profileName = saved.name
        isSavingProfile = false
    }

    private func bindingChip(_ binding: Vinegar303MIDIBinding) -> some View {
        HStack(spacing: 4) {
            Text(binding.summary)
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .foregroundStyle(Vinegar303Theme.dim)
                .lineLimit(1)

            Button {
                midi.removeBinding(binding)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(Vinegar303Theme.faint)
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .help("Remove this mapping")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Vinegar303Theme.controlFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Vinegar303Theme.border, lineWidth: 1)
        )
    }
}
