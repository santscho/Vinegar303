import AudioToolbox
import Combine
import Darwin
import Foundation

// MARK: - Incoming messages

public enum Vinegar303MIDIMessage: Equatable {
    case noteOn(channel: Int, note: Int, velocity: Int)
    case noteOff(channel: Int, note: Int)
    case controlChange(channel: Int, controller: Int, value: Int)
    case pitchBend(channel: Int, value: Int)

    public var channel: Int {
        switch self {
        case .noteOn(let channel, _, _),
             .noteOff(let channel, _),
             .controlChange(let channel, _, _),
             .pitchBend(let channel, _):
            return channel
        }
    }

    /// Parses a complete CoreMIDI packet. The parser carries running status
    /// across messages and ignores realtime/system messages that the mapper
    /// does not consume.
    public static func parse(_ bytes: [UInt8]) -> [Vinegar303MIDIMessage] {
        var result: [Vinegar303MIDIMessage] = []
        var index = 0
        var runningStatus: UInt8?

        while index < bytes.count {
            let byte = bytes[index]

            // Realtime messages can appear between any two MIDI bytes.
            if byte >= 0xF8 {
                index += 1
                continue
            }

            let status: UInt8
            if byte >= 0x80 {
                runningStatus = byte
                status = byte
                index += 1

                if status >= 0xF0 {
                    // System common messages are not part of the mapping model.
                    runningStatus = nil
                    continue
                }
            } else {
                guard let current = runningStatus else {
                    index += 1
                    continue
                }
                status = current
            }

            let type = status & 0xF0
            let channel = Int(status & 0x0F) + 1

            switch type {
            case 0x80, 0x90, 0xB0:
                guard index + 1 < bytes.count else { return result }
                let data1 = Int(bytes[index])
                let data2 = Int(bytes[index + 1])
                index += 2

                switch type {
                case 0x80:
                    result.append(.noteOff(channel: channel, note: data1))
                case 0x90:
                    if data2 == 0 {
                        result.append(.noteOff(channel: channel, note: data1))
                    } else {
                        result.append(
                            .noteOn(channel: channel, note: data1, velocity: data2)
                        )
                    }
                default:
                    result.append(
                        .controlChange(
                            channel: channel,
                            controller: data1,
                            value: data2
                        )
                    )
                }

            case 0xE0:
                guard index + 1 < bytes.count else { return result }
                let lsb = Int(bytes[index])
                let msb = Int(bytes[index + 1])
                index += 2
                result.append(
                    .pitchBend(channel: channel, value: lsb | (msb << 7))
                )

            default:
                // Unsupported channel/system message: discard its data bytes.
                while index < bytes.count, bytes[index] < 0x80 {
                    index += 1
                }
            }
        }

        return result
    }
}

// MARK: - Learn targets

/// Every control in the standalone editor that can be driven by MIDI.
/// AU parameters, sequencer pads, transport functions and note selectors are
/// all represented here so Learn is not limited to continuous CC parameters.
public enum Vinegar303MIDILearnTarget: Hashable {
    case parameter(Vinegar303Parameter)
    case pattern(Int)
    case stepGate(Int)
    case stepAccent(Int)
    case stepSlide(Int)
    case stepNote(Int)
    case editMode
    case shift
    case patternLengthDecrease
    case patternLengthIncrease

    public var label: String {
        switch self {
        case .parameter(let parameter):
            return Vinegar303ParameterCatalog.spec(parameter).name.uppercased()
        case .pattern(let index):
            return "PATTERN \(String(format: "%02d", index + 1))"
        case .stepGate(let index):
            return "GATE \(String(format: "%02d", index + 1))"
        case .stepAccent(let index):
            return "ACCENT \(String(format: "%02d", index + 1))"
        case .stepSlide(let index):
            return "SLIDE \(String(format: "%02d", index + 1))"
        case .stepNote(let index):
            return "NOTE \(String(format: "%02d", index + 1))"
        case .editMode:
            return "EDIT MODE"
        case .shift:
            return "SHIFT"
        case .patternLengthDecrease:
            return "LENGTH −"
        case .patternLengthIncrease:
            return "LENGTH +"
        }
    }
}

// MARK: - Bindings and profiles

public struct Vinegar303MIDIBinding: Codable, Hashable, Identifiable {
    public enum Source: String, Codable {
        case controlChange
        case noteOn
        case pitchBend
    }

    public enum Target: String, Codable {
        case parameter
        case pattern
        case stepGate
        case stepAccent
        case stepSlide
        case stepNote
        case editMode
        case shift
        case patternLengthDecrease
        case patternLengthIncrease
    }

