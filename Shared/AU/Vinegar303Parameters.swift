import AudioToolbox
import Foundation

// MARK: - FX chain identity

public enum Vinegar303FXEffectType: Int, CaseIterable, Identifiable {
    case none = 0
    case delay = 1

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .none: return "None"
        case .delay: return "Delay"
        }
    }
}

public enum Vinegar303FXControl: Int, CaseIterable, Hashable {
    case type = 0
    case enabled = 1
    case time = 2
    case feedback = 3
    case tone = 4
    case mix = 5
    case sync = 6
    case division = 7
    case pingPong = 8

    public var title: String {
        switch self {
        case .type: return "Type"
        case .enabled: return "Enabled"
        case .time: return "Time"
        case .feedback: return "Feedback"
        case .tone: return "Tone"
        case .mix: return "Mix"
        case .sync: return "Sync"
        case .division: return "Division"
        case .pingPong: return "Ping-Pong"
        }
    }
}

public enum Vinegar303FXDivision: Int, CaseIterable, Identifiable {
    case quarter = 0
    case eighth = 1
    case eighthDotted = 2
    case sixteenth = 3
    case sixteenthDotted = 4
    case thirtySecond = 5

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .quarter: return "1/4"
        case .eighth: return "1/8"
        case .eighthDotted: return "1/8D"
        case .sixteenth: return "1/16"
        case .sixteenthDotted: return "1/16D"
        case .thirtySecond: return "1/32"
        }
    }

    /// Quarter-note beats represented by this division.
    public var beats: Double {
        switch self {
        case .quarter: return 1.0
        case .eighth: return 0.5
        case .eighthDotted: return 0.75
        case .sixteenth: return 0.25
        case .sixteenthDotted: return 0.375
        case .thirtySecond: return 0.125
        }
    }

    public func seconds(tempo: Double) -> Double {
        beats * 60.0 / max(tempo, 20.0)
    }
}

/// Four fixed effect slots. Keeping the slots fixed preserves the AU parameter
/// tree and host automation addresses; the UI presents the active slots as an
/// ordered chain.
public enum Vinegar303FXSlot: Int, CaseIterable, Identifiable {
    case one = 0
    case two = 1
    case three = 2
    case four = 3

    public static let count = 4
    public static let addressBase: AUParameterAddress = 100
    public static let addressStride: AUParameterAddress = 9

    public var id: Int { rawValue }

    public var displayName: String { "FX \(rawValue + 1)" }

    public func parameter(_ control: Vinegar303FXControl) -> Vinegar303Parameter {
        let address = Self.addressBase
            + AUParameterAddress(rawValue) * Self.addressStride
            + AUParameterAddress(control.rawValue)
        return Vinegar303Parameter(rawValue: address) ?? .fx1Type
    }

    public var parameters: [Vinegar303Parameter] {
        Vinegar303FXControl.allCases.map(parameter)
    }
}

// MARK: - Parameter identity

/// Stable AU parameter addresses. These are part of the plug-in's public
/// automation contract and must never be reordered.
public enum Vinegar303Parameter: AUParameterAddress, CaseIterable {
    case cutoff = 1
    case resonance = 2
    case envmod = 3
    case decay = 4
    case accent = 5
    case volume = 6
    case tuning = 7
    case waveform = 8
    case distortion = 9
    case drive = 10
    case tempo = 11
    case pattern = 12
    case patternLength = 13
    case sync = 14
    case run = 15
    case midiMode = 16
    case pitchTranspose = 17
    case scaleEnable = 18
    case scaleKey = 19
    case scaleType = 20
    case halfSpeed = 21

    // Fixed FX slots. These addresses are part of the public automation
    // contract and must never be reordered.
    case fx1Type = 100
    case fx1Enabled = 101
    case fx1Time = 102
    case fx1Feedback = 103
    case fx1Tone = 104
    case fx1Mix = 105
    case fx1Sync = 106
    case fx1Division = 107
    case fx1PingPong = 108

    case fx2Type = 109
    case fx2Enabled = 110
    case fx2Time = 111
    case fx2Feedback = 112
    case fx2Tone = 113
    case fx2Mix = 114
    case fx2Sync = 115
    case fx2Division = 116
    case fx2PingPong = 117

    case fx3Type = 118
    case fx3Enabled = 119
    case fx3Time = 120
    case fx3Feedback = 121
    case fx3Tone = 122
    case fx3Mix = 123
    case fx3Sync = 124
    case fx3Division = 125
    case fx3PingPong = 126

    case fx4Type = 127
    case fx4Enabled = 128
    case fx4Time = 129
    case fx4Feedback = 130
    case fx4Tone = 131
    case fx4Mix = 132
    case fx4Sync = 133
    case fx4Division = 134
    case fx4PingPong = 135

