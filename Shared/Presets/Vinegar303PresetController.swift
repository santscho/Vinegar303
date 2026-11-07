import AudioToolbox
import Combine
import Foundation

/// Bridges the file-backed preset library to the live parameter tree and
/// pattern bank. Preset loads write through `AUParameter` so host automation and
/// generic editors observe the same values.
final class Vinegar303PresetController: ObservableObject {
    let library: Vinegar303PresetLibrary
    let parameterTree: AUParameterTree
    let patterns: PatternStore

    @Published private(set) var currentEntry: Vinegar303PresetEntry
    @Published private(set) var isDirty = false

    private let parametersByIdentifier: [String: AUParameter]
    private var parameterObserverToken: AUParameterObserverToken?
    private var cancellables = Set<AnyCancellable>()
    private var presetApplyDepth = 0
    private var isApplyingPreset: Bool { presetApplyDepth > 0 }
    private var parameterBaseline: [AUParameterAddress: AUValue] = [:]

    init(
        library: Vinegar303PresetLibrary,
        parameterTree: AUParameterTree,
        patterns: PatternStore
    ) {
        self.library = library
        self.parameterTree = parameterTree
        self.patterns = patterns
        self.currentEntry = library.factoryEntry
        self.parametersByIdentifier = Dictionary(
            uniqueKeysWithValues: parameterTree.allParameters.compactMap { parameter in
                guard let id = Vinegar303Parameter(rawValue: parameter.address) else { return nil }
                return (Vinegar303ParameterCatalog.spec(id).identifier, parameter)
            }
        )

        observeParameterChanges()
        observePatternChanges()
        observeLibraryChanges()
        snapshotParameterBaseline()
    }

    deinit {
        if let parameterObserverToken {
            parameterTree.removeParameterObserver(parameterObserverToken)
        }
    }

    // MARK: Public state

    var entries: [Vinegar303PresetEntry] {
        library.entries
    }

    func entries(in category: String) -> [Vinegar303PresetEntry] {
        library.entries(in: category)
    }

    var categories: [Vinegar303PresetCategory] {
        library.categories
    }

    var canSaveCurrent: Bool {
        !currentEntry.isFactory
    }

    var currentPatternIndex: Int {
        min(
            max(Int(parameter(.pattern)?.value.rounded() ?? 0), 0),
            Vinegar303PatternLibrary.patternCount - 1
        )
    }

    func currentPreset() throws -> Vinegar303Preset {
        try library.preset(for: currentEntry)
    }

    // MARK: Navigation and loading

    func refreshLibrary() {
        library.reload()
        reconcileCurrentEntry()
    }

    @discardableResult
    func load(_ entry: Vinegar303PresetEntry) throws -> Vinegar303Preset {
        let preset = try library.preset(for: entry)
        apply(preset)
        currentEntry = entry
        isDirty = false
        snapshotParameterBaseline()
        return preset
    }

    @discardableResult
    func step(_ offset: Int) throws -> Vinegar303PresetEntry {
        let allEntries = entries
        guard !allEntries.isEmpty else {
            throw Vinegar303PresetError.fileOperation("No presets are available.")
        }

        let currentIndex = allEntries.firstIndex { $0.id == currentEntry.id }
        let base = currentIndex ?? (offset >= 0 ? -1 : 0)
        let count = allEntries.count
        let nextIndex = ((base + offset) % count + count) % count
        let next = allEntries[nextIndex]
        try load(next)
        return next
    }

    // MARK: Saving

    @discardableResult
    func saveCurrent() throws -> Vinegar303PresetEntry {
        guard !currentEntry.isFactory else {
            throw Vinegar303PresetError.factoryIsReadOnly
        }
        guard let url = currentEntry.url else {
            throw Vinegar303PresetError.fileOperation("The active preset has no file location.")
        }

        let preset = capture(name: currentEntry.name, scope: currentEntry.scope)
        let saved = try library.save(
            preset,
            category: currentEntry.category,
            replacing: url
        )
        currentEntry = saved
        isDirty = false
        snapshotParameterBaseline()
        return saved
    }

    @discardableResult
    func saveAs(
        name: String,
        category: String,
        scope: Vinegar303PresetScope
    ) throws -> Vinegar303PresetEntry {
        let preset = capture(name: name, scope: scope)
        let saved = try library.save(preset, category: category)
        currentEntry = saved
        isDirty = false
        snapshotParameterBaseline()
        return saved
    }

    // MARK: Manager operations

    @discardableResult
    func createCategory(_ name: String) throws -> String {
        let category = try library.createCategory(name)
        reconcileCurrentEntry()
        return category
    }

