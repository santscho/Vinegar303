import AudioToolbox
import Foundation

// MARK: - Preset document

/// Versioned, portable preset document. The file is intentionally plain JSON so
/// presets can be backed up, inspected and exchanged without a database.
public enum Vinegar303PresetScope: String, Codable, CaseIterable, Hashable, Identifiable {
    case full
    case patterns

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .full: "FULL"
        case .patterns: "PATTERNS"
        }
    }

    public var detail: String {
        switch self {
        case .full: "Patterns, sound and scale"
        case .patterns: "Patterns and sequence state only"
        }
    }
}

public struct Vinegar303PresetStep: Codable, Equatable {
    public var note: Int
    public var gate: Bool
    public var accent: Bool
    public var slide: Bool

    public init(note: Int = 33, gate: Bool = true, accent: Bool = false, slide: Bool = false) {
        self.note = min(max(note, Vinegar303PatternLibrary.lowestNote), Vinegar303PatternLibrary.highestNote)
        self.gate = gate
        self.accent = accent
        self.slide = slide
    }

    public init(_ step: Vinegar303Step) {
        self.init(note: step.note, gate: step.gate, accent: step.accent, slide: step.slide)
    }

    public static var rest: Vinegar303PresetStep {
        Vinegar303PresetStep(gate: false)
    }

    public var model: Vinegar303Step {
        Vinegar303Step(note: note, gate: gate, accent: accent, slide: slide)
    }
}

public struct Vinegar303PresetPattern: Codable, Equatable {
    public var length: Int
    public var steps: [Vinegar303PresetStep]

    public init(length: Int = Vinegar303PatternLibrary.stepsPerPattern, steps: [Vinegar303PresetStep]) {
        self.length = min(max(length, 1), Vinegar303PatternLibrary.stepsPerPattern)
        var normalized = Array(steps.prefix(Vinegar303PatternLibrary.stepsPerPattern))
        while normalized.count < Vinegar303PatternLibrary.stepsPerPattern {
            normalized.append(.rest)
        }
        self.steps = normalized
    }

    public init(_ pattern: Vinegar303Pattern) {
        self.init(length: pattern.length, steps: pattern.steps.map(Vinegar303PresetStep.init))
    }

    public static var rest: Vinegar303PresetStep {
        Vinegar303PresetStep(gate: false)
    }

    public var model: Vinegar303Pattern {
        Vinegar303Pattern(steps: steps.map(\.model), length: length)
    }
}

public struct Vinegar303PresetSequencer: Codable, Equatable {
    /// Zero-based pattern index. Files use the same convention as the AU
    /// parameter rather than the one-based display labels.
    public var currentPattern: Int
    public var patterns: [Vinegar303PresetPattern]

    public init(currentPattern: Int, patterns: [Vinegar303PresetPattern]) {
        self.currentPattern = min(
            max(currentPattern, 0),
            Vinegar303PatternLibrary.patternCount - 1
        )
        var normalized = Array(patterns.prefix(Vinegar303PatternLibrary.patternCount))
        while normalized.count < Vinegar303PatternLibrary.patternCount {
            normalized.append(Vinegar303PresetPattern(steps: []))
        }
        self.patterns = normalized
    }

    public var patternBank: [Vinegar303Pattern] {
        patterns.map(\.model)
    }
}

public struct Vinegar303Preset: Codable, Equatable {
    public static let formatIdentifier = "vinegar303.preset"
    public static let currentVersion = 1
    public static let fileExtension = "v303preset"

    public var format: String
    public var version: Int
    public var name: String
    public var scope: Vinegar303PresetScope
    public var sequencer: Vinegar303PresetSequencer
    public var sound: [String: Double]?
    public var scale: [String: Double]?

    public init(
        format: String = Vinegar303Preset.formatIdentifier,
        version: Int = Vinegar303Preset.currentVersion,
        name: String,
        scope: Vinegar303PresetScope,
        sequencer: Vinegar303PresetSequencer,
        sound: [String: Double]?,
        scale: [String: Double]?
    ) {
        self.format = format
        self.version = version
        self.name = name
        self.scope = scope
        self.sequencer = sequencer
        self.sound = sound
        self.scale = scale
    }

    /// Validate and normalize values that can arrive from an arbitrary file.
    public func normalized() throws -> Vinegar303Preset {
        guard format == Self.formatIdentifier else {
            throw Vinegar303PresetError.invalidFormat
        }
        guard version >= 1, version <= Self.currentVersion else {
            throw Vinegar303PresetError.unsupportedVersion(version)
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            throw Vinegar303PresetError.emptyName
        }

        var normalizedPatterns = Array(sequencer.patterns.prefix(Vinegar303PatternLibrary.patternCount))
        while normalizedPatterns.count < Vinegar303PatternLibrary.patternCount {
            normalizedPatterns.append(Vinegar303PresetPattern(steps: []))
        }
        normalizedPatterns = normalizedPatterns.map {
            Vinegar303PresetPattern(length: $0.length, steps: $0.steps)
        }

        var result = self
        result.name = cleanName
        result.version = Self.currentVersion
        result.sequencer = Vinegar303PresetSequencer(
            currentPattern: sequencer.currentPattern,
            patterns: normalizedPatterns
        )

        if scope == .full {
            guard sound != nil, scale != nil else {
                throw Vinegar303PresetError.missingSection
            }
        } else {
            result.sound = nil
            result.scale = nil
        }

        return result
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(try normalized())
    }

    public static func decode(_ data: Data) throws -> Vinegar303Preset {
        do {
            return try JSONDecoder().decode(Vinegar303Preset.self, from: data).normalized()
        } catch let error as Vinegar303PresetError {
            throw error
        } catch {
            throw Vinegar303PresetError.invalidDocument(error.localizedDescription)
        }
    }