    public var fxSlot: Vinegar303FXSlot? {
        guard rawValue >= Vinegar303FXSlot.addressBase else { return nil }
        let offset = rawValue - Vinegar303FXSlot.addressBase
        guard offset < Vinegar303FXSlot.addressStride * AUParameterAddress(Vinegar303FXSlot.count)
        else { return nil }
        return Vinegar303FXSlot(
            rawValue: Int(offset / Vinegar303FXSlot.addressStride)
        )
    }

    public var fxControl: Vinegar303FXControl? {
        guard let fxSlot else { return nil }
        let offset = rawValue - Vinegar303FXSlot.addressBase
        let controlOffset = offset - AUParameterAddress(fxSlot.rawValue) * Vinegar303FXSlot.addressStride
        return Vinegar303FXControl(rawValue: Int(controlOffset))
    }
}

private func vinegarPitchText(_ semitones: Int) -> String {
    semitones > 0 ? "+\(semitones) st" : "\(semitones) st"
}

public enum Vinegar303Taper {
    case linear
    case logarithmic

    func normalize(_ value: Double, minimum: Double, maximum: Double) -> Double {
        guard maximum > minimum else { return 0 }
        switch self {
        case .linear:
            return (value - minimum) / (maximum - minimum)
        case .logarithmic:
            let lo = max(minimum, 0.0001)
            let hi = max(maximum, lo * 1.0001)
            return log(max(value, lo) / lo) / log(hi / lo)
        }
    }

    func denormalize(_ normalized: Double, minimum: Double, maximum: Double) -> Double {
        let clamped = min(max(normalized, 0), 1)
        switch self {
        case .linear:
            return minimum + (maximum - minimum) * clamped
        case .logarithmic:
            let lo = max(minimum, 0.0001)
            let hi = max(maximum, lo * 1.0001)
            return lo * pow(hi / lo, clamped)
        }
    }
}

public struct Vinegar303ParameterSpec {
    public let id: Vinegar303Parameter
    public let identifier: String
    public let name: String
    public let minimum: AUValue
    public let maximum: AUValue
    public let defaultValue: AUValue
    public let unit: AudioUnitParameterUnit
    public let valueStrings: [String]?
    public let flags: AudioUnitParameterOptions
    public let taper: Vinegar303Taper
    public let isBipolar: Bool
    /// Non-nil for stepped parameters. The value is always snapped to this
    /// increment before it reaches the UI or DSP.
    public let step: AUValue?

    public var range: ClosedRange<Double> {
        Double(minimum)...Double(maximum)
    }

    /// Flags the host sees on the published `AUParameter`.
    ///
    /// Readable and writable are required for DAWs such as Ableton Live to
    /// expose a parameter in Configure mode, Macro mapping and automation.
    /// Continuous parameters also advertise that they can be ramped.
    public var hostFlags: AudioUnitParameterOptions {
        var options: AudioUnitParameterOptions = [.flag_IsReadable, .flag_IsWritable]
        options.formUnion(flags)
        if step == nil && valueStrings == nil {
            options.insert(.flag_CanRamp)
        }
        return options
    }

    public func snapped(_ value: AUValue) -> AUValue {
        let clamped = min(max(value, minimum), maximum)
        guard let step, step > 0 else { return clamped }
        let snapped = (clamped / step).rounded() * step
        return min(max(snapped, minimum), maximum)
    }

    public func normalized(_ value: AUValue) -> Double {
        taper.normalize(Double(snapped(value)), minimum: Double(minimum), maximum: Double(maximum))
    }

    public func value(fromNormalized normalized: Double) -> AUValue {
        snapped(AUValue(taper.denormalize(normalized, minimum: Double(minimum), maximum: Double(maximum))))
    }