    public var id: String {
        [
            source.rawValue,
            number.map(String.init) ?? "-",
            target.rawValue,
            parameter ?? "-",
            index.map(String.init) ?? "-",
        ].joined(separator: ":")
    }

    public var source: Source
    public var number: Int?
    public var target: Target
    public var parameter: String?
    public var index: Int?

    public init(
        source: Source,
        number: Int? = nil,
        target: Target,
        parameter: String? = nil,
        index: Int? = nil
    ) {
        self.source = source
        self.number = number
        self.target = target
        self.parameter = parameter
        self.index = index
    }

    public var sourceLabel: String {
        switch source {
        case .controlChange:
            return "CC \(number ?? 0)"
        case .noteOn:
            return "N\(number ?? 0)"
        case .pitchBend:
            return "PB"
        }
    }

    public var targetLabel: String {
        switch target {
        case .parameter:
            guard let parameter else { return "PARAM" }
            return Vinegar303ParameterCatalog.all
                .first { $0.identifier == parameter }?
                .name.uppercased() ?? parameter.uppercased()
        case .pattern:
            return "PAT \(String(format: "%02d", (index ?? 0) + 1))"
        case .stepGate:
            return "GATE \(String(format: "%02d", (index ?? 0) + 1))"
        case .stepAccent:
            return "ACC \(String(format: "%02d", (index ?? 0) + 1))"
        case .stepSlide:
            return "SLIDE \(String(format: "%02d", (index ?? 0) + 1))"
        case .stepNote:
            return "NOTE \(String(format: "%02d", (index ?? 0) + 1))"
        case .editMode:
            return "EDIT MODE"
        case .shift:
            return "SHIFT"
        case .patternLengthDecrease:
            return "LENGTH −"
        case .patternLengthIncrease:
            return "LENGTH +"
        }
    }

    public var summary: String {
        "\(sourceLabel) \u{2192} \(targetLabel)"
    }
}

public struct Vinegar303MIDIProfile: Codable, Hashable, Identifiable {
    public static let noneName = "None"
    public static let launchkeyMiniName = "Launchkey Mini"

    /// 0 means Omni; 1...16 select one MIDI channel.
    public var channel: Int
    public var name: String
    public var bindings: [Vinegar303MIDIBinding]

    public var id: String { name }

    public init(
        name: String,
        channel: Int = 1,
        bindings: [Vinegar303MIDIBinding] = []
    ) {
        self.name = name
        self.channel = min(max(channel, 0), 16)
        self.bindings = bindings
    }

    public var channelLabel: String {
        channel == 0 ? "OMNI" : "CH \(channel)"
    }

    /// Empty default profile. It is built into the app and is never written to
    /// the profiles directory.
    public static var none: Vinegar303MIDIProfile {
        Vinegar303MIDIProfile(name: noneName, channel: 1, bindings: [])
    }

    public static var launchkeyMini: Vinegar303MIDIProfile {
        var bindings: [Vinegar303MIDIBinding] = []

        let ccParameters = [
            (21, "cutoff"),
            (22, "resonance"),
            (23, "envmod"),
            (24, "decay"),
            (25, "accent"),
            (26, "tuning"),
            (27, "volume"),
            (28, "tempo"),
        ]
        for (controller, parameter) in ccParameters {
            bindings.append(
                Vinegar303MIDIBinding(
                    source: .controlChange,
                    number: controller,
                    target: .parameter,
                    parameter: parameter
                )
            )
        }

        // Launchkey-style pads select the 16 sequencer patterns.
        for note in 36...51 {
            bindings.append(
                Vinegar303MIDIBinding(
                    source: .noteOn,
                    number: note,
                    target: .pattern,
                    index: note - 36
                )
            )
        }

        // The next chromatic octave toggles step gates in the current pattern.
        for note in 52...67 {
            bindings.append(
                Vinegar303MIDIBinding(
                    source: .noteOn,
                    number: note,
                    target: .stepGate,
                    index: note - 52
                )
            )
        }

        // The next octave toggles accents in the current pattern.
        for note in 68...83 {
            bindings.append(
                Vinegar303MIDIBinding(
                    source: .noteOn,
                    number: note,
                    target: .stepAccent,
                    index: note - 68
                )
            )
        }

        bindings.append(
            Vinegar303MIDIBinding(
                source: .pitchBend,
                target: .parameter,
                parameter: "tuning"
            )
        )

        return Vinegar303MIDIProfile(
            name: launchkeyMiniName,
            channel: 1,
            bindings: bindings
        )
    }
}