    public static func load(from url: URL) throws -> Vinegar303Preset {
        try decode(Data(contentsOf: url))
    }

    /// The built-in, read-only factory preset. It is deliberately generated
    /// from the same parameter and pattern defaults as a fresh audio unit.
    public static func factory() throws -> Vinegar303Preset {
        let bank = Vinegar303PatternLibrary.factory().map(Vinegar303PresetPattern.init)
        let sequencer = Vinegar303PresetSequencer(currentPattern: 0, patterns: bank)

        let sound = Dictionary(uniqueKeysWithValues: Vinegar303PresetParameterGroups.sound.map { parameter in
            let spec = Vinegar303ParameterCatalog.spec(parameter)
            return (spec.identifier, Double(spec.defaultValue))
        })
        let scale = Dictionary(uniqueKeysWithValues: Vinegar303PresetParameterGroups.scale.map { parameter in
            let spec = Vinegar303ParameterCatalog.spec(parameter)
            return (spec.identifier, Double(spec.defaultValue))
        })

        return Vinegar303Preset(
            name: "Factory Default",
            scope: .full,
            sequencer: sequencer,
            sound: sound,
            scale: scale
        )
    }
}

// MARK: - Category document

/// Portable container for a complete category. Each contained preset keeps its
/// own full pattern bank, scope and sound data, so a category can be moved
/// between libraries without flattening or copying patterns separately.
public struct Vinegar303PresetCategoryArchive: Codable, Equatable {
    public static let formatIdentifier = "vinegar303.category"
    public static let currentVersion = 1
    public static let fileExtension = "v303category"

    public var format: String
    public var version: Int
    public var name: String
    public var presets: [Vinegar303Preset]

    public init(
        format: String = Vinegar303PresetCategoryArchive.formatIdentifier,
        version: Int = Vinegar303PresetCategoryArchive.currentVersion,
        name: String,
        presets: [Vinegar303Preset]
    ) {
        self.format = format
        self.version = version
        self.name = name
        self.presets = presets
    }

    /// Validate and normalize a category received from an arbitrary file.
    public func normalized() throws -> Vinegar303PresetCategoryArchive {
        guard format == Self.formatIdentifier else {
            throw Vinegar303PresetError.invalidCategoryFormat
        }
        guard version >= 1, version <= Self.currentVersion else {
            throw Vinegar303PresetError.unsupportedCategoryVersion(version)
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !presets.isEmpty else {
            throw Vinegar303PresetError.emptyCategory
        }

        var result = self
        result.name = cleanName
        result.version = Self.currentVersion
        result.presets = try presets.map { try $0.normalized() }
        return result
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(try normalized())
    }

    public static func decode(_ data: Data) throws -> Vinegar303PresetCategoryArchive {
        do {
            return try JSONDecoder().decode(Self.self, from: data).normalized()
        } catch let error as Vinegar303PresetError {
            throw error
        } catch {
            throw Vinegar303PresetError.invalidCategoryDocument(error.localizedDescription)
        }
    }

    public static func load(from url: URL) throws -> Vinegar303PresetCategoryArchive {
        try decode(Data(contentsOf: url))
    }
}

// MARK: - Parameter groups

public enum Vinegar303PresetParameterGroups {
    public static let sound: [Vinegar303Parameter] = [
        .cutoff,
        .resonance,
        .envmod,
        .decay,
        .accent,
        .volume,
        .tuning,
        .waveform,
        .distortion,
        .drive,
        .halfSpeed,
    ]

    /// Scale settings are stored separately so a future partial-save mode can
    /// combine them with patterns without copying the sound.
    public static let scale: [Vinegar303Parameter] = [
        .pitchTranspose,
        .scaleEnable,
        .scaleKey,
        .scaleType,
    ]
}

// MARK: - Errors

public enum Vinegar303PresetError: LocalizedError {
    case invalidFormat
    case unsupportedVersion(Int)
    case invalidCategoryFormat
    case unsupportedCategoryVersion(Int)
    case emptyCategory
    case emptyName
    case missingSection
    case invalidDocument(String)
    case invalidCategoryDocument(String)
    case factoryIsReadOnly
    case factoryCategoryIsReadOnly
    case categoryNotFound
    case categoryAlreadyExists
    case invalidCategory
    case destinationIsFactory
    case activePresetHasUnsavedChanges
    case fileOperation(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            "This is not a Vinegar303 preset file."
        case .unsupportedVersion(let version):
            "This preset uses unsupported schema version \(version)."
        case .invalidCategoryFormat:
            "This is not a Vinegar303 category export file."
        case .unsupportedCategoryVersion(let version):
            "This category export uses unsupported schema version \(version)."
        case .emptyCategory:
            "A category export must contain at least one preset."
        case .emptyName:
            "The preset name cannot be empty."
        case .missingSection:
            "A full preset must contain both sound and scale settings."
        case .invalidDocument(let reason):
            "The preset file could not be read: \(reason)"
        case .invalidCategoryDocument(let reason):
            "The category export file could not be read: \(reason)"
        case .factoryIsReadOnly:
            "The Factory Default preset is read-only. Duplicate it or use Save As."
        case .factoryCategoryIsReadOnly:
            "The Factory category is read-only and cannot be deleted."
        case .categoryNotFound:
            "The selected category no longer exists."
        case .categoryAlreadyExists:
            "A category with that name already exists."
        case .invalidCategory:
            "The category name is not valid."
        case .destinationIsFactory:
            "The Factory Default preset cannot be modified."
        case .activePresetHasUnsavedChanges:
            "Save or discard the active preset's changes first."
        case .fileOperation(let reason):
            "The preset file operation failed: \(reason)"
        }
    }
}