    public func format(_ value: AUValue) -> String {
        if let control = id.fxControl {
            switch control {
            case .type:
                return value >= 0.5 ? "DELAY" : "NONE"
            case .enabled, .pingPong:
                return value >= 0.5 ? "ON" : "OFF"
            case .time:
                return "\(Int(value.rounded())) ms"
            case .feedback, .tone, .mix:
                return "\(Int(value.rounded())) %"
            case .sync:
                return value >= 0.5 ? "HOST" : "FREE"
            case .division:
                let index = min(
                    max(Int(value.rounded()), 0),
                    Vinegar303FXDivision.allCases.count - 1
                )
                return Vinegar303FXDivision(rawValue: index)?.title ?? "1/8"
            }
        }

        switch id {
        case .cutoff:
            return value >= 1_000
                ? String(format: "%.2f kHz", value / 1_000)
                : "\(Int(value.rounded())) Hz"
        case .resonance, .envmod, .accent, .distortion:
            return "\(Int(value.rounded())) %"
        case .decay:
            return value >= 1_000
                ? String(format: "%.1f s", value / 1_000)
                : "\(Int(value.rounded())) ms"
        case .volume:
            return String(format: "%.1f dB", value)
        case .tuning:
            return String(format: "%+.0f ct", value)
        case .drive:
            return String(format: "%.1f dB", value)
        case .waveform:
            return value >= 0.5 ? "SAW" : "SQR"
        case .tempo:
            return "\(Int(value.rounded())) BPM"
        case .pattern:
            return String(format: "P%02d", Int(value.rounded()) + 1)
        case .patternLength:
            return "\(Int(value.rounded())) steps"
        case .sync:
            return value >= 0.5 ? "HOST" : "FREE"
        case .run:
            return value >= 0.5 ? "RUN" : "STOP"
        case .midiMode:
            return value >= 0.5 ? "NOTE" : "PATTERN"
        case .pitchTranspose:
            return vinegarPitchText(Int(value.rounded()))
        case .scaleEnable:
            return value >= 0.5 ? "ON" : "OFF"
        case .scaleKey:
            let index = min(max(Int(value.rounded()), 0), Vinegar303Scale.keyNames.count - 1)
            return Vinegar303Scale.keyNames[index]
        case .scaleType:
            let index = min(max(Int(value.rounded()), 0), Vinegar303Scale.modeNames.count - 1)
            return Vinegar303Scale.modeNames[index].uppercased()
        case .halfSpeed:
            return value >= 0.5 ? "1:2" : "1:1"
        default:
            // FX parameters are handled by the `fxControl` branch above.
            return ""
        }
    }
}

public enum Vinegar303ParameterCatalog {
    public static let all: [Vinegar303ParameterSpec] = [
        spec(.cutoff, "cutoff", "Cutoff", 200, 2_000, 520, .hertz, taper: .logarithmic, flags: [.flag_DisplayLogarithmic]),
        spec(.resonance, "resonance", "Resonance", 0, 100, 28, .percent),
        spec(.envmod, "envmod", "Envmod", 0, 100, 45, .percent),
        spec(.decay, "decay", "Decay", 40, 1_600, 300, .milliseconds, taper: .logarithmic, flags: [.flag_DisplayLogarithmic]),
        spec(.accent, "accent", "Accent", 0, 100, 50, .percent),
        spec(.volume, "volume", "Volume", -60, 0, -8, .decibels),
        spec(.tuning, "tuning", "Tuning", -50, 50, 0, .cents, isBipolar: true),
        spec(
            .waveform, "waveform", "Waveform", 0, 1, 1, .indexed,
            valueStrings: ["Square", "Saw"],
            flags: [.flag_ValuesHaveStrings]
        ),
        spec(.distortion, "distortion", "Distortion", 0, 100, 0, .percent),
        spec(.drive, "drive", "Drive", 0, 24, 0, .decibels),
        spec(.tempo, "tempo", "Tempo", 40, 240, 132, .BPM),
        spec(
            .pattern, "pattern", "Pattern", 0, 15, 0, .indexed,
            valueStrings: (1...16).map { String(format: "%02d", $0) },
            flags: [.flag_ValuesHaveStrings]
        ),
        spec(
            .patternLength, "pattern_length", "Length", 1, 16, 16, .indexed,
            valueStrings: (1...16).map { "\($0)" },
            flags: [.flag_ValuesHaveStrings]
        ),
        spec(
            .sync, "sync", "Sync", 0, 1, 1, .indexed,
            valueStrings: ["Free", "Host"],
            flags: [.flag_ValuesHaveStrings]
        ),
        spec(
            .run, "run", "Run", 0, 1, 0, .indexed,
            valueStrings: ["Stop", "Run"],
            flags: [.flag_ValuesHaveStrings]
        ),
        spec(
            .halfSpeed, "halfSpeed", "Half Speed", 0, 1, 0, .indexed,
            valueStrings: ["1:1", "1:2"],
            flags: [.flag_ValuesHaveStrings],
            step: 1
        ),
        spec(
            .midiMode, "midi_mode", "MIDI Mode", 0, 1, 0, .indexed,
            valueStrings: ["Pattern", "Note"],
            flags: [.flag_ValuesHaveStrings]
        ),
        spec(
            .pitchTranspose, "pitchTranspose", "Pitch Transpose", -12, 12, 0,
            .indexed,
            valueStrings: (-12...12).map(vinegarPitchText),
            flags: [.flag_ValuesHaveStrings],
            isBipolar: true,
            step: 1
        ),
        spec(
            .scaleEnable, "scaleEnable", "Scale Aware", 0, 1, 0, .indexed,
            valueStrings: ["Off", "On"],
            flags: [.flag_ValuesHaveStrings],
            step: 1
        ),
        spec(
            .scaleKey, "scaleKey", "Scale Key", 0, 11, 0, .indexed,
            valueStrings: Vinegar303Scale.keyNames,
            flags: [.flag_ValuesHaveStrings],
            step: 1
        ),
        spec(
            .scaleType, "scaleType", "Scale Type", 0, 6, 0, .indexed,
            valueStrings: Vinegar303Scale.modeNames,
            flags: [.flag_ValuesHaveStrings],
            step: 1
        ),
    ] + Vinegar303FXSlot.allCases.flatMap { slot in
        let prefix = "fx\(slot.rawValue + 1)"
        let name = "FX \(slot.rawValue + 1)"
        return [
            spec(
                slot.parameter(.type), "\(prefix)_type", "\(name) Type", 0, 1, 0, .indexed,
                valueStrings: ["None", "Delay"],
                flags: [.flag_ValuesHaveStrings],
                step: 1
            ),
            spec(
                slot.parameter(.enabled), "\(prefix)_enabled", "\(name) Enabled", 0, 1, 0, .indexed,
                valueStrings: ["Off", "On"],
                flags: [.flag_ValuesHaveStrings],
                step: 1
            ),
            spec(
                slot.parameter(.time), "\(prefix)_time", "\(name) Time", 20, 2_000, 300, .milliseconds,
                taper: .logarithmic,
                flags: [.flag_DisplayLogarithmic]
            ),
            spec(slot.parameter(.feedback), "\(prefix)_feedback", "\(name) Feedback", 0, 90, 35, .percent),
            spec(slot.parameter(.tone), "\(prefix)_tone", "\(name) Tone", 0, 100, 55, .percent),
            spec(slot.parameter(.mix), "\(prefix)_mix", "\(name) Mix", 0, 100, 25, .percent),
            spec(
                slot.parameter(.sync), "\(prefix)_sync", "\(name) Sync", 0, 1, 1, .indexed,
                valueStrings: ["Free", "Host"],
                flags: [.flag_ValuesHaveStrings],
                step: 1
            ),
            spec(
                slot.parameter(.division), "\(prefix)_division", "\(name) Division", 0, 5, 1, .indexed,
                valueStrings: Vinegar303FXDivision.allCases.map(\.title),
                flags: [.flag_ValuesHaveStrings],
                step: 1
            ),
            spec(
                slot.parameter(.pingPong), "\(prefix)_ping_pong", "\(name) Ping-Pong", 0, 1, 0, .indexed,
                valueStrings: ["Off", "On"],
                flags: [.flag_ValuesHaveStrings],
                step: 1
            ),
        ]
    }

