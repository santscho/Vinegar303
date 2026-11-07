import Combine
import Darwin
import Foundation

// MARK: - Library entries

public struct Vinegar303PresetEntry: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let category: String
    public let scope: Vinegar303PresetScope
    public let url: URL?
    public let isFactory: Bool

    public init(
        name: String,
        category: String,
        scope: Vinegar303PresetScope,
        url: URL?,
        isFactory: Bool
    ) {
        self.id = isFactory ? "factory.default" : (url?.path ?? "\(category)/\(name)")
        self.name = name
        self.category = category
        self.scope = scope
        self.url = url
        self.isFactory = isFactory
    }
}

public struct Vinegar303PresetCategory: Identifiable, Hashable {
    public let name: String
    public let isFactory: Bool
    public let count: Int

    public var id: String { name }

    public init(name: String, isFactory: Bool, count: Int) {
        self.name = name
        self.isFactory = isFactory
        self.count = count
    }
}

// MARK: - Import resolution

public enum Vinegar303PresetImportPolicy: String, CaseIterable {
    case skip
    case keepBoth
    case overwrite
}

public struct Vinegar303PresetImportConflict: Hashable, Identifiable {
    public enum Kind: String, Hashable {
        case category
        case preset
    }

    public let kind: Kind
    public let name: String
    public let category: String

    public var id: String {
        switch kind {
        case .category:
            "category:\(name.lowercased())"
        case .preset:
            "preset:\(category.lowercased())/\(name.lowercased())"
        }
    }

    public init(kind: Kind, name: String, category: String = "") {
        self.kind = kind
        self.name = name
        self.category = category
    }
}

// MARK: - File library

/// File-backed preset library shared by the standalone app and the AUv3
/// extension. Each preset is one JSON file; each category is one folder.
public final class Vinegar303PresetLibrary: ObservableObject {
    public static let factoryCategoryName = "Factory"
    public static let defaultCategoryName = "User"
    public static let presetsDirectoryName = "Presets"

    @Published public private(set) var categories: [Vinegar303PresetCategory] = []
    @Published public private(set) var entries: [Vinegar303PresetEntry] = []
    @Published public private(set) var libraryURL: URL
    @Published public private(set) var isSharedLibrary: Bool

    public let factoryPreset: Vinegar303Preset

    private let fileManager = FileManager.default
    private let factoryEntryStorage: Vinegar303PresetEntry

    public var factoryEntry: Vinegar303PresetEntry {
        factoryEntryStorage
    }

    public init(rootURL: URL? = nil) {
        let factory = (try? Vinegar303Preset.factory().normalized()) ?? Vinegar303Preset(
            name: "Factory Default",
            scope: .full,
            sequencer: Vinegar303PresetSequencer(
                currentPattern: 0,
                patterns: Array(repeating: Vinegar303PresetPattern(steps: []), count: Vinegar303PatternLibrary.patternCount)
            ),
            sound: [:],
            scale: [:]
        )
        factoryPreset = factory
        factoryEntryStorage = Vinegar303PresetEntry(
            name: factory.name,
            category: Self.factoryCategoryName,
            scope: factory.scope,
            url: nil,
            isFactory: true
        )

        if let rootURL {
            libraryURL = rootURL
            isSharedLibrary = true
        } else {
            let resolved = Self.resolveLibraryURL()
            libraryURL = resolved.url
            isSharedLibrary = resolved.isShared
        }

        do {
            try fileManager.createDirectory(at: libraryURL, withIntermediateDirectories: true)
            try ensureCategory(Self.defaultCategoryName)
        } catch {
            // A failed first launch should not prevent the editor from opening.
            // The manager surfaces the path and any later operation error.
        }
        reload()
    }

    // MARK: Loading