/// Launchkey Mini MK3 pad layout in DAW/Session mode. The top row runs
/// left-to-right from note 96 to 103, and the bottom row from 112 to 119.
/// These pads are treated as a dedicated gate layer so the controller's
/// keyboard range remains available to the user's normal note bindings.
public enum Vinegar303LaunchkeyPadMap {
    public static let topNotes: [Int] = Array(96...103)
    public static let bottomNotes: [Int] = Array(112...119)
    public static let allNotes: [Int] = topNotes + bottomNotes
    public static let redVelocity: UInt8 = 5
    public static let greenVelocity: UInt8 = 19
    public static let knobControllers = 21...28
    public static let noteKnobModeController = 117
    public static let shiftController = 108
    public static let trackLeftController = 103
    public static let trackRightController = 102

    public static func gateIndex(for note: Int) -> Int? {
        if let index = topNotes.firstIndex(of: note) {
            return index
        }
        if let index = bottomNotes.firstIndex(of: note) {
            return topNotes.count + index
        }
        return nil
    }

    public static func note(forGate gate: Int) -> Int? {
        guard (0..<allNotes.count).contains(gate) else { return nil }
        return allNotes[gate]
    }

    /// Maps a DAW knob (CC 21–28) to the matching gate. The lower or upper
    /// row is selected by the SHIFT modifier, giving eight physical knobs two
    /// independent pad assignments each.
    public static func noteKnobIndex(for controller: Int, bottomRow: Bool) -> Int? {
        guard knobControllers.contains(controller) else { return nil }
        return controller - knobControllers.lowerBound + (bottomRow ? topNotes.count : 0)
    }

    public static func ledMessage(
        forGate gate: Int,
        color: Vinegar303LaunchkeyPadColor
    ) -> [UInt8]? {
        guard let note = note(forGate: gate) else { return nil }
        return [0x90, UInt8(note & 0x7F), color.velocity]
    }

    /// Resolves the physical pads that represent a sequencer step for the red
    /// transport-follow LED. Learned pad assignments take precedence over the
    /// default step column; if that column's pad has been repurposed, it no
    /// longer lights for the old step.
    public static func transportGateIndices(
        forStep step: Int,
        bindings: [Vinegar303MIDIBinding]
    ) -> [Int] {
        guard (0..<allNotes.count).contains(step) else { return [] }

        var claimedPads = Set<Int>()
        var stepPads = Set<Int>()
        for binding in bindings {
            guard binding.source == .noteOn,
                  let number = binding.number,
                  let pad = gateIndex(for: number)
            else { continue }

            claimedPads.insert(pad)
            if binding.index == step, binding.target.isStepScoped {
                stepPads.insert(pad)
            }
        }

        if !stepPads.isEmpty {
            return stepPads.sorted()
        }
        return claimedPads.contains(step) ? [] : [step]
    }
}

private extension Vinegar303MIDIBinding.Target {
    var isStepScoped: Bool {
        switch self {
        case .stepGate, .stepAccent, .stepSlide, .stepNote:
            return true
        case .parameter, .pattern, .editMode, .shift,
             .patternLengthDecrease, .patternLengthIncrease:
            return false
        }
    }
}

public enum Vinegar303LaunchkeyPadColor: Equatable {
    case off
    case red
    case green

    public var velocity: UInt8 {
        switch self {
        case .off:
            return 0
        case .red:
            return Vinegar303LaunchkeyPadMap.redVelocity
        case .green:
            return Vinegar303LaunchkeyPadMap.greenVelocity
        }
    }
}

public enum Vinegar303MIDIAction: Equatable {
    case parameter(Vinegar303Parameter, AUValue)
    case pattern(Int)
    case stepGate(Int)
    case stepAccent(Int)
    case stepSlide(Int)
    case stepNote(Int, Int)
    case adjustPatternLength(Int)
}

// MARK: - Profile storage

public final class Vinegar303MIDIProfileStore {
    public static let defaultProfilesDirectoryName = "MIDI/Profiles"

    public let directoryURL: URL

    private let fileManager = FileManager.default
    private let activeProfileKey = "Vinegar303.MIDI.ActiveProfile"