    public static func spec(_ id: Vinegar303Parameter) -> Vinegar303ParameterSpec {
        all.first { $0.id == id } ?? all[0]
    }

    private static func spec(
        _ id: Vinegar303Parameter,
        _ identifier: String,
        _ name: String,
        _ minimum: AUValue,
        _ maximum: AUValue,
        _ defaultValue: AUValue,
        _ unit: AudioUnitParameterUnit,
        valueStrings: [String]? = nil,
        taper: Vinegar303Taper = .linear,
        flags: AudioUnitParameterOptions = [],
        isBipolar: Bool = false,
        step: AUValue? = nil
    ) -> Vinegar303ParameterSpec {
        Vinegar303ParameterSpec(
            id: id,
            identifier: identifier,
            name: name,
            minimum: minimum,
            maximum: maximum,
            defaultValue: defaultValue,
            unit: unit,
            valueStrings: valueStrings,
            flags: flags,
            taper: taper,
            isBipolar: isBipolar,
            step: step
        )
    }
}

// MARK: - AU parameter tree

public enum Vinegar303ParameterTreeFactory {
    public static func makeTree() -> AUParameterTree {
        let parameters = Vinegar303ParameterCatalog.all.map { spec in
            AUParameterTree.createParameter(
                withIdentifier: spec.identifier,
                name: spec.name,
                address: spec.id.rawValue,
                min: spec.minimum,
                max: spec.maximum,
                unit: spec.unit,
                unitName: nil,
                flags: spec.hostFlags,
                valueStrings: spec.valueStrings,
                dependentParameters: nil
            )
        }

        let tree = AUParameterTree.createTree(withChildren: parameters)

        // Sensible automation behaviour for the host's generic editor.
        for parameter in tree.allParameters {
            parameter.value = Vinegar303ParameterCatalog.spec(
                Vinegar303Parameter(rawValue: parameter.address) ?? .cutoff
            ).defaultValue
        }

        return tree
    }
}