    public func reload() {
        let categoryURLs = (try? fileManager.contentsOfDirectory(
            at: libraryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let folderNames = categoryURLs
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        var loadedEntries: [Vinegar303PresetEntry] = [factoryEntry]
        var loadedCategories: [Vinegar303PresetCategory] = [
            Vinegar303PresetCategory(
                name: Self.factoryCategoryName,
                isFactory: true,
                count: 1
            ),
        ]

        for folderName in folderNames {
            let folder = libraryURL.appendingPathComponent(folderName, isDirectory: true)
            let presetURLs = (try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            var categoryEntries: [Vinegar303PresetEntry] = []
            for url in presetURLs where url.pathExtension.lowercased() == Vinegar303Preset.fileExtension {
                guard let preset = try? Vinegar303Preset.load(from: url) else { continue }
                categoryEntries.append(
                    Vinegar303PresetEntry(
                        name: preset.name,
                        category: folderName,
                        scope: preset.scope,
                        url: url,
                        isFactory: false
                    )
                )
            }
            categoryEntries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            loadedEntries.append(contentsOf: categoryEntries)
            loadedCategories.append(
                Vinegar303PresetCategory(
                    name: folderName,
                    isFactory: false,
                    count: categoryEntries.count
                )
            )
        }

        entries = loadedEntries
        categories = loadedCategories
    }

    public func entries(in category: String) -> [Vinegar303PresetEntry] {
        entries.filter { $0.category == category }
    }

    public func entry(id: String) -> Vinegar303PresetEntry? {
        entries.first { $0.id == id }
    }

    public func preset(for entry: Vinegar303PresetEntry) throws -> Vinegar303Preset {
        if entry.isFactory {
            return factoryPreset
        }
        guard let url = entry.url else {
            throw Vinegar303PresetError.fileOperation("The preset has no file location.")
        }
        return try Vinegar303Preset.load(from: url)
    }

    // MARK: Categories

    @discardableResult
    public func createCategory(_ name: String) throws -> String {
        let cleanName = sanitizedComponent(name, fallback: "")
        guard !cleanName.isEmpty else {
            throw Vinegar303PresetError.invalidCategory
        }
        guard cleanName.caseInsensitiveCompare(Self.factoryCategoryName) != .orderedSame else {
            throw Vinegar303PresetError.invalidCategory
        }

        try ensureCategory(cleanName)
        reload()
        return cleanName
    }

    /// Rename a user category folder in place. Presets contain no category
    /// field, so moving the folder preserves every preset and its metadata.
    @discardableResult
    public func renameCategory(_ name: String, to newName: String) throws -> String {
        guard name.caseInsensitiveCompare(Self.factoryCategoryName) != .orderedSame else {
            throw Vinegar303PresetError.factoryCategoryIsReadOnly
        }
        guard let category = categories.first(where: {
            !$0.isFactory && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            throw Vinegar303PresetError.categoryNotFound
        }

        let cleanName = sanitizedComponent(newName, fallback: "")
        guard !cleanName.isEmpty else {
            throw Vinegar303PresetError.invalidCategory
        }
        guard cleanName.caseInsensitiveCompare(Self.factoryCategoryName) != .orderedSame else {
            throw Vinegar303PresetError.invalidCategory
        }
        if let existing = existingCategory(named: cleanName),
           existing.name.caseInsensitiveCompare(category.name) != .orderedSame {
            throw Vinegar303PresetError.categoryAlreadyExists
        }

        if cleanName == category.name {
            return category.name
        }

        let root = libraryURL.standardizedFileURL
        let source = root
            .appendingPathComponent(category.name, isDirectory: true)
            .standardizedFileURL
        let destination = root
            .appendingPathComponent(cleanName, isDirectory: true)
            .standardizedFileURL
        guard source.deletingLastPathComponent() == root,
              destination.deletingLastPathComponent() == root else {
            throw Vinegar303PresetError.invalidCategory
        }

        do {
            if existingCategory(named: cleanName) != nil {
                // A case-only rename needs a temporary hop on a
                // case-insensitive volume.
                let temporary = root.appendingPathComponent(".\(UUID().uuidString)", isDirectory: true)
                try fileManager.moveItem(at: source, to: temporary)
                do {
                    try fileManager.moveItem(at: temporary, to: destination)
                } catch {
                    try? fileManager.moveItem(at: temporary, to: source)
                    throw error
                }
            } else {
                try fileManager.moveItem(at: source, to: destination)
            }
        } catch {
            throw Vinegar303PresetError.fileOperation(error.localizedDescription)
        }

        reload()
        return cleanName
    }

    private func ensureCategory(_ name: String) throws {
        let directory = libraryURL.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Delete a user category and every preset file inside it. The Factory
    /// category is built in, and the target is constrained to a direct child of
    /// the preset library so a bad name cannot escape the library root.
    @discardableResult
    public func deleteCategory(_ name: String) throws -> Int {
        guard name.caseInsensitiveCompare(Self.factoryCategoryName) != .orderedSame else {
            throw Vinegar303PresetError.factoryCategoryIsReadOnly
        }
        guard let category = categories.first(where: {
            !$0.isFactory && $0.name == name
        }) else {
            throw Vinegar303PresetError.categoryNotFound
        }

        let root = libraryURL.standardizedFileURL
        let directory = root
            .appendingPathComponent(category.name, isDirectory: true)
            .standardizedFileURL
        guard directory.deletingLastPathComponent() == root else {
            throw Vinegar303PresetError.invalidCategory
        }

        do {
            try fileManager.removeItem(at: directory)
        } catch {
            throw Vinegar303PresetError.fileOperation(error.localizedDescription)
        }
        reload()
        return category.count
    }

    private func ensureCategoryDirectory(_ category: String) throws -> URL {
        guard category.caseInsensitiveCompare(Self.factoryCategoryName) != .orderedSame else {
            throw Vinegar303PresetError.destinationIsFactory
        }
        let cleanName = sanitizedComponent(category, fallback: Self.defaultCategoryName)
        guard !cleanName.isEmpty else {
            throw Vinegar303PresetError.invalidCategory
        }
        let directory = libraryURL.appendingPathComponent(cleanName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: Save, duplicate and delete

    @discardableResult
    public func save(
        _ preset: Vinegar303Preset,
        category: String,
        replacing existingURL: URL? = nil
    ) throws -> Vinegar303PresetEntry {
        let normalized = try preset.normalized()
        let directory = try ensureCategoryDirectory(category)

        let targetURL: URL
        if let existingURL {
            guard existingURL.standardizedFileURL.path.hasPrefix(libraryURL.standardizedFileURL.path + "/") else {
                throw Vinegar303PresetError.fileOperation("The preset is outside the preset library.")
            }
            targetURL = existingURL
        } else {
            targetURL = uniqueURL(in: directory, name: normalized.name)
        }

        do {
            try normalized.encoded().write(to: targetURL, options: .atomic)
        } catch {
            throw Vinegar303PresetError.fileOperation(error.localizedDescription)
        }

        reload()
        guard let saved = entries.first(where: {
            $0.url?.standardizedFileURL == targetURL.standardizedFileURL
        }) else {
            throw Vinegar303PresetError.fileOperation("The saved preset could not be indexed.")
        }
        return saved
    }

    @discardableResult
    public func duplicate(_ entry: Vinegar303PresetEntry) throws -> Vinegar303PresetEntry {
        var preset = try preset(for: entry)
        preset.name = "\(entry.name) Copy"
        let category = entry.isFactory ? Self.defaultCategoryName : entry.category
        return try save(preset, category: category)
    }

    @discardableResult
    public func rename(_ entry: Vinegar303PresetEntry, to newName: String) throws -> Vinegar303PresetEntry {
        guard !entry.isFactory, let oldURL = entry.url else {
            throw Vinegar303PresetError.factoryIsReadOnly
        }
        let cleanName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            throw Vinegar303PresetError.emptyName
        }

        var preset = try preset(for: entry)
        preset.name = cleanName
        let directory = try ensureCategoryDirectory(entry.category)
        let newURL = uniqueURL(in: directory, name: cleanName)

        do {
            try preset.encoded().write(to: newURL, options: .atomic)
            try fileManager.removeItem(at: oldURL)
        } catch {
            throw Vinegar303PresetError.fileOperation(error.localizedDescription)
        }
        reload()

        guard let renamed = entries.first(where: {
            $0.url?.standardizedFileURL == newURL.standardizedFileURL
        }) else {
            throw Vinegar303PresetError.fileOperation("The renamed preset could not be indexed.")
        }
        return renamed
    }

    public func delete(_ entry: Vinegar303PresetEntry) throws {
        guard !entry.isFactory else {
            throw Vinegar303PresetError.factoryIsReadOnly
        }
        guard let url = entry.url else {
            throw Vinegar303PresetError.fileOperation("The preset has no file location.")
        }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw Vinegar303PresetError.fileOperation(error.localizedDescription)
        }
        reload()
    }

    // MARK: Import and export

    /// Return the collisions that the user must resolve before importing.
    /// Category archives collide by their restored category name; single
    /// presets collide by name inside the selected target category.
    public func importConflicts(
        from urls: [URL],
        into category: String
    ) throws -> [Vinegar303PresetImportConflict] {
        var conflicts: [Vinegar303PresetImportConflict] = []
        var seen = Set<String>()

        for url in urls {
            let fileExtension = url.pathExtension.lowercased()
            guard fileExtension == Vinegar303Preset.fileExtension
                    || fileExtension == Vinegar303PresetCategoryArchive.fileExtension else { continue }

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let conflict: Vinegar303PresetImportConflict?
            if fileExtension == Vinegar303PresetCategoryArchive.fileExtension {
                let archive = try Vinegar303PresetCategoryArchive.load(from: url)
                let candidate = importCategoryBaseName(named: archive.name)
                if let existing = existingCategory(named: candidate) {
                    conflict = Vinegar303PresetImportConflict(kind: .category, name: existing.name)
                } else {
                    conflict = nil
                }
            } else {
                let preset = try Vinegar303Preset.load(from: url)
                if let existing = existingEntry(named: preset.name, in: category) {
                    conflict = Vinegar303PresetImportConflict(
                        kind: .preset,
                        name: existing.name,
                        category: category
                    )
                } else {
                    conflict = nil
                }
            }

            if let conflict, seen.insert(conflict.id).inserted {
                conflicts.append(conflict)
            }
        }
        return conflicts
    }

    @discardableResult
    public func importPresets(
        from urls: [URL],
        into category: String,
        policy: Vinegar303PresetImportPolicy = .keepBoth
    ) throws -> [Vinegar303PresetEntry] {
        var imported: [Vinegar303PresetEntry] = []
        for url in urls {
            let fileExtension = url.pathExtension.lowercased()
            guard fileExtension == Vinegar303Preset.fileExtension
                    || fileExtension == Vinegar303PresetCategoryArchive.fileExtension else { continue }

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            if fileExtension == Vinegar303PresetCategoryArchive.fileExtension {
                let archive = try Vinegar303PresetCategoryArchive.load(from: url)
                guard let destination = try categoryForImport(named: archive.name, policy: policy) else {
                    continue
                }
                for preset in archive.presets {
                    if let entry = try importPreset(preset, into: destination, policy: policy) {
                        imported.append(entry)
                    }
                }
            } else if let entry = try importPreset(
                Vinegar303Preset.load(from: url),
                into: category,
                policy: policy
            ) {
                imported.append(entry)
            }
        }
        return imported
    }

    public func export(_ entry: Vinegar303PresetEntry, to url: URL) throws {
        let preset = try preset(for: entry)
        do {
            try preset.encoded().write(to: url, options: .atomic)
        } catch {
            throw Vinegar303PresetError.fileOperation(error.localizedDescription)
        }
    }

    /// Build the portable representation of every preset in a category. The
    /// selected category can be the factory category as well as a user folder.
    public func categoryArchive(for category: String) throws -> Vinegar303PresetCategoryArchive {
        let presets = try entries(in: category).map { try preset(for: $0) }
        guard !presets.isEmpty else {
            throw Vinegar303PresetError.emptyCategory
        }
        return Vinegar303PresetCategoryArchive(name: category, presets: presets)
    }

    public func exportCategory(_ category: String, to url: URL) throws {
        let archive = try categoryArchive(for: category)
        do {
            try archive.encoded().write(to: url, options: .atomic)
        } catch {
            throw Vinegar303PresetError.fileOperation(error.localizedDescription)
        }
    }

    private func importPreset(
        _ preset: Vinegar303Preset,
        into category: String,
        policy: Vinegar303PresetImportPolicy
    ) throws -> Vinegar303PresetEntry? {
        var preset = preset
        if let existing = existingEntry(named: preset.name, in: category) {
            switch policy {
            case .skip:
                return nil
            case .keepBoth:
                preset.name = versionedPresetName(preset.name, in: category)
            case .overwrite:
                guard !existing.isFactory, let existingURL = existing.url else {
                    throw Vinegar303PresetError.destinationIsFactory
                }
                preset.name = existing.name
                return try save(preset, category: category, replacing: existingURL)
            }
        }
        return try save(preset, category: category)
    }

    /// Category archives carry their category name. Restore to that folder,
    /// creating it on demand. A collision follows the user's import policy.
    private func categoryForImport(
        named name: String,
        policy: Vinegar303PresetImportPolicy
    ) throws -> String? {
        let base = importCategoryBaseName(named: name)
        if let existing = existingCategory(named: base) {
            switch policy {
            case .skip:
                return nil
            case .keepBoth:
                return try createCategory(versionedCategoryName(base))
            case .overwrite:
                try deleteCategory(existing.name)
                return try createCategory(base)
            }
        }
        return try createCategory(base)
    }

    private func importCategoryBaseName(named name: String) -> String {
        var candidate = sanitizedComponent(name, fallback: "Imported")
        if candidate.caseInsensitiveCompare(Self.factoryCategoryName) == .orderedSame {
            candidate += " Imported"
        }
        return candidate
    }

    private func existingCategory(named name: String) -> Vinegar303PresetCategory? {
        categories.first {
            !$0.isFactory && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func existingEntry(named name: String, in category: String) -> Vinegar303PresetEntry? {
        entries.first {
            $0.category == category && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func versionedCategoryName(_ base: String) -> String {
        var candidate = "\(base) version"
        var suffix = 2
        while existingCategory(named: candidate) != nil {
            candidate = "\(base) version \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func versionedPresetName(_ base: String, in category: String) -> String {
        var candidate = "\(base) version"
        var suffix = 2
        while existingEntry(named: candidate, in: category) != nil {
            candidate = "\(base) version \(suffix)"
            suffix += 1
        }
        return candidate
    }

    // MARK: Pattern copying

    @discardableResult
    public func copyPatterns(
        from source: Vinegar303PresetEntry,
        sourcePatterns: [Int],
        to destination: Vinegar303PresetEntry,
        destinationStart: Int
    ) throws -> Vinegar303PresetEntry {
        guard !destination.isFactory, let destinationURL = destination.url else {
            throw Vinegar303PresetError.destinationIsFactory
        }
        let sourcePreset = try preset(for: source)
        var destinationPreset = try preset(for: destination)

        let start = max(0, min(destinationStart, Vinegar303PatternLibrary.patternCount - 1))
        for (offset, sourceIndex) in sourcePatterns.enumerated() {
            let destinationIndex = start + offset
            guard destinationIndex < Vinegar303PatternLibrary.patternCount else { break }
            guard sourcePreset.sequencer.patterns.indices.contains(sourceIndex),
                  destinationPreset.sequencer.patterns.indices.contains(destinationIndex) else { continue }
            destinationPreset.sequencer.patterns[destinationIndex] = sourcePreset.sequencer.patterns[sourceIndex]
        }

        return try save(
            destinationPreset,
            category: destination.category,
            replacing: destinationURL
        )
    }

    // MARK: Helpers

    private func uniqueURL(in directory: URL, name: String) -> URL {
        let base = sanitizedComponent(name, fallback: "Preset")
        var candidate = directory
            .appendingPathComponent(base)
            .appendingPathExtension(Vinegar303Preset.fileExtension)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(base) \(suffix)")
                .appendingPathExtension(Vinegar303Preset.fileExtension)
            suffix += 1
        }
        return candidate
    }

    private func sanitizedComponent(_ value: String, fallback: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = CharacterSet(charactersIn: "/:\\")
        result = result.components(separatedBy: forbidden).joined(separator: "-")
        result = result.replacingOccurrences(of: "..", with: ".")
        while result.hasPrefix(".") {
            result.removeFirst()
        }
        result = String(result.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? fallback : result
    }

    private static var realHomeDirectory: URL {
        // Inside App Sandbox, FileManager.homeDirectoryForCurrentUser points at
        // the app container. The home-relative exception is based on the real
        // account home, so resolve that path through the POSIX account record.
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private static func resolveLibraryURL() -> (url: URL, isShared: Bool) {
        // The live library lives outside both bundles so reinstalling the host
        // app or AUv3 extension never removes user presets. Both targets carry
        // the matching home-relative sandbox exception in their entitlements.
        let shared = realHomeDirectory
            .appendingPathComponent("Library/Application Support/Vinegar303", isDirectory: true)
            .appendingPathComponent(presetsDirectoryName, isDirectory: true)
        let probe = shared.appendingPathComponent(".vinegar303-write-test")
        do {
            try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
            try Data().write(to: probe, options: .atomic)
            try? FileManager.default.removeItem(at: probe)
            return (shared, true)
        } catch {
            // If the sandbox exception is unavailable, keep the editor usable
            // with a library inside the current process' container.
        }

        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return (
            support
                .appendingPathComponent("Vinegar303", isDirectory: true)
                .appendingPathComponent(presetsDirectoryName, isDirectory: true),
            false
        )
    }
}