    public init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL ?? Self.resolveDirectoryURL()
        try? fileManager.createDirectory(
            at: self.directoryURL,
            withIntermediateDirectories: true
        )
    }

    public var activeProfileName: String? {
        UserDefaults.standard.string(forKey: activeProfileKey)
    }

    public func setActiveProfileName(_ name: String) {
        UserDefaults.standard.set(name, forKey: activeProfileKey)
    }

    public func loadProfiles() -> [Vinegar303MIDIProfile] {
        let urls: [URL] = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var profiles: [Vinegar303MIDIProfile] = urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { (url: URL) -> Vinegar303MIDIProfile? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Vinegar303MIDIProfile.self, from: data)
            }
            .filter {
                $0.name.caseInsensitiveCompare(Vinegar303MIDIProfile.noneName) != .orderedSame
            }

        profiles.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return [.none] + profiles
    }

    public func save(_ profile: Vinegar303MIDIProfile) throws {
        guard profile.name.caseInsensitiveCompare(Vinegar303MIDIProfile.noneName)
            != .orderedSame else { return }
        let data = try JSONEncoder().encode(profile)
        try data.write(to: url(for: profile.name), options: .atomic)
    }

    public func delete(named name: String) throws {
        guard name.caseInsensitiveCompare(Vinegar303MIDIProfile.noneName)
            != .orderedSame else { return }
        let url = url(for: name)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func url(for name: String) -> URL {
        directoryURL.appendingPathComponent(Self.fileName(for: name), isDirectory: false)
    }

    private static func fileName(for name: String) -> String {
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return (cleaned.isEmpty ? "Profile" : cleaned) + ".json"
    }

    private static var realHomeDirectory: URL {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private static func resolveDirectoryURL() -> URL {
        let shared = realHomeDirectory
            .appendingPathComponent("Library/Application Support/Vinegar303", isDirectory: true)
            .appendingPathComponent(defaultProfilesDirectoryName, isDirectory: true)

        let probe = shared.appendingPathComponent(".vinegar303-midi-write-test")
        do {
            try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
            try Data().write(to: probe, options: .atomic)
            try? FileManager.default.removeItem(at: probe)
            return shared
        } catch {
            // Preserve a usable local profile store if the shared folder is
            // unavailable (for example in a differently sandboxed host).
        }

        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("Vinegar303", isDirectory: true)
            .appendingPathComponent(defaultProfilesDirectoryName, isDirectory: true)
    }
}

// MARK: - Mapping controller

public final class Vinegar303MIDIController: ObservableObject {
    public let store: Vinegar303MIDIProfileStore

    @Published public private(set) var profile: Vinegar303MIDIProfile
    @Published public private(set) var profiles: [Vinegar303MIDIProfile]
    @Published public private(set) var learnTarget: Vinegar303MIDILearnTarget?
    @Published public private(set) var inputStatus = "MIDI OFFLINE"
    @Published public private(set) var connectedDeviceNames: [String] = []
    @Published public private(set) var launchkeyEditModeEnabled = false
    @Published public private(set) var launchkeyShiftHeld = false
    @Published public private(set) var learnBadgesVisible = false

    private var noteKnobLastValues: [Int: Int] = [:]
    private var noteKnobPickupActive: [Int: Bool] = [:]
    private var actionControlStates: [String: Bool] = [:]
    private let noteKnobPickupTolerance = 1.5

    /// Supplies the current note at a step so the knob can pick it up before
    /// taking over. The standalone host wires this to the current pattern.
    public var noteForStep: ((Int) -> Int?)?

    public var onAction: ((Vinegar303MIDIAction) -> Void)?
    public var onUnmappedNote: ((Vinegar303MIDIMessage) -> Void)?

    public init(
        store: Vinegar303MIDIProfileStore = Vinegar303MIDIProfileStore(),
        profileName: String? = nil
    ) {
        self.store = store
        let loaded = store.loadProfiles()
        profiles = loaded
        let preferred = profileName ?? store.activeProfileName
        self.profile = loaded.first { $0.name == preferred }
            ?? loaded.first { $0.name == Vinegar303MIDIProfile.noneName }
            ?? .none
        store.setActiveProfileName(self.profile.name)
    }

    public var profileNames: [String] {
        profiles.map(\.name)
    }

    public var isLearning: Bool {
        learnTarget != nil
    }

    private var isNoneProfile: Bool {
        profile.name.caseInsensitiveCompare(Vinegar303MIDIProfile.noneName) == .orderedSame
    }

    public var launchkeyNoteKnobRow: String {
        launchkeyShiftHeld ? "BOTTOM" : "TOP"
    }

    public func receive(_ message: Vinegar303MIDIMessage) {
        guard accepts(channel: message.channel) || isLaunchkeyControl(message) else {
            return
        }

        // Learn accepts both CC controls and pad notes. Capture before the
        // Launchkey's hard-coded pad/transport handling so those controls can
        // themselves be remapped.
        if let learnTarget, let source = learnSource(for: message) {
            learn(
                source: source.source,
                number: source.number,
                target: learnTarget
            )
            return
        }

        // None is a real bypass, not just an empty binding list. The
        // Launchkey's pad grid, note knobs, shift row and track shortcuts are
        // hard-coded outside profiles, so they must be suppressed here too.
        // Notes still reach the synth as ordinary MIDI input.
        if isNoneProfile {
            switch message {
            case .noteOn, .noteOff:
                onUnmappedNote?(message)
            case .controlChange, .pitchBend:
                break
            }
            return
        }

        switch message {
        case .noteOn(_, let note, let velocity):
            if velocity == 0 {
                onUnmappedNote?(message)
                return
            }
            if let binding = binding(for: message) {
                apply(binding, normalized: 1, pressed: true)
                return
            }
            if let gate = Vinegar303LaunchkeyPadMap.gateIndex(for: note) {
                onAction?(
                    launchkeyEditModeEnabled ? .stepGate(gate) : .pattern(gate)
                )
                return
            }
            onUnmappedNote?(message)

        case .noteOff(_, let note):
            if let binding = noteBinding(for: note) {
                release(binding)
            }
            onUnmappedNote?(message)

        case .controlChange(_, let controller, let value):
            if !launchkeyEditModeEnabled,
               message.channel == 16,
               Vinegar303LaunchkeyPadMap.knobControllers.contains(controller) {
                noteKnobLastValues[controller] = value
            }
            if controller == Vinegar303LaunchkeyPadMap.shiftController {
                if let binding = binding(for: message) {
                    apply(
                        binding,
                        normalized: Double(value) / 127.0,
                        pressed: value > 0
                    )
                } else {
                    setShiftHeld(value > 0)
                }
                return
            }
            if controller == Vinegar303LaunchkeyPadMap.noteKnobModeController {
                if let binding = binding(for: message) {
                    apply(
                        binding,
                        normalized: Double(value) / 127.0,
                        pressed: value > 0
                    )
                } else if value > 0 {
                    toggleLaunchkeyEditMode()
                }
                return
            }
            if message.channel == 16,
               (controller == Vinegar303LaunchkeyPadMap.trackLeftController
                    || controller == Vinegar303LaunchkeyPadMap.trackRightController) {
                if let binding = binding(for: message) {
                    apply(
                        binding,
                        normalized: Double(value) / 127.0,
                        pressed: value > 0
                    )
                    return
                }
                if launchkeyShiftHeld && value > 0 {
                    onAction?(
                        .adjustPatternLength(
                            controller == Vinegar303LaunchkeyPadMap.trackRightController
                                ? 1
                                : -1
                        )
                    )
                }
                return
            }
            if launchkeyEditModeEnabled,
               let index = Vinegar303LaunchkeyPadMap.noteKnobIndex(
                   for: controller,
                   bottomRow: launchkeyShiftHeld
               ) {
                handleNoteKnob(controller: controller, value: value, index: index)
                return
            }
            guard let binding = binding(for: message) else { return }
            apply(
                binding,
                normalized: Double(value) / 127.0,
                pressed: value > 0
            )

        case .pitchBend(_, let value):
            guard let binding = binding(for: message) else { return }
            apply(binding, normalized: Double(value) / 16_383.0, pressed: true)
        }
    }

    public func armLearn(_ parameter: Vinegar303Parameter) {
        armLearn(.parameter(parameter))
    }

    public func armLearn(_ target: Vinegar303MIDILearnTarget) {
        noteKnobPickupActive.removeAll()
        learnTarget = target
    }

    public func cancelLearn() {
        learnTarget = nil
    }

    public func setLearnBadgesVisible(_ visible: Bool) {
        guard visible != learnBadgesVisible else { return }
        learnBadgesVisible = visible
        if !visible {
            cancelLearn()
        }
    }

    public func setLaunchkeyEditMode(_ enabled: Bool) {
        guard !isNoneProfile else { return }
        guard enabled != launchkeyEditModeEnabled else { return }
        launchkeyEditModeEnabled = enabled
        learnTarget = nil
        noteKnobPickupActive.removeAll()
    }

    private func setShiftHeld(_ held: Bool) {
        guard held != launchkeyShiftHeld else { return }
        launchkeyShiftHeld = held
        noteKnobPickupActive.removeAll()
    }

    public func setChannel(_ channel: Int) {
        var next = profile
        next.channel = min(max(channel, 0), 16)
        profile = next
        persistProfile()
    }

    public func loadProfile(named name: String) {
        guard let next = profiles.first(where: { $0.name == name }) else { return }
        profile = next
        store.setActiveProfileName(next.name)
        learnTarget = nil
        resetLaunchkeyInteractionState()
    }

    @discardableResult
    public func saveProfile(named name: String) -> Vinegar303MIDIProfile {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var resolvedName = cleanName.isEmpty ? profile.name : cleanName
        if resolvedName.caseInsensitiveCompare(Vinegar303MIDIProfile.noneName) == .orderedSame {
            resolvedName = uniqueProfileName(base: "New Mapping")
        }
        var next = profile
        next.name = resolvedName
        profile = next
        persistProfile()
        store.setActiveProfileName(resolvedName)
        return next
    }

    @discardableResult
    public func deleteProfile(named name: String) -> Bool {
        guard name != Vinegar303MIDIProfile.launchkeyMiniName,
              name.caseInsensitiveCompare(Vinegar303MIDIProfile.noneName) != .orderedSame,
              profiles.contains(where: { $0.name == name }) else {
            return false
        }

        do {
            try store.delete(named: name)
        } catch {
            return false
        }

        let remaining = store.loadProfiles()
        profiles = remaining
        if profile.name == name {
            let fallback = remaining.first {
                $0.name == Vinegar303MIDIProfile.noneName
            } ?? remaining.first ?? .none
            profile = fallback
            store.setActiveProfileName(fallback.name)
            learnTarget = nil
            resetLaunchkeyInteractionState()
        }
        return true
    }

    public func resetToLaunchkeyMini() {
        profile = .launchkeyMini
        persistProfile()
        store.setActiveProfileName(profile.name)
        learnTarget = nil
        resetLaunchkeyInteractionState()
    }

    public func removeBinding(_ binding: Vinegar303MIDIBinding) {
        var next = profile
        next.bindings.removeAll { $0.id == binding.id }
        profile = next
        persistProfile()
    }

    public func updateInputStatus(devices: [String]) {
        connectedDeviceNames = devices
        if devices.isEmpty {
            inputStatus = "MIDI NO DEVICES"
        } else if devices.count == 1 {
            inputStatus = "MIDI \(devices[0])"
        } else {
            inputStatus = "MIDI \(devices.count) DEVICES"
        }
    }

    public func reportInputError(_ message: String) {
        connectedDeviceNames = []
        inputStatus = "MIDI ERROR: \(message)"
    }

    private func accepts(channel: Int) -> Bool {
        profile.channel == 0 || profile.channel == channel
    }

    /// Accept the Launchkey's DAW-mode knob CCs and its mode buttons even when
    /// the active profile is filtering another channel. SHIFT selects the lower
    /// pad row; RECORD toggles EDIT MODE.
    private func isLaunchkeyControl(_ message: Vinegar303MIDIMessage) -> Bool {
        guard case .controlChange(let channel, let controller, _) = message else {
            return false
        }
        if controller == Vinegar303LaunchkeyPadMap.shiftController {
            return true
        }
        guard channel == 16 else { return false }
        return Vinegar303LaunchkeyPadMap.knobControllers.contains(controller)
            || controller == Vinegar303LaunchkeyPadMap.noteKnobModeController
            || controller == Vinegar303LaunchkeyPadMap.trackLeftController
            || controller == Vinegar303LaunchkeyPadMap.trackRightController
    }

    private func toggleLaunchkeyEditMode() {
        setLaunchkeyEditMode(!launchkeyEditModeEnabled)
    }

    private func noteKnobTargetCC(for note: Int) -> Double {
        let low = Vinegar303PatternLibrary.lowestNote
        let high = Vinegar303PatternLibrary.highestNote
        let clamped = min(max(note, low), high)
        return Double(clamped - low) / Double(high - low) * 127.0
    }

    private func noteKnobNote(for value: Int) -> Int {
        let low = Vinegar303PatternLibrary.lowestNote
        let high = Vinegar303PatternLibrary.highestNote
        let normalized = Double(min(max(value, 0), 127)) / 127.0
        return low + Int((normalized * Double(high - low)).rounded())
    }

    /// Pickup: the knob only takes over once it reaches the note currently on
    /// the pad. After that, the pot's full 0–127 travel maps to C1–C4.
    private func handleNoteKnob(controller: Int, value: Int, index: Int) {
        guard let targetNote = noteForStep?(index) else { return }

        let targetCC = noteKnobTargetCC(for: targetNote)
        let previous = noteKnobLastValues[controller]
        noteKnobLastValues[controller] = value

        if noteKnobPickupActive[controller] != true {
            let valueCC = Double(value)
            let crossed = abs(valueCC - targetCC) <= noteKnobPickupTolerance
                || previous.map { previousValue in
                    let previousCC = Double(previousValue)
                    return (previousCC < targetCC && valueCC >= targetCC)
                        || (previousCC > targetCC && valueCC <= targetCC)
                } ?? false
            guard crossed else { return }
            noteKnobPickupActive[controller] = true
        }

        onAction?(.stepNote(index, noteKnobNote(for: value)))
    }

    private func binding(for message: Vinegar303MIDIMessage) -> Vinegar303MIDIBinding? {
        profile.bindings.first { binding in
            switch (binding.source, message) {
            case (.controlChange, .controlChange(_, let controller, _)):
                return binding.number == controller
            case (.noteOn, .noteOn(_, let note, _)):
                return binding.number == note
            case (.pitchBend, .pitchBend):
                return true
            default:
                return false
            }
        }
    }

    private func noteBinding(for note: Int) -> Vinegar303MIDIBinding? {
        profile.bindings.first {
            $0.source == .noteOn && $0.number == note
        }
    }

    private func apply(
        _ binding: Vinegar303MIDIBinding,
        normalized: Double,
        pressed: Bool
    ) {
        switch binding.target {
        case .parameter:
            guard let identifier = binding.parameter,
                  let parameter = Vinegar303ParameterCatalog.all.first(
                    where: { $0.identifier == identifier }
                  ) else { return }
            let value = parameter.value(fromNormalized: min(max(normalized, 0), 1))
            onAction?(.parameter(parameter.id, value))

        case .pattern:
            guard fires(binding, pressed: pressed),
                  let index = binding.index,
                  (0..<Vinegar303PatternLibrary.patternCount).contains(index) else {
                return
            }
            onAction?(.pattern(index))

        case .stepGate:
            guard fires(binding, pressed: pressed),
                  let index = binding.index,
                  (0..<Vinegar303PatternLibrary.stepsPerPattern).contains(index) else {
                return
            }
            onAction?(.stepGate(index))

        case .stepAccent:
            guard fires(binding, pressed: pressed),
                  let index = binding.index,
                  (0..<Vinegar303PatternLibrary.stepsPerPattern).contains(index) else {
                return
            }
            onAction?(.stepAccent(index))

        case .stepSlide:
            guard fires(binding, pressed: pressed),
                  let index = binding.index,
                  (0..<Vinegar303PatternLibrary.stepsPerPattern).contains(index) else {
                return
            }
            onAction?(.stepSlide(index))

        case .stepNote:
            guard let index = binding.index,
                  (0..<Vinegar303PatternLibrary.stepsPerPattern).contains(index) else {
                return
            }
            if binding.source == .noteOn {
                guard pressed, let note = binding.number else { return }
                onAction?(.stepNote(index, Vinegar303Step.clampNote(note)))
            } else {
                let low = Vinegar303PatternLibrary.lowestNote
                let high = Vinegar303PatternLibrary.highestNote
                let note = low + Int(
                    (min(max(normalized, 0), 1) * Double(high - low)).rounded()
                )
                onAction?(.stepNote(index, note))
            }

        case .editMode:
            guard fires(binding, pressed: pressed) else { return }
            setLaunchkeyEditMode(!launchkeyEditModeEnabled)

        case .shift:
            setShiftHeld(pressed && normalized > 0)

        case .patternLengthDecrease:
            guard fires(binding, pressed: pressed) else { return }
            onAction?(.adjustPatternLength(-1))

        case .patternLengthIncrease:
            guard fires(binding, pressed: pressed) else { return }
            onAction?(.adjustPatternLength(1))
        }
    }

    /// Note buttons fire on press and ignore the release. CC buttons must also
    /// not repeat while held, so each learned CC action is edge-triggered.
    private func fires(_ binding: Vinegar303MIDIBinding, pressed: Bool) -> Bool {
        guard binding.source == .controlChange else { return pressed }
        if !pressed {
            actionControlStates[binding.id] = false
            return false
        }
        let wasPressed = actionControlStates[binding.id] ?? false
        actionControlStates[binding.id] = true
        return !wasPressed
    }

    private func release(_ binding: Vinegar303MIDIBinding) {
        actionControlStates[binding.id] = false
        if binding.target == .shift {
            setShiftHeld(false)
        }
    }

    private struct LearnSource {
        let source: Vinegar303MIDIBinding.Source
        let number: Int?
    }

    private func learnSource(for message: Vinegar303MIDIMessage) -> LearnSource? {
        switch message {
        case .noteOn(_, let note, let velocity) where velocity > 0:
            return LearnSource(source: .noteOn, number: note)
        case .controlChange(_, let controller, let value) where value > 0:
            return LearnSource(source: .controlChange, number: controller)
        default:
            return nil
        }
    }

    private func learn(
        source: Vinegar303MIDIBinding.Source,
        number: Int?,
        target: Vinegar303MIDILearnTarget
    ) {
        guard let descriptor = bindingDescriptor(for: target) else { return }
        var next = profile
        if next.name.caseInsensitiveCompare(Vinegar303MIDIProfile.noneName) == .orderedSame {
            next.name = uniqueProfileName(base: "New Mapping")
            next.bindings.removeAll()
        }
        next.bindings.removeAll {
            ($0.source == source && $0.number == number)
                || matches($0, target: target)
        }
        next.bindings.append(
            Vinegar303MIDIBinding(
                source: source,
                number: number,
                target: descriptor.target,
                parameter: descriptor.parameter,
                index: descriptor.index
            )
        )
        profile = next
        learnTarget = nil
        actionControlStates.removeAll()
        persistProfile()
    }

    private func bindingDescriptor(
        for target: Vinegar303MIDILearnTarget
    ) -> (target: Vinegar303MIDIBinding.Target, parameter: String?, index: Int?)? {
        switch target {
        case .parameter(let parameter):
            return (.parameter, Vinegar303ParameterCatalog.spec(parameter).identifier, nil)
        case .pattern(let index):
            guard (0..<Vinegar303PatternLibrary.patternCount).contains(index) else { return nil }
            return (.pattern, nil, index)
        case .stepGate(let index):
            guard (0..<Vinegar303PatternLibrary.stepsPerPattern).contains(index) else { return nil }
            return (.stepGate, nil, index)
        case .stepAccent(let index):
            guard (0..<Vinegar303PatternLibrary.stepsPerPattern).contains(index) else { return nil }
            return (.stepAccent, nil, index)
        case .stepSlide(let index):
            guard (0..<Vinegar303PatternLibrary.stepsPerPattern).contains(index) else { return nil }
            return (.stepSlide, nil, index)
        case .stepNote(let index):
            guard (0..<Vinegar303PatternLibrary.stepsPerPattern).contains(index) else { return nil }
            return (.stepNote, nil, index)
        case .editMode:
            return (.editMode, nil, nil)
        case .shift:
            return (.shift, nil, nil)
        case .patternLengthDecrease:
            return (.patternLengthDecrease, nil, nil)
        case .patternLengthIncrease:
            return (.patternLengthIncrease, nil, nil)
        }
    }

    private func matches(
        _ binding: Vinegar303MIDIBinding,
        target: Vinegar303MIDILearnTarget
    ) -> Bool {
        switch target {
        case .parameter(let parameter):
            return binding.target == .parameter
                && binding.parameter == Vinegar303ParameterCatalog.spec(parameter).identifier
        case .pattern(let index):
            return binding.target == .pattern && binding.index == index
        case .stepGate(let index):
            return binding.target == .stepGate && binding.index == index
        case .stepAccent(let index):
            return binding.target == .stepAccent && binding.index == index
        case .stepSlide(let index):
            return binding.target == .stepSlide && binding.index == index
        case .stepNote(let index):
            return binding.target == .stepNote && binding.index == index
        case .editMode:
            return binding.target == .editMode
        case .shift:
            return binding.target == .shift
        case .patternLengthDecrease:
            return binding.target == .patternLengthDecrease
        case .patternLengthIncrease:
            return binding.target == .patternLengthIncrease
        }
    }

    private func resetLaunchkeyInteractionState() {
        launchkeyEditModeEnabled = false
        launchkeyShiftHeld = false
        noteKnobLastValues.removeAll()
        noteKnobPickupActive.removeAll()
        actionControlStates.removeAll()
    }

    private func uniqueProfileName(base: String) -> String {
        let names = Set(profiles.map { $0.name.lowercased() })
        guard names.contains(base.lowercased()) else { return base }
        var suffix = 2
        while names.contains("\(base) \(suffix)".lowercased()) {
            suffix += 1
        }
        return "\(base) \(suffix)"
    }

    private func persistProfile() {
        guard profile.name.caseInsensitiveCompare(Vinegar303MIDIProfile.noneName)
            != .orderedSame else {
            store.setActiveProfileName(profile.name)
            profiles = store.loadProfiles()
            return
        }
        try? store.save(profile)
        store.setActiveProfileName(profile.name)
        profiles = store.loadProfiles()
    }
}