    @discardableResult
    func renameCategory(_ category: String, to name: String) throws -> String {
        let wasCurrent = !currentEntry.isFactory
            && currentEntry.category.caseInsensitiveCompare(category) == .orderedSame
        let currentName = currentEntry.name
        let wasDirty = isDirty
        let renamed = try library.renameCategory(category, to: name)

        if wasCurrent,
           let updated = entries.first(where: {
               $0.category.caseInsensitiveCompare(renamed) == .orderedSame
                   && $0.name.caseInsensitiveCompare(currentName) == .orderedSame
           }) {
            currentEntry = updated
            isDirty = wasDirty
        } else {
            reconcileCurrentEntry()
        }
        return renamed
    }

    @discardableResult
    func duplicate(_ entry: Vinegar303PresetEntry) throws -> Vinegar303PresetEntry {
        let copy = try library.duplicate(entry)
        reconcileCurrentEntry()
        return copy
    }

    @discardableResult
    func rename(_ entry: Vinegar303PresetEntry, to name: String) throws -> Vinegar303PresetEntry {
        let wasCurrent = entry.id == currentEntry.id
        let renamed = try library.rename(entry, to: name)
        if wasCurrent {
            currentEntry = renamed
        } else {
            reconcileCurrentEntry()
        }
        return renamed
    }

    func delete(_ entry: Vinegar303PresetEntry) throws {
        try library.delete(entry)
        if entry.id == currentEntry.id {
            currentEntry = library.factoryEntry
            isDirty = false
        } else {
            reconcileCurrentEntry()
        }
    }

    @discardableResult
    func deleteCategory(_ category: String) throws -> Int {
        let deletedCount = try library.deleteCategory(category)
        if currentEntry.category == category {
            currentEntry = library.factoryEntry
            isDirty = false
        } else {
            reconcileCurrentEntry()
        }
        return deletedCount
    }

    func importConflicts(
        from urls: [URL],
        into category: String
    ) throws -> [Vinegar303PresetImportConflict] {
        try library.importConflicts(from: urls, into: category)
    }

    @discardableResult
    func importPresets(
        _ urls: [URL],
        into category: String,
        policy: Vinegar303PresetImportPolicy = .keepBoth
    ) throws -> [Vinegar303PresetEntry] {
        let imported = try library.importPresets(from: urls, into: category, policy: policy)
        reconcileCurrentEntry()
        return imported
    }

    func export(_ entry: Vinegar303PresetEntry, to url: URL) throws {
        try library.export(entry, to: url)
    }

    func categoryArchive(for category: String) throws -> Vinegar303PresetCategoryArchive {
        try library.categoryArchive(for: category)
    }

    @discardableResult
    func copyPatterns(
        from source: Vinegar303PresetEntry,
        sourcePatterns: [Int],
        to destination: Vinegar303PresetEntry,
        destinationStart: Int
    ) throws -> Vinegar303PresetEntry {
        if source.id == currentEntry.id, isDirty {
            throw Vinegar303PresetError.activePresetHasUnsavedChanges
        }
        if destination.id == currentEntry.id, isDirty {
            throw Vinegar303PresetError.activePresetHasUnsavedChanges
        }

        let copied = try library.copyPatterns(
            from: source,
            sourcePatterns: sourcePatterns,
            to: destination,
            destinationStart: destinationStart
        )

        if destination.id == currentEntry.id {
            try load(copied)
        } else {
            reconcileCurrentEntry()
        }
        return copied
    }

    // MARK: Applying

    private func apply(_ preset: Vinegar303Preset) {
        // Parameter notifications are delivered asynchronously on the main
        // queue. Keep the application scope alive until those queued callbacks
        // have drained, otherwise the final writes can mark a fresh preset
        // dirty after `load` has already cleared the flag.
        presetApplyDepth += 1

        let bank = preset.sequencer.patternBank
        patterns.replace(with: bank)

        let currentPattern = min(
            max(preset.sequencer.currentPattern, 0),
            Vinegar303PatternLibrary.patternCount - 1
        )
        setParameter(.pattern, value: AUValue(currentPattern))
        let length = bank.indices.contains(currentPattern)
            ? bank[currentPattern].length
            : Vinegar303PatternLibrary.stepsPerPattern
        setParameter(.patternLength, value: AUValue(length))

        if preset.scope == .full {
            applyValues(preset.sound, group: Vinegar303PresetParameterGroups.sound)
            applyValues(preset.scale, group: Vinegar303PresetParameterGroups.scale)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.presetApplyDepth = max(0, self.presetApplyDepth - 1)
        }
    }

