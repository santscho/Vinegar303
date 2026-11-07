import AudioToolbox
import Combine
import Foundation

/// Bridges an `AUParameterTree` to SwiftUI.
///
/// Reads go through a local published snapshot; writes go back to the
/// `AUParameter` with the observer token as originator, which is the
/// automation-safe path used by hosts. Remote automation is fanned back into
/// the snapshot on the main queue.
final class ParameterModel: ObservableObject {
    let tree: AUParameterTree

    private var parameters: [AUParameterAddress: AUParameter] = [:]
    private var observerToken: AUParameterObserverToken?

    @Published private(set) var values: [AUParameterAddress: AUValue] = [:]

    init(tree: AUParameterTree) {
        self.tree = tree
        for parameter in tree.allParameters {
            parameters[parameter.address] = parameter
            values[parameter.address] = parameter.value
        }

        observerToken = tree.token(byAddingParameterObserver: { [weak self] address, value in
            DispatchQueue.main.async {
                guard let self else { return }
                self.values[address] = value
            }
        })
    }

    deinit {
        if let token = observerToken {
            tree.removeParameterObserver(token)
        }
    }

    // MARK: Reads

    func parameter(_ id: Vinegar303Parameter) -> AUParameter? {
        parameters[id.rawValue]
    }

    func value(_ id: Vinegar303Parameter) -> AUValue {
        values[id.rawValue] ?? parameters[id.rawValue]?.value ?? Vinegar303ParameterCatalog.spec(id).defaultValue
    }

    func normalized(_ id: Vinegar303Parameter) -> Double {
        min(max(Vinegar303ParameterCatalog.spec(id).normalized(value(id)), 0), 1)
    }

    func displayValue(_ id: Vinegar303Parameter) -> String {
        Vinegar303ParameterCatalog.spec(id).format(value(id))
    }

    // MARK: Writes

    func setNormalized(_ normalized: Double, for id: Vinegar303Parameter) {
        let spec = Vinegar303ParameterCatalog.spec(id)
        var newValue = spec.value(fromNormalized: min(max(normalized, 0), 1))
        if spec.valueStrings != nil {
            newValue = newValue.rounded()
        }
        write(newValue, for: id)
    }

    func setValue(_ newValue: AUValue, for id: Vinegar303Parameter) {
        let spec = Vinegar303ParameterCatalog.spec(id)
        var clamped = min(max(newValue, spec.minimum), spec.maximum)
        if spec.valueStrings != nil {
            clamped = clamped.rounded()
        }
        write(clamped, for: id)
    }

    /// Marks the start of a user gesture. Hosts use this to identify the
    /// parameter the user just touched and to arm automation recording.
    func beginGesture(_ id: Vinegar303Parameter) {
        guard let parameter = parameters[id.rawValue] else { return }
        parameter.setValue(
            parameter.value,
            originator: observerToken,
            atHostTime: 0,
            eventType: .touch
        )
    }

    /// Marks the end of a user gesture.
    func endGesture(_ id: Vinegar303Parameter) {
        guard let parameter = parameters[id.rawValue] else { return }
        parameter.setValue(
            parameter.value,
            originator: observerToken,
            atHostTime: 0,
            eventType: .release
        )
    }

    /// Writes a discrete control change as one complete user gesture.
    func setValueWithGesture(_ newValue: AUValue, for id: Vinegar303Parameter) {
        beginGesture(id)
        setValue(newValue, for: id)
        endGesture(id)
    }

    func toggle(_ id: Vinegar303Parameter) {
        setValueWithGesture(value(id) >= 0.5 ? 0 : 1, for: id)
    }

    func adjust(_ id: Vinegar303Parameter, by delta: AUValue) {
        setValueWithGesture(value(id) + delta, for: id)
    }

    private func write(_ newValue: AUValue, for id: Vinegar303Parameter) {
        let spec = Vinegar303ParameterCatalog.spec(id)
        let clamped = spec.snapped(newValue)
        values[id.rawValue] = clamped
        parameters[id.rawValue]?.setValue(
            clamped,
            originator: observerToken,
            atHostTime: 0,
            eventType: .value
        )
    }
}

/// Local, observable copy of the sequencer data. Edits are pushed back into the
/// audio unit (which publishes them to its double-buffered pattern bank).
final class PatternStore: ObservableObject {
    @Published private(set) var patterns: [Vinegar303Pattern]

    private let commit: ([Vinegar303Pattern]) -> Void

    init(patterns: [Vinegar303Pattern], commit: @escaping ([Vinegar303Pattern]) -> Void) {
        self.commit = commit
        var normalized = patterns
        while normalized.count < Vinegar303PatternLibrary.patternCount {
            normalized.append(.empty())
        }
        self.patterns = Array(normalized.prefix(Vinegar303PatternLibrary.patternCount))
    }

    func step(pattern: Int, index: Int) -> Vinegar303Step {
        guard patterns.indices.contains(pattern), patterns[pattern].steps.indices.contains(index) else {
            return .rest
        }
        return patterns[pattern][index]
    }

    func setNote(pattern: Int, index: Int, note: Int) {
        update(pattern: pattern, index: index) { $0.note = Vinegar303Step.clampNote(note) }
    }

    func toggleGate(pattern: Int, index: Int) {
        update(pattern: pattern, index: index) { $0.gate.toggle() }
    }

    func toggleAccent(pattern: Int, index: Int) {
        update(pattern: pattern, index: index) { $0.accent.toggle() }
    }

    func toggleSlide(pattern: Int, index: Int) {
        update(pattern: pattern, index: index) { $0.slide.toggle() }
    }

    func setLength(pattern: Int, length: Int) {
        guard patterns.indices.contains(pattern) else { return }
        patterns[pattern].length = min(max(length, 1), Vinegar303PatternLibrary.stepsPerPattern)
        commit(patterns)
    }

    func replace(with newPatterns: [Vinegar303Pattern]) {
        var normalized = Array(newPatterns.prefix(Vinegar303PatternLibrary.patternCount))
        while normalized.count < Vinegar303PatternLibrary.patternCount {
            normalized.append(.empty())
        }
        patterns = normalized
        commit(patterns)
    }

    private func update(pattern: Int, index: Int, _ transform: (inout Vinegar303Step) -> Void) {
        guard patterns.indices.contains(pattern),
              patterns[pattern].steps.indices.contains(index) else { return }
        transform(&patterns[pattern].steps[index])
        commit(patterns)
    }
}
