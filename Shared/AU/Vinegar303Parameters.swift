import AudioToolbox
import Foundation

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
    ]

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