    private func applyValues(_ values: [String: Double]?, group: [Vinegar303Parameter]) {
        guard let values else { return }
        for id in group {
            let spec = Vinegar303ParameterCatalog.spec(id)
            guard let raw = values[spec.identifier] else { continue }
            let clamped = min(max(AUValue(raw), spec.minimum), spec.maximum)
            setParameter(id, value: spec.snapped(clamped))
        }
    }

    // MARK: Capture

    private func capture(name: String, scope: Vinegar303PresetScope) -> Vinegar303Preset {
        var bank = patterns.patterns
        let selected = currentPatternIndex

        // The pattern-length parameter is the engine's active mirror. Prefer it
        // for the selected pattern so a host-automated length is captured too.
        if bank.indices.contains(selected), let activeLength = parameter(.patternLength)?.value {
            bank[selected].length = min(
                max(Int(activeLength.rounded()), 1),
                Vinegar303PatternLibrary.stepsPerPattern
            )
        }

        let sequencer = Vinegar303PresetSequencer(
            currentPattern: selected,
            patterns: bank.map(Vinegar303PresetPattern.init)
        )

        let sound = scope == .full ? captureValues(group: Vinegar303PresetParameterGroups.sound) : nil
        let scale = scope == .full ? captureValues(group: Vinegar303PresetParameterGroups.scale) : nil

        return Vinegar303Preset(
            name: name,
            scope: scope,
            sequencer: sequencer,
            sound: sound,
            scale: scale
        )
    }

    private func captureValues(group: [Vinegar303Parameter]) -> [String: Double] {
        var values: [String: Double] = [:]
        for id in group {
            let spec = Vinegar303ParameterCatalog.spec(id)
            if let parameter = parameter(id) {
                values[spec.identifier] = Double(parameter.value)
            } else {
                values[spec.identifier] = Double(spec.defaultValue)
            }
        }
        return values
    }

    // MARK: Observation

    private func observeParameterChanges() {
        parameterObserverToken = parameterTree.token(byAddingParameterObserver: { [weak self] address, _ in
            DispatchQueue.main.async {
                self?.handleParameterChange(address: address)
            }
        })
    }

    private func observePatternChanges() {
        patterns.$patterns
            .dropFirst()
            .sink { [weak self] updatedPatterns in
                guard let self, !self.isApplyingPreset else { return }
                self.synchronizePatternLength(using: updatedPatterns)
                self.isDirty = true
            }
            .store(in: &cancellables)
    }

    private func observeLibraryChanges() {
        library.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        library.$entries
            .dropFirst()
            .sink { [weak self] _ in
                self?.reconcileCurrentEntry()
            }
            .store(in: &cancellables)
    }

    private func handleParameterChange(address: AUParameterAddress) {
        guard !isApplyingPreset,
              let id = Vinegar303Parameter(rawValue: address) else { return }

        switch id {
        case .run, .sync, .midiMode, .tempo:
            return
        case .pattern:
            synchronizePatternLength()
        default:
            break
        }

        if currentEntry.scope == .patterns,
           Vinegar303PresetParameterGroups.sound.contains(id)
            || Vinegar303PresetParameterGroups.scale.contains(id) {
            return
        }

        // Parameter notifications can arrive after the application flag has
        // been released. Comparing the live value with the last loaded/saved
        // baseline prevents those echoes from making a fresh preset dirty.
        if let baseline = parameterBaseline[address],
           abs((parameter(id)?.value ?? 0) - baseline) < 0.0001 {
            return
        }

        isDirty = true
    }

    private func snapshotParameterBaseline() {
        parameterBaseline = Dictionary(
            uniqueKeysWithValues: parameterTree.allParameters.map { ($0.address, $0.value) }
        )
    }

    /// When a preset or a host changes the selected pattern, the active
    /// pattern-length parameter follows the length stored with that pattern.
    private func synchronizePatternLength(using bank: [Vinegar303Pattern]? = nil) {
        let bank = bank ?? patterns.patterns
        guard bank.indices.contains(currentPatternIndex) else { return }
        let length = bank[currentPatternIndex].length
        let parameter = parameter(.patternLength)
        guard Int((parameter?.value ?? 0).rounded()) != length else { return }
        parameter?.setValue(AUValue(length), originator: parameterObserverToken)
    }

    private func reconcileCurrentEntry() {
        guard !currentEntry.isFactory else { return }
        guard let updated = entries.first(where: { $0.id == currentEntry.id }) else {
            currentEntry = library.factoryEntry
            isDirty = false
            return
        }
        currentEntry = updated
    }

    // MARK: Helpers

    private func parameter(_ id: Vinegar303Parameter) -> AUParameter? {
        parameterTree.parameter(withAddress: id.rawValue)
    }

    private func setParameter(_ id: Vinegar303Parameter, value: AUValue) {
        parameter(id)?.setValue(value, originator: parameterObserverToken)
    }
}
