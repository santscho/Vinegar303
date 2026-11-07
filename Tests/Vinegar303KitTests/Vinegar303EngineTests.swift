import AppKit
import AudioToolbox
import SwiftUI
import XCTest
@testable import Vinegar303Kit

final class Vinegar303EngineTests: XCTestCase {
    private let sampleRate: Double = 48_000

    func testEngineRendersAudibleAudio() {
        let engine = Vinegar303Engine()
        engine.prepare(sampleRate: sampleRate)
        engine.setParameter(.sync, 0)
        engine.setParameter(.run, 1)
        engine.setParameter(.tempo, 132)
        engine.setParameter(.volume, -6)

        let frames = Int(sampleRate)
        var samples = [Float](repeating: 0, count: frames * 2)

        samples.withUnsafeMutableBufferPointer { buffer in
            let audioBuffer = AudioBuffer(
                mNumberChannels: 2,
                mDataByteSize: UInt32(buffer.count * MemoryLayout<Float>.size),
                mData: buffer.baseAddress
            )
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
            withUnsafeMutablePointer(to: &list) { pointer in
                engine.render(
                    into: pointer,
                    frames: frames,
                    frameOffset: 0,
                    hostTempo: nil,
                    hostPlaying: nil
                )
            }
        }

        let peak = samples.map(abs).max() ?? 0
        XCTAssertTrue(peak.isFinite)
        XCTAssertGreaterThan(peak, 0.01, "The internal sequencer should produce audio")
        XCTAssertLessThanOrEqual(peak, 1.0, "The output limiter should keep the signal bounded")
        XCTAssertGreaterThan(engine.playheadStep, 0, "The sequencer should advance")
    }

    func testDelayProducesTailAfterNoteOffWhenEnabled() {
        let engine = makeDelayEngine(enabled: true)
        engine.noteOn(midi: 45, velocity: 100)
        _ = render(engine, frames: 4_800, hostPlaying: nil)

        engine.noteOff(midi: 45)
        // Skip the dry release, then measure 400–500 ms. The 120 ms delay
        // repeats at 120, 240, 360 and 480 ms.
        _ = render(engine, frames: 19_200, hostPlaying: nil)
        let tail = render(engine, frames: 4_800, hostPlaying: nil)
        let peak = tail.map(abs).max() ?? 0

        XCTAssertGreaterThan(peak, 0.005, "The delay should continue after the note is released")
    }

    func testBypassedDelayDoesNotProduceATail() {
        let engine = makeDelayEngine(enabled: false)
        engine.noteOn(midi: 45, velocity: 100)
        _ = render(engine, frames: 4_800, hostPlaying: nil)

        engine.noteOff(midi: 45)
        _ = render(engine, frames: 19_200, hostPlaying: nil)
        let tail = render(engine, frames: 4_800, hostPlaying: nil)
        let peak = tail.map(abs).max() ?? 0

        XCTAssertLessThan(peak, 0.001, "A disabled delay must be fully bypassed")
    }

    func testReenabledDelayDoesNotReplayStaleAudio() {
        let engine = makeDelayEngine(enabled: true)
        engine.noteOn(midi: 45, velocity: 100)
        _ = render(engine, frames: 4_800, hostPlaying: nil)
        engine.noteOff(midi: 45)
        _ = render(engine, frames: 4_800, hostPlaying: nil)

        // Hold the slot bypassed long enough for the dry VCA release to settle;
        // any remaining signal after re-enabling would be the stale delay buffer.
        engine.setParameter(.fx1Enabled, 0)
        _ = render(engine, frames: 96_000, hostPlaying: nil)
        engine.setParameter(.fx1Enabled, 1)
        let revived = render(engine, frames: 4_800, hostPlaying: nil)
        let peak = revived.map(abs).max() ?? 0

        XCTAssertLessThan(peak, 0.001, "Re-enabling a delay must not replay its stale buffer")
    }

    func testDelayDivisionsUseHostTempo() {
        XCTAssertEqual(Vinegar303FXDivision.eighth.seconds(tempo: 120), 0.25, accuracy: 0.0001)
        XCTAssertEqual(Vinegar303FXDivision.eighthDotted.seconds(tempo: 120), 0.375, accuracy: 0.0001)
        XCTAssertEqual(Vinegar303FXDivision.sixteenth.seconds(tempo: 120), 0.125, accuracy: 0.0001)
    }

    func testFXChainModelAddsRemovesAndReorders() {
        let model = ParameterModel(tree: Vinegar303ParameterTreeFactory.makeTree())
        XCTAssertTrue(model.fxActiveSlots.isEmpty)

        let first = model.addFX(.delay)
        let second = model.addFX(.delay)
        XCTAssertEqual(first, .one)
        XCTAssertEqual(second, .two)
        XCTAssertEqual(model.fxActiveSlots, [.one, .two])

        model.setValue(200, for: .fx1Time)
        model.setValue(500, for: .fx2Time)
        model.moveFX(from: 0, to: 1)

        XCTAssertEqual(model.value(.fx1Time), 500)
        XCTAssertEqual(model.value(.fx2Time), 200)

        model.removeFX(.one)
        XCTAssertEqual(model.fxActiveSlots, [.one])
        XCTAssertEqual(model.value(.fx1Time), 200)
    }

    func testFXParametersUseStableAddresses() {
        XCTAssertEqual(Vinegar303Parameter.fx2Type.rawValue, 109)
        XCTAssertEqual(Vinegar303Parameter.fx2Type.fxSlot, .two)
        XCTAssertEqual(Vinegar303Parameter.fx2Type.fxControl, .type)
        XCTAssertEqual(Vinegar303FXSlot.three.parameter(.mix).rawValue, 123)

        let type = Vinegar303ParameterCatalog.spec(.fx1Type)
        XCTAssertEqual(type.identifier, "fx1_type")
        XCTAssertEqual(type.defaultValue, 0)
        XCTAssertEqual(type.valueStrings, ["None", "Delay"])

        let time = Vinegar303ParameterCatalog.spec(.fx1Time)
        XCTAssertEqual(time.defaultValue, 300)
        XCTAssertEqual(time.format(250), "250 ms")

        let division = Vinegar303ParameterCatalog.spec(.fx1Division)
        XCTAssertEqual(division.valueStrings?.count, Vinegar303FXDivision.allCases.count)
        XCTAssertEqual(division.format(1), "1/8")
    }

    func testEngineStaysSilentBeforePreparation() {
        let engine = Vinegar303Engine()
        var samples = [Float](repeating: 1, count: 128)

        samples.withUnsafeMutableBufferPointer { buffer in
            let audioBuffer = AudioBuffer(
                mNumberChannels: 2,
                mDataByteSize: UInt32(buffer.count * MemoryLayout<Float>.size),
                mData: buffer.baseAddress
            )
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
            withUnsafeMutablePointer(to: &list) { pointer in
                engine.render(into: pointer, frames: 64, frameOffset: 0, hostTempo: nil, hostPlaying: nil)
            }
        }

        XCTAssertEqual(samples.max(), 0)
    }

    func testSequencerDefaultsToStopped() {
        let engine = Vinegar303Engine()
        engine.prepare(sampleRate: sampleRate)

        XCTAssertEqual(Vinegar303ParameterCatalog.spec(.run).defaultValue, 0)
        XCTAssertEqual(engine.parameter(.run), 0)

        let samples = render(engine, frames: 4_096, hostPlaying: nil)
        XCTAssertEqual(engine.playheadStep, -1)
        XCTAssertEqual(samples.max() ?? 0, 0, accuracy: 0.0001)
    }

    func testStoppedHostTransportDoesNotStartPlayback() {
        let engine = Vinegar303Engine()
        engine.prepare(sampleRate: sampleRate)
        engine.setParameter(.sync, 1)
        engine.setParameter(.run, 0)

        let samples = render(engine, frames: 4_096, hostPlaying: false)
        XCTAssertEqual(engine.playheadStep, -1)
        XCTAssertEqual(samples.max() ?? 0, 0, accuracy: 0.0001)
    }

    func testHostTransportStartsSequencerWhenRunIsStopped() {
        let engine = Vinegar303Engine()
        engine.prepare(sampleRate: sampleRate)
        engine.setParameter(.sync, 1)
        engine.setParameter(.run, 0)

        let samples = render(engine, frames: 4_800, hostPlaying: true)
        let peak = samples.map(abs).max() ?? 0
        XCTAssertGreaterThanOrEqual(engine.playheadStep, 0)
        XCTAssertGreaterThan(peak, 0.01)
    }

    func testFreeToHostWhilePlayingAlignsToHostAndHostStopTakesOver() {
        let engine = Vinegar303Engine()
        engine.prepare(sampleRate: sampleRate)
        engine.setParameter(.sync, 0)
        engine.setParameter(.run, 1)
        engine.setParameter(.tempo, 120)

        _ = render(engine, frames: 12_000, hostPlaying: true, hostTempo: 120)

        // Host is at step 4.1667. Re-entering Host mode must jump there and
        // continue from that phase, not from the Free-running position.
        engine.setParameter(.sync, 1)
        let aligned = render(
            engine,
            frames: 64,
            hostPlaying: true,
            hostTempo: 120,
            hostSamplePosition: 25_000
        )
        XCTAssertEqual(engine.playheadStep, 4)
        XCTAssertGreaterThan(aligned.map(abs).max() ?? 0, 0.001)

        // Run is still 1, but Host mode is authoritative, so host stop must win.
        _ = render(engine, frames: 64, hostPlaying: false, hostTempo: 120)
        XCTAssertEqual(engine.playheadStep, -1)
    }

    func testHostSyncAlignsUsingBeatFallback() {
        let engine = Vinegar303Engine()
        engine.prepare(sampleRate: sampleRate)
        engine.setParameter(.sync, 1)
        engine.setParameter(.run, 0)
        engine.setParameter(.tempo, 120)

        _ = render(engine, frames: 64, hostPlaying: true, hostTempo: 120, hostBeatPosition: 6.5)
        XCTAssertEqual(engine.playheadStep, 10)
    }

    func testHalfSpeedAlignsToHostBeatFallback() {
        let engine = Vinegar303Engine()
        engine.prepare(sampleRate: sampleRate)
        engine.setParameter(.sync, 1)
        engine.setParameter(.run, 0)
        engine.setParameter(.tempo, 120)
        engine.setParameter(.halfSpeed, 1)

        _ = render(engine, frames: 64, hostPlaying: true, hostTempo: 120, hostBeatPosition: 6.5)
        XCTAssertEqual(engine.playheadStep, 13)
    }

    func testManualRunStartsWithoutHostTransport() {
        let engine = Vinegar303Engine()
        engine.prepare(sampleRate: sampleRate)
        engine.setParameter(.sync, 1)
        engine.setParameter(.run, 1)

        let samples = render(engine, frames: 4_800, hostPlaying: nil)
        let peak = samples.map(abs).max() ?? 0
        XCTAssertGreaterThanOrEqual(engine.playheadStep, 0)
        XCTAssertGreaterThan(peak, 0.01)
    }

    func testHalfSpeedDoublesFreeRunningStepDuration() {
        func playhead(after frames: Int, halfSpeed: AUValue) -> Int {
            let engine = Vinegar303Engine()
            engine.prepare(sampleRate: sampleRate)
            engine.setParameter(.sync, 0)
            engine.setParameter(.run, 1)
            engine.setParameter(.tempo, 120)
            engine.setParameter(.halfSpeed, halfSpeed)
            _ = render(engine, frames: frames, hostPlaying: nil)
            return engine.playheadStep
        }

        // 120 BPM at 48 kHz gives 6,000 samples per 16th-note step; 1:2
        // doubles that to 12,000 without changing the integer step index.
        XCTAssertEqual(playhead(after: 6_000, halfSpeed: 0), 1)
        XCTAssertEqual(playhead(after: 6_000, halfSpeed: 1), 0)
        XCTAssertEqual(playhead(after: 12_000, halfSpeed: 1), 1)
    }

    func testHalfSpeedScalesHostTempo() {
        let engine = Vinegar303Engine()
        engine.prepare(sampleRate: sampleRate)
        engine.setParameter(.sync, 1)
        engine.setParameter(.run, 0)
        engine.setParameter(.tempo, 120)
        engine.setParameter(.halfSpeed, 1)

        _ = render(engine, frames: 6_000, hostPlaying: true, hostTempo: 120)
        XCTAssertEqual(engine.playheadStep, 0)
        _ = render(engine, frames: 6_000, hostPlaying: true, hostTempo: 120)
        XCTAssertEqual(engine.playheadStep, 1)
    }

    func testParameterTreeOpensInStop() {
        let tree = Vinegar303ParameterTreeFactory.makeTree()
        let run = tree.parameter(withAddress: Vinegar303Parameter.run.rawValue)
        XCTAssertEqual(run?.value, 0)
    }

    func testParameterTreeExposesHostAutomationFlags() {
        let tree = Vinegar303ParameterTreeFactory.makeTree()
        XCTAssertEqual(tree.allParameters.count, Vinegar303Parameter.allCases.count)

        for parameter in tree.allParameters {
            XCTAssertTrue(
                parameter.flags.contains(.flag_IsReadable),
                "\(parameter.identifier) must be readable by the host"
            )
            XCTAssertTrue(
                parameter.flags.contains(.flag_IsWritable),
                "\(parameter.identifier) must be writable by the host"
            )
        }

        let cutoff = tree.parameter(withAddress: Vinegar303Parameter.cutoff.rawValue)
        XCTAssertEqual(cutoff?.flags.contains(.flag_CanRamp), true)

        let pattern = tree.parameter(withAddress: Vinegar303Parameter.pattern.rawValue)
        XCTAssertEqual(pattern?.flags.contains(.flag_CanRamp), false)
    }

    func testParameterModelEmitsTouchValueReleaseAutomationEvents() {
        let tree = Vinegar303ParameterTreeFactory.makeTree()
        let expectation = expectation(description: "Touch, value and release events")
        let lock = NSLock()
        var events: [AUParameterAutomationEventType] = []
        var fulfilled = false

        let token = tree.token(byAddingParameterAutomationObserver: { count, eventPointer in
            lock.lock()
            for index in 0..<count {
                events.append(eventPointer[index].eventType)
            }
            let shouldFulfill = !fulfilled && events.contains(.touch) && events.contains(.release)
            if shouldFulfill { fulfilled = true }
            lock.unlock()
            if shouldFulfill { expectation.fulfill() }
        })
        defer { tree.removeParameterObserver(token) }

        let model = ParameterModel(tree: tree)
        model.setValueWithGesture(75, for: .resonance)

        wait(for: [expectation], timeout: 1)

        lock.lock()
        let captured = events
        lock.unlock()

        XCTAssertEqual(captured.first, .touch)
        XCTAssertTrue(captured.contains(.value))
        XCTAssertEqual(captured.last, .release)
    }

    func testEditorModelOpensStopped() {
        let model = ParameterModel(tree: Vinegar303ParameterTreeFactory.makeTree())
        XCTAssertEqual(model.value(.run), 0)
    }

    @MainActor
    func testAUViewControllerUsesFullCanvasAndFillsHostBounds() throws {
        let controller = Vinegar303AUViewController()
        controller.loadView()
        XCTAssertEqual(controller.preferredContentSize.width, 1_300, accuracy: 0.1)

        let tree = Vinegar303ParameterTreeFactory.makeTree()
        let patterns = PatternStore(patterns: Vinegar303PatternLibrary.factory()) { _ in }
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vinegar303PresetTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let library = Vinegar303PresetLibrary(rootURL: temporaryDirectory)
        let presets = Vinegar303PresetController(
            library: library,
            parameterTree: tree,
            patterns: patterns
        )
        let editor = Vinegar303Editor(
            parameterTree: tree,
            patterns: patterns,
            presets: presets,
            playhead: { -1 }
        )
        let hosting = NSHostingView(rootView: editor.frame(width: 1_300))
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(
            controller.preferredContentSize.height,
            hosting.fittingSize.height,
            accuracy: 0.5,
            "The AU canvas must be fitted to the complete editor"
        )

        _ = try controller.createAudioUnit(with: Vinegar303AudioUnit.componentDescription)
        controller.view.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(controller.view.subviews.count, 1)
        XCTAssertEqual(controller.view.subviews[0].frame, controller.view.bounds)
    }

    func testAudioUnitInstantiationAndStateRecallOpenInStop() throws {
        let unit = try Vinegar303AudioUnit(componentDescription: Vinegar303AudioUnit.componentDescription)
        let run = unit.editorParameterTree.parameter(withAddress: Vinegar303Parameter.run.rawValue)
        XCTAssertEqual(run?.value, 0)

        run?.value = 1
        XCTAssertEqual(run?.value, 1)

        unit.fullState = unit.fullState
        XCTAssertEqual(run?.value, 0)
    }

    func testFactoryBankIsFullyPopulatedAndPlayable() throws {
        let bank = Vinegar303PatternLibrary.factory()
        XCTAssertEqual(bank.count, Vinegar303PatternLibrary.patternCount)

        let signatures = bank.map { pattern in
            "\(pattern.length):" + pattern.steps.map {
                "\($0.note),\($0.gate),\($0.accent),\($0.slide)"
            }.joined(separator: "|")
        }
        XCTAssertEqual(Set(signatures).count, bank.count, "Every factory pattern must be distinct")

        for (patternIndex, pattern) in bank.enumerated() {
            XCTAssertEqual(pattern.length, Vinegar303PatternLibrary.stepsPerPattern)
            XCTAssertGreaterThanOrEqual(
                pattern.steps.filter(\.gate).count,
                6,
                "Pattern \(patternIndex + 1) is too sparse"
            )

            for (stepIndex, step) in pattern.steps.enumerated() {
                XCTAssertTrue(
                    (Vinegar303PatternLibrary.lowestNote...Vinegar303PatternLibrary.highestNote).contains(step.note)
                )
                if step.accent {
                    XCTAssertTrue(step.gate, "Accent must land on a gated step")
                }
                if step.slide {
                    XCTAssertTrue(step.gate, "Slide must start on a gated step")
                    XCTAssertTrue(
                        pattern.steps[(stepIndex + 1) % pattern.length].gate,
                        "Slide \(patternIndex + 1)/\(stepIndex + 1) must resolve to a gated step"
                    )
                }
            }
        }

        let factory = try Vinegar303Preset.factory()
        XCTAssertEqual(factory.sequencer.patterns.count, Vinegar303PatternLibrary.patternCount)
        XCTAssertTrue(factory.sequencer.patterns.allSatisfy { $0.steps.contains { $0.gate } })
    }

    func testPatternBankRoundTrips() {
        let engine = Vinegar303Engine()
        var patterns = engine.patterns
        let edited = Vinegar303Step(note: 45, gate: true, accent: true, slide: true)
        patterns[2].steps[7] = edited
        patterns[2].length = 7
        engine.patterns = patterns

        XCTAssertEqual(engine.patterns[2].steps[7], edited)
        XCTAssertEqual(engine.patterns[2].length, 7)
        XCTAssertEqual(engine.patterns.count, Vinegar303PatternLibrary.patternCount)
    }

    func testPresetDocumentRoundTripsPerPatternLengths() throws {
        var factory = try Vinegar303Preset.factory()
        factory.name = "Lengths"
        factory.sequencer.patterns[3].length = 7

        let decoded = try Vinegar303Preset.decode(try factory.encoded())
        XCTAssertEqual(decoded.name, "Lengths")
        XCTAssertEqual(decoded.scope, .full)
        XCTAssertEqual(decoded.sequencer.patterns.count, Vinegar303PatternLibrary.patternCount)
        XCTAssertEqual(decoded.sequencer.patterns[3].length, 7)
        XCTAssertNotNil(decoded.sound)
        XCTAssertNotNil(decoded.scale)
    }

    func testPatternsOnlyPresetOmitsSoundAndScale() throws {
        var preset = try Vinegar303Preset.factory()
        preset.name = "Patterns Only"
        preset.scope = .patterns

        let decoded = try Vinegar303Preset.decode(try preset.encoded())
        XCTAssertEqual(decoded.scope, .patterns)
        XCTAssertNil(decoded.sound)
        XCTAssertNil(decoded.scale)
    }

    func testPresetLibraryStoresCategoriesAndPatternCopies() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vinegar303PresetTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let library = Vinegar303PresetLibrary(rootURL: temporaryDirectory)

        var source = try Vinegar303Preset.factory()
        source.name = "Source"
        source.sequencer.patterns[0].length = 5
        let sourceEntry = try library.save(source, category: "Techno")

        var destination = try Vinegar303Preset.factory()
        destination.name = "Destination"
        let destinationEntry = try library.save(destination, category: "Techno")

        let copied = try library.copyPatterns(
            from: sourceEntry,
            sourcePatterns: [0],
            to: destinationEntry,
            destinationStart: 4
        )
        let loaded = try library.preset(for: copied)
        XCTAssertEqual(library.entries(in: "Techno").count, 2)
        XCTAssertEqual(loaded.sequencer.patterns[4].length, 5)
        XCTAssertTrue(library.categories.contains { $0.name == "Techno" && $0.count == 2 })
        XCTAssertThrowsError(try library.save(source, category: Vinegar303PresetLibrary.factoryCategoryName))
    }

    func testPresetLibraryExportsSinglePresetAndFullCategory() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vinegar303PresetTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let library = Vinegar303PresetLibrary(rootURL: temporaryDirectory)

        var first = try Vinegar303Preset.factory()
        first.name = "First"
        first.sequencer.patterns[2].length = 7
        let firstEntry = try library.save(first, category: "Bank")

        var second = try Vinegar303Preset.factory()
        second.name = "Second"
        second.scope = .patterns
        _ = try library.save(second, category: "Bank")

        let archive = try library.categoryArchive(for: "Bank")
        XCTAssertEqual(archive.name, "Bank")
        XCTAssertEqual(archive.presets.count, 2)
        XCTAssertEqual(archive.presets.first { $0.name == "First" }?.sequencer.patterns[2].length, 7)
        XCTAssertEqual(
            archive.presets.first { $0.name == "First" }?.sequencer.patterns.count,
            Vinegar303PatternLibrary.patternCount
        )
        XCTAssertEqual(archive.presets.first { $0.name == "Second" }?.scope, .patterns)

        let categoryURL = temporaryDirectory.appendingPathComponent("Bank.v303category")
        try library.exportCategory("Bank", to: categoryURL)
        let decodedArchive = try Vinegar303PresetCategoryArchive.load(from: categoryURL)
        XCTAssertEqual(decodedArchive.presets.count, 2)
        XCTAssertEqual(decodedArchive.presets.first { $0.name == "First" }?.sequencer.patterns[2].length, 7)

        let singleURL = temporaryDirectory.appendingPathComponent("First.v303preset")
        try library.export(firstEntry, to: singleURL)
        XCTAssertEqual(try Vinegar303Preset.load(from: singleURL).name, "First")
    }

    func testPresetLibraryImportsCategoryArchiveAndCreatesCategory() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vinegar303PresetTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let library = Vinegar303PresetLibrary(rootURL: temporaryDirectory)

        var first = try Vinegar303Preset.factory()
        first.name = "First"
        first.sequencer.patterns[1].length = 9
        _ = try library.save(first, category: "Source")

        var second = try Vinegar303Preset.factory()
        second.name = "Second"
        _ = try library.save(second, category: "Source")

        let categoryURL = temporaryDirectory.appendingPathComponent("Source.v303category")
        try library.exportCategory("Source", to: categoryURL)
        try library.deleteCategory("Source")
        XCTAssertFalse(library.categories.contains { $0.name == "Source" })

        // A category archive restores its own folder; the selected target is
        // irrelevant and no category has to exist beforehand.
        let imported = try library.importPresets(
            from: [categoryURL],
            into: Vinegar303PresetLibrary.factoryCategoryName
        )
        XCTAssertEqual(imported.count, 2)
        XCTAssertTrue(library.categories.contains { $0.name == "Source" })
        XCTAssertEqual(library.entries(in: "Source").count, 2)
        XCTAssertTrue(imported.allSatisfy { $0.category == "Source" })

        guard let importedFirst = imported.first(where: { $0.name == "First" }) else {
            return XCTFail("The category import must preserve preset names")
        }
        let loaded = try library.preset(for: importedFirst)
        XCTAssertEqual(loaded.sequencer.patterns[1].length, 9)
        XCTAssertEqual(loaded.sequencer.patterns.count, Vinegar303PatternLibrary.patternCount)
    }

    func testCategoryImportConflictPolicies() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vinegar303PresetTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let library = Vinegar303PresetLibrary(rootURL: temporaryDirectory)

        var first = try Vinegar303Preset.factory()
        first.name = "First"
        _ = try library.save(first, category: "Source")

        var second = try Vinegar303Preset.factory()
        second.name = "Second"
        _ = try library.save(second, category: "Source")

        let categoryURL = temporaryDirectory.appendingPathComponent("Source.v303category")
        try library.exportCategory("Source", to: categoryURL)

        var stale = try Vinegar303Preset.factory()
        stale.name = "Stale"
        _ = try library.save(stale, category: "Source")

        let conflicts = try library.importConflicts(from: [categoryURL], into: "User")
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts.first?.kind, .category)
        XCTAssertEqual(conflicts.first?.name, "Source")

        let skipped = try library.importPresets(from: [categoryURL], into: "User", policy: .skip)
        XCTAssertTrue(skipped.isEmpty)
        XCTAssertEqual(library.entries(in: "Source").count, 3)
        XCTAssertFalse(library.categories.contains { $0.name == "Source version" })

        let kept = try library.importPresets(from: [categoryURL], into: "User", policy: .keepBoth)
        XCTAssertEqual(kept.count, 2)
        XCTAssertEqual(kept.first?.category, "Source version")
        XCTAssertEqual(library.entries(in: "Source version").count, 2)

        let overwritten = try library.importPresets(from: [categoryURL], into: "User", policy: .overwrite)
        XCTAssertEqual(overwritten.count, 2)
        XCTAssertEqual(library.entries(in: "Source").count, 2)
        XCTAssertFalse(library.entries(in: "Source").contains { $0.name == "Stale" })
    }

    func testPresetImportConflictPolicies() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vinegar303PresetTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let library = Vinegar303PresetLibrary(rootURL: temporaryDirectory)

        var existing = try Vinegar303Preset.factory()
        existing.name = "Lead"
        existing.sequencer.patterns[0].length = 3
        _ = try library.save(existing, category: "User")

        var importedPreset = try Vinegar303Preset.factory()
        importedPreset.name = "Lead"
        importedPreset.sequencer.patterns[0].length = 9
        let presetURL = temporaryDirectory.appendingPathComponent("Lead.v303preset")
        try importedPreset.encoded().write(to: presetURL, options: .atomic)

        let conflicts = try library.importConflicts(from: [presetURL], into: "User")
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts.first?.kind, .preset)
        XCTAssertEqual(conflicts.first?.name, "Lead")
        XCTAssertEqual(conflicts.first?.category, "User")

        let skipped = try library.importPresets(from: [presetURL], into: "User", policy: .skip)
        XCTAssertTrue(skipped.isEmpty)
        XCTAssertEqual(library.entries(in: "User").count, 1)

        let kept = try library.importPresets(from: [presetURL], into: "User", policy: .keepBoth)
        XCTAssertEqual(kept.first?.name, "Lead version")
        XCTAssertEqual(library.entries(in: "User").count, 2)

        let overwritten = try library.importPresets(from: [presetURL], into: "User", policy: .overwrite)
        guard let overwrittenFirst = overwritten.first else {
            return XCTFail("Overwrite must import the existing preset")
        }
        let loaded = try library.preset(for: overwrittenFirst)
        XCTAssertEqual(overwrittenFirst.name, "Lead")
        XCTAssertEqual(loaded.sequencer.patterns[0].length, 9)
        XCTAssertEqual(library.entries(in: "User").count, 2)
    }

    func testPresetLibraryDeletesCategoryWithContainedPresets() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vinegar303PresetTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let library = Vinegar303PresetLibrary(rootURL: temporaryDirectory)

        var first = try Vinegar303Preset.factory()
        first.name = "First"
        _ = try library.save(first, category: "Delete Me")

        var second = try Vinegar303Preset.factory()
        second.name = "Second"
        _ = try library.save(second, category: "Delete Me")

        var keep = try Vinegar303Preset.factory()
        keep.name = "Keep"
        _ = try library.save(keep, category: "Keep")

        let deletedCount = try library.deleteCategory("Delete Me")
        XCTAssertEqual(deletedCount, 2)
        XCTAssertFalse(library.categories.contains { $0.name == "Delete Me" })
        XCTAssertTrue(library.entries(in: "Delete Me").isEmpty)
        XCTAssertEqual(library.entries(in: "Keep").count, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: temporaryDirectory.appendingPathComponent("Delete Me").path
            )
        )
        XCTAssertThrowsError(try library.deleteCategory(Vinegar303PresetLibrary.factoryCategoryName))
        XCTAssertThrowsError(try library.deleteCategory("Missing"))
    }

    func testPresetLibraryRenamesCategoryAndPreservesPresets() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vinegar303PresetTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let library = Vinegar303PresetLibrary(rootURL: temporaryDirectory)

        var first = try Vinegar303Preset.factory()
        first.name = "First"
        first.sequencer.patterns[0].length = 6
        _ = try library.save(first, category: "Old")

        var second = try Vinegar303Preset.factory()
        second.name = "Second"
        _ = try library.save(second, category: "Old")

        var other = try Vinegar303Preset.factory()
        other.name = "Other"
        _ = try library.save(other, category: "Other")

        let renamed = try library.renameCategory("Old", to: "New")

        XCTAssertEqual(renamed, "New")
        XCTAssertFalse(library.categories.contains { $0.name == "Old" })
        XCTAssertTrue(library.categories.contains { $0.name == "New" && $0.count == 2 })
        XCTAssertEqual(library.entries(in: "New").count, 2)
        XCTAssertTrue(library.entries(in: "New").allSatisfy { $0.category == "New" })
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: temporaryDirectory.appendingPathComponent("Old").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: temporaryDirectory.appendingPathComponent("New").path
            )
        )

        guard let firstEntry = library.entries(in: "New").first(where: { $0.name == "First" }) else {
            return XCTFail("Renaming a category must preserve its presets")
        }
        let loaded = try library.preset(for: firstEntry)
        XCTAssertEqual(loaded.sequencer.patterns[0].length, 6)

        XCTAssertThrowsError(try library.renameCategory("New", to: "Other"))
        XCTAssertThrowsError(
            try library.renameCategory(Vinegar303PresetLibrary.factoryCategoryName, to: "Nope")
        )
        XCTAssertThrowsError(try library.renameCategory("Missing", to: "Nope"))
        XCTAssertThrowsError(try library.renameCategory("New", to: "   "))
    }

    func testRenamingActiveCategoryKeepsCurrentPreset() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vinegar303PresetTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let tree = Vinegar303ParameterTreeFactory.makeTree()
        let patterns = PatternStore(patterns: Vinegar303PatternLibrary.factory()) { _ in }
        let library = Vinegar303PresetLibrary(rootURL: temporaryDirectory)
        let controller = Vinegar303PresetController(
            library: library,
            parameterTree: tree,
            patterns: patterns
        )

        _ = try controller.saveAs(name: "Keep", category: "Old", scope: .full)
        let renamed = try controller.renameCategory("Old", to: "New")

        XCTAssertEqual(renamed, "New")
        XCTAssertEqual(controller.currentEntry.name, "Keep")
        XCTAssertEqual(controller.currentEntry.category, "New")
        XCTAssertFalse(controller.currentEntry.isFactory)
        XCTAssertTrue(library.entries(in: "New").contains { $0.id == controller.currentEntry.id })
    }

    func testDeletingActiveCategoryFallsBackToFactory() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vinegar303PresetTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let tree = Vinegar303ParameterTreeFactory.makeTree()
        let patterns = PatternStore(patterns: Vinegar303PatternLibrary.factory()) { _ in }
        let library = Vinegar303PresetLibrary(rootURL: temporaryDirectory)
        let controller = Vinegar303PresetController(
            library: library,
            parameterTree: tree,
            patterns: patterns
        )

        _ = try controller.saveAs(name: "Doomed", category: "Trash", scope: .full)
        let deletedCount = try controller.deleteCategory("Trash")

        XCTAssertEqual(deletedCount, 1)
        XCTAssertEqual(controller.currentEntry.id, library.factoryEntry.id)
        XCTAssertFalse(controller.isDirty)
        XCTAssertFalse(library.categories.contains { $0.name == "Trash" })
    }

    func testFactoryCategoryArchiveImportsUnderSafeUserName() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vinegar303PresetTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let library = Vinegar303PresetLibrary(rootURL: temporaryDirectory)

        let categoryURL = temporaryDirectory.appendingPathComponent("Factory.v303category")
        try library.exportCategory(Vinegar303PresetLibrary.factoryCategoryName, to: categoryURL)

        let imported = try library.importPresets(from: [categoryURL], into: "User")
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.category, "Factory Imported")
        XCTAssertTrue(library.categories.contains { $0.name == "Factory Imported" })
    }

    func testPatternLengthsRoundTripThroughFullState() throws {
        let unit = try Vinegar303AudioUnit(componentDescription: Vinegar303AudioUnit.componentDescription)
        var patterns = unit.patterns
        patterns[5].length = 9
        unit.patterns = patterns

        let state = unit.fullState
        patterns[5].length = 16
        unit.patterns = patterns
        unit.fullState = state

        XCTAssertEqual(unit.patterns[5].length, 9)
    }

    func testFXParametersRoundTripThroughFullState() throws {
        let unit = try Vinegar303AudioUnit(componentDescription: Vinegar303AudioUnit.componentDescription)
        let tree = unit.editorParameterTree
        guard let type = tree.parameter(withAddress: Vinegar303Parameter.fx1Type.rawValue),
              let enabled = tree.parameter(withAddress: Vinegar303Parameter.fx1Enabled.rawValue),
              let time = tree.parameter(withAddress: Vinegar303Parameter.fx1Time.rawValue),
              let feedback = tree.parameter(withAddress: Vinegar303Parameter.fx1Feedback.rawValue),
              let tone = tree.parameter(withAddress: Vinegar303Parameter.fx1Tone.rawValue),
              let mix = tree.parameter(withAddress: Vinegar303Parameter.fx1Mix.rawValue),
              let sync = tree.parameter(withAddress: Vinegar303Parameter.fx1Sync.rawValue),
              let division = tree.parameter(withAddress: Vinegar303Parameter.fx1Division.rawValue),
              let pingPong = tree.parameter(withAddress: Vinegar303Parameter.fx1PingPong.rawValue)
        else {
            return XCTFail("Missing FX parameters")
        }

        type.value = 1
        enabled.value = 1
        time.value = 180
        feedback.value = 42
        tone.value = 63
        mix.value = 37
        sync.value = 0
        division.value = 2
        pingPong.value = 1

        let state = unit.fullState

        type.value = 0
        enabled.value = 0
        time.value = 300
        feedback.value = 35
        tone.value = 55
        mix.value = 25
        sync.value = 1
        division.value = 1
        pingPong.value = 0
        unit.fullState = state

        XCTAssertEqual(type.value, 1)
        XCTAssertEqual(enabled.value, 1)
        XCTAssertEqual(time.value, 180)
        XCTAssertEqual(feedback.value, 42)
        XCTAssertEqual(tone.value, 63)
        XCTAssertEqual(mix.value, 37)
        XCTAssertEqual(sync.value, 0)
        XCTAssertEqual(division.value, 2)
        XCTAssertEqual(pingPong.value, 1)
    }

    func testPresetCapturesDelayChain() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vinegar303PresetTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let tree = Vinegar303ParameterTreeFactory.makeTree()
        let patterns = PatternStore(patterns: Vinegar303PatternLibrary.factory()) { _ in }
        let controller = Vinegar303PresetController(
            library: Vinegar303PresetLibrary(rootURL: temporaryDirectory),
            parameterTree: tree,
            patterns: patterns
        )

        guard let type = tree.parameter(withAddress: Vinegar303Parameter.fx1Type.rawValue),
              let enabled = tree.parameter(withAddress: Vinegar303Parameter.fx1Enabled.rawValue),
              let time = tree.parameter(withAddress: Vinegar303Parameter.fx1Time.rawValue),
              let feedback = tree.parameter(withAddress: Vinegar303Parameter.fx1Feedback.rawValue),
              let mix = tree.parameter(withAddress: Vinegar303Parameter.fx1Mix.rawValue)
        else {
            return XCTFail("Missing FX parameters")
        }

        type.value = 1
        enabled.value = 1
        time.value = 240
        feedback.value = 55
        mix.value = 40

        let entry = try controller.saveAs(name: "Delay Chain", category: "User", scope: .full)

        type.value = 0
        enabled.value = 0
        time.value = 300
        feedback.value = 35
        mix.value = 25
        _ = try controller.load(entry)

        XCTAssertEqual(type.value, 1)
        XCTAssertEqual(enabled.value, 1)
        XCTAssertEqual(time.value, 240)
        XCTAssertEqual(feedback.value, 55)
        XCTAssertEqual(mix.value, 40)
    }

    func testPresetControllerSavesLoadsAndKeepsScopeIsolation() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vinegar303PresetTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let tree = Vinegar303ParameterTreeFactory.makeTree()
        let patterns = PatternStore(patterns: Vinegar303PatternLibrary.factory()) { _ in }
        let library = Vinegar303PresetLibrary(rootURL: temporaryDirectory)
        let controller = Vinegar303PresetController(
            library: library,
            parameterTree: tree,
            patterns: patterns
        )

        guard let cutoff = tree.parameter(withAddress: Vinegar303Parameter.cutoff.rawValue),
              let halfSpeed = tree.parameter(withAddress: Vinegar303Parameter.halfSpeed.rawValue) else {
            return XCTFail("Missing sound parameter")
        }

        cutoff.value = 777
        halfSpeed.value = 1
        patterns.setLength(pattern: 0, length: 7)
        let full = try controller.saveAs(name: "Full", category: "User", scope: .full)
        XCTAssertEqual(controller.currentEntry.id, full.id)
        XCTAssertFalse(controller.isDirty)

        cutoff.value = 250
        halfSpeed.value = 0
        _ = try controller.load(full)
        XCTAssertEqual(cutoff.value, 777, accuracy: 0.1)
        XCTAssertEqual(halfSpeed.value, 1)
        XCTAssertEqual(patterns.patterns[0].length, 7)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(controller.isDirty, "Loading a preset must not leave it marked dirty")

        let patternsOnly = try controller.saveAs(name: "Patterns", category: "User", scope: .patterns)
        cutoff.value = 250
        halfSpeed.value = 0
        _ = try controller.load(patternsOnly)
        XCTAssertEqual(cutoff.value, 250, accuracy: 0.1)
        XCTAssertEqual(halfSpeed.value, 0)
        XCTAssertEqual(controller.currentEntry.scope, .patterns)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(controller.isDirty, "Loading a patterns preset must not leave it marked dirty")

        _ = try controller.load(library.factoryEntry)
        XCTAssertThrowsError(try controller.saveCurrent())
    }

    private func makeDelayEngine(enabled: Bool) -> Vinegar303Engine {
        let engine = Vinegar303Engine()
        engine.prepare(sampleRate: sampleRate)
        engine.setParameter(.sync, 0)
        engine.setParameter(.run, 0)
        engine.setParameter(.midiMode, 1)
        engine.setParameter(.cutoff, 2_000)
        engine.setParameter(.resonance, 0)
        engine.setParameter(.envmod, 0)
        engine.setParameter(.decay, 40)
        engine.setParameter(.waveform, 1)
        engine.setParameter(.volume, 0)
        engine.setParameter(.distortion, 0)
        engine.setParameter(.drive, 0)
        engine.setParameter(.fx1Type, 1)
        engine.setParameter(.fx1Enabled, enabled ? 1 : 0)
        engine.setParameter(.fx1Sync, 0)
        engine.setParameter(.fx1Time, 120)
        engine.setParameter(.fx1Feedback, 40)
        engine.setParameter(.fx1Tone, 80)
        engine.setParameter(.fx1Mix, 50)
        engine.setParameter(.fx1PingPong, 0)
        return engine
    }

    private func render(
        _ engine: Vinegar303Engine,
        frames: Int,
        hostPlaying: Bool?,
        hostTempo: Double? = nil,
        hostSamplePosition: Double? = nil,
        hostBeatPosition: Double? = nil
    ) -> [Float] {
        var samples = [Float](repeating: 0, count: frames * 2)
        samples.withUnsafeMutableBufferPointer { buffer in
            let audioBuffer = AudioBuffer(
                mNumberChannels: 2,
                mDataByteSize: UInt32(buffer.count * MemoryLayout<Float>.size),
                mData: buffer.baseAddress
            )
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
            withUnsafeMutablePointer(to: &list) { pointer in
                engine.render(
                    into: pointer,
                    frames: frames,
                    frameOffset: 0,
                    hostTempo: hostTempo,
                    hostPlaying: hostPlaying,
                    hostSamplePosition: hostSamplePosition,
                    hostBeatPosition: hostBeatPosition
                )
            }
        }
        return samples
    }

    func testScaleQuantizerUsesNearestNoteAndQuantizesTiesUp() {
        // E Minor: E F# G A B C D. F natural is exactly between E and F#.
        XCTAssertEqual(Vinegar303Scale.quantize(note: 41, key: 4, mode: 1), 42)
        XCTAssertEqual(Vinegar303Scale.quantize(note: 40, key: 4, mode: 1), 40)
        XCTAssertEqual(Vinegar303Scale.quantize(note: 42, key: 4, mode: 1), 42)

        // C# in C Major is between C and D; the tie resolves upward to D.
        XCTAssertEqual(Vinegar303Scale.quantize(note: 61, key: 0, mode: 0), 62)

        // A# in A Dorian is between A and B; the tie resolves upward to B.
        XCTAssertEqual(Vinegar303Scale.quantize(note: 70, key: 9, mode: 2), 71)
    }

    func testScaleTablesContainAllModes() {
        XCTAssertEqual(Vinegar303Scale.keyNames.count, 12)
        XCTAssertEqual(Vinegar303Scale.modeNames.count, 7)
        XCTAssertEqual(Vinegar303Scale.intervals.count, 7)
        XCTAssertEqual(Vinegar303Scale.intervals[0], [0, 2, 4, 5, 7, 9, 11])
        XCTAssertEqual(Vinegar303Scale.intervals[1], [0, 2, 3, 5, 7, 8, 10])
        XCTAssertEqual(Vinegar303Scale.intervals[6], [0, 1, 3, 5, 6, 8, 10])
    }

    func testScaleParametersAreDiscrete() {
        let catalog = Vinegar303ParameterCatalog.self
        let enable = catalog.spec(.scaleEnable)
        let key = catalog.spec(.scaleKey)
        let mode = catalog.spec(.scaleType)

        XCTAssertEqual(enable.id.rawValue, 18)
        XCTAssertEqual(enable.identifier, "scaleEnable")
        XCTAssertEqual(enable.name, "Scale Aware")
        XCTAssertEqual(enable.minimum, 0)
        XCTAssertEqual(enable.maximum, 1)
        XCTAssertEqual(enable.defaultValue, 0)
        XCTAssertEqual(enable.step, 1)
        XCTAssertEqual(enable.valueStrings, ["Off", "On"])
        XCTAssertTrue(enable.flags.contains(.flag_ValuesHaveStrings))
        XCTAssertEqual(enable.format(0), "OFF")
        XCTAssertEqual(enable.format(1), "ON")

        XCTAssertEqual(key.id.rawValue, 19)
        XCTAssertEqual(key.identifier, "scaleKey")
        XCTAssertEqual(key.name, "Scale Key")
        XCTAssertEqual(key.minimum, 0)
        XCTAssertEqual(key.maximum, 11)
        XCTAssertEqual(key.defaultValue, 0)
        XCTAssertEqual(key.step, 1)
        XCTAssertEqual(key.valueStrings?.count, 12)
        XCTAssertEqual(key.format(4), "E")
        XCTAssertTrue(key.flags.contains(.flag_ValuesHaveStrings))

        XCTAssertEqual(mode.id.rawValue, 20)
        XCTAssertEqual(mode.identifier, "scaleType")
        XCTAssertEqual(mode.name, "Scale Type")
        XCTAssertEqual(mode.minimum, 0)
        XCTAssertEqual(mode.maximum, 6)
        XCTAssertEqual(mode.defaultValue, 0)
        XCTAssertEqual(mode.step, 1)
        XCTAssertEqual(mode.valueStrings?.count, 7)
        XCTAssertEqual(mode.format(1), "NATURAL MINOR")
        XCTAssertTrue(mode.flags.contains(.flag_ValuesHaveStrings))

        let tree = Vinegar303ParameterTreeFactory.makeTree()
        for spec in [enable, key, mode] {
            guard let parameter = tree.parameter(withAddress: spec.id.rawValue) else {
                return XCTFail("Missing scale parameter \(spec.identifier)")
            }
            XCTAssertEqual(parameter.minValue, spec.minimum)
            XCTAssertEqual(parameter.maxValue, spec.maximum)
            XCTAssertEqual(parameter.unit, .indexed)
            XCTAssertTrue(parameter.flags.contains(.flag_ValuesHaveStrings))
            XCTAssertEqual(parameter.valueStrings, spec.valueStrings)
        }
    }

    func testScaleAwareBypassesTransposeAndQuantizesAtTrigger() {
        let scaleOn = estimateFrequency(renderScaleNote(scaleEnabled: true, note: 41, transpose: 12))
        let expected = estimateFrequency(renderScaleNote(scaleEnabled: false, note: 42, transpose: 0))
        let transposedChromatic = estimateFrequency(renderScaleNote(scaleEnabled: false, note: 41, transpose: 12))

        XCTAssertGreaterThan(scaleOn, 50)
        XCTAssertEqual(scaleOn, expected, accuracy: expected * 0.08)
        XCTAssertGreaterThan(transposedChromatic, scaleOn * 1.5)
    }

    func testScaleParametersRoundTripThroughFullState() throws {
        let unit = try Vinegar303AudioUnit(componentDescription: Vinegar303AudioUnit.componentDescription)
        let tree = unit.editorParameterTree
        guard let enable = tree.parameter(withAddress: Vinegar303Parameter.scaleEnable.rawValue),
              let key = tree.parameter(withAddress: Vinegar303Parameter.scaleKey.rawValue),
              let mode = tree.parameter(withAddress: Vinegar303Parameter.scaleType.rawValue) else {
            return XCTFail("Missing scale parameters")
        }

        enable.value = 1
        key.value = 4
        mode.value = 2
        let state = unit.fullState

        enable.value = 0
        key.value = 0
        mode.value = 0
        unit.fullState = state

        XCTAssertEqual(enable.value, 1)
        XCTAssertEqual(key.value, 4)
        XCTAssertEqual(mode.value, 2)
    }

    func testHalfSpeedRoundTripsThroughFullState() throws {
        let unit = try Vinegar303AudioUnit(componentDescription: Vinegar303AudioUnit.componentDescription)
        guard let halfSpeed = unit.editorParameterTree.parameter(
            withAddress: Vinegar303Parameter.halfSpeed.rawValue
        ) else {
            return XCTFail("Missing half-speed parameter")
        }

        halfSpeed.value = 1
        let state = unit.fullState
        halfSpeed.value = 0
        unit.fullState = state

        XCTAssertEqual(halfSpeed.value, 1)
    }

    func testPitchTransposeParameterIsDiscrete() {
        let spec = Vinegar303ParameterCatalog.spec(.pitchTranspose)
        XCTAssertEqual(spec.id.rawValue, 17)
        XCTAssertEqual(spec.identifier, "pitchTranspose")
        XCTAssertEqual(spec.name, "Pitch Transpose")
        XCTAssertEqual(spec.minimum, -12)
        XCTAssertEqual(spec.maximum, 12)
        XCTAssertEqual(spec.defaultValue, 0)
        XCTAssertEqual(spec.step, 1)
        XCTAssertTrue(spec.isBipolar)
        XCTAssertEqual(spec.unit, .indexed)
        XCTAssertTrue(spec.flags.contains(.flag_ValuesHaveStrings))
        XCTAssertFalse(spec.flags.contains(.flag_IsHighResolution))
        XCTAssertEqual(spec.valueStrings?.count, 25)
        XCTAssertEqual(spec.format(-12), "-12 st")
        XCTAssertEqual(spec.format(0), "0 st")
        XCTAssertEqual(spec.format(12), "+12 st")
        XCTAssertEqual(spec.valueStrings?.first, "-12 st")
        XCTAssertEqual(spec.valueStrings?[12], "0 st")
        XCTAssertEqual(spec.valueStrings?.last, "+12 st")
        XCTAssertEqual(spec.snapped(-9.5), -10)
        XCTAssertEqual(spec.snapped(-9.49), -9)
        XCTAssertEqual(spec.snapped(13), 12)
        XCTAssertEqual(spec.value(fromNormalized: 0.5), 0)
        XCTAssertEqual(spec.normalized(-12), 0, accuracy: 0.0001)
        XCTAssertEqual(spec.normalized(12), 1, accuracy: 0.0001)

        let tree = Vinegar303ParameterTreeFactory.makeTree()
        guard let parameter = tree.parameter(withAddress: Vinegar303Parameter.pitchTranspose.rawValue) else {
            return XCTFail("Missing Pitch Transpose parameter")
        }
        XCTAssertEqual(parameter.minValue, -12)
        XCTAssertEqual(parameter.maxValue, 12)
        XCTAssertEqual(parameter.unit, .indexed)
        XCTAssertTrue(parameter.flags.contains(.flag_ValuesHaveStrings))
        XCTAssertEqual(parameter.valueStrings?.count, 25)
    }

    func testPitchTransposeModelSnapsAndFormats() {
        let model = ParameterModel(tree: Vinegar303ParameterTreeFactory.makeTree())
        let spec = Vinegar303ParameterCatalog.spec(.pitchTranspose)

        model.setValue(-9.5, for: .pitchTranspose)
        XCTAssertEqual(model.value(.pitchTranspose), -10)
        XCTAssertEqual(model.normalized(.pitchTranspose), spec.normalized(-10), accuracy: 0.0001)
        XCTAssertEqual(model.displayValue(.pitchTranspose), "-10 st")

        model.setNormalized(0.5, for: .pitchTranspose)
        XCTAssertEqual(model.value(.pitchTranspose), 0)
        XCTAssertEqual(model.displayValue(.pitchTranspose), "0 st")

        model.setNormalized(1, for: .pitchTranspose)
        XCTAssertEqual(model.value(.pitchTranspose), 12)
        XCTAssertEqual(model.displayValue(.pitchTranspose), "+12 st")

        model.setNormalized(0, for: .pitchTranspose)
        XCTAssertEqual(model.value(.pitchTranspose), -12)
        XCTAssertEqual(model.displayValue(.pitchTranspose), "-12 st")
    }

    func testParameterReadoutsUseConsistentUnitSpacing() {
        let catalog = Vinegar303ParameterCatalog.self
        XCTAssertEqual(catalog.spec(.cutoff).format(520), "520 Hz")
        XCTAssertEqual(catalog.spec(.resonance).format(20), "20 %")
        XCTAssertEqual(catalog.spec(.envmod).format(20), "20 %")
        XCTAssertEqual(catalog.spec(.accent).format(20), "20 %")
        XCTAssertEqual(catalog.spec(.distortion).format(20), "20 %")
        XCTAssertEqual(catalog.spec(.decay).format(300), "300 ms")
        XCTAssertEqual(catalog.spec(.pitchTranspose).format(0), "0 st")
        XCTAssertEqual(catalog.spec(.halfSpeed).format(0), "1:1")
        XCTAssertEqual(catalog.spec(.halfSpeed).format(1), "1:2")
    }

    func testPitchTransposeOffsetsOscillatorFrequencyBySemitones() {
        let base = estimateFrequency(renderTransposedNote(0))
        let octaveUp = estimateFrequency(renderTransposedNote(12))
        let octaveDown = estimateFrequency(renderTransposedNote(-12))

        XCTAssertGreaterThan(base, 50)
        XCTAssertEqual(octaveUp / base, 2, accuracy: 0.08)
        XCTAssertEqual(octaveDown / base, 0.5, accuracy: 0.05)
    }

    private func renderTransposedNote(_ semitones: AUValue) -> [Float] {
        let engine = Vinegar303Engine()
        engine.prepare(sampleRate: sampleRate)
        engine.setParameter(.sync, 0)
        engine.setParameter(.run, 0)
        engine.setParameter(.midiMode, 1)
        engine.setParameter(.cutoff, 2_000)
        engine.setParameter(.resonance, 0)
        engine.setParameter(.envmod, 0)
        engine.setParameter(.decay, 40)
        engine.setParameter(.waveform, 1)
        engine.setParameter(.volume, 0)
        engine.setParameter(.distortion, 0)
        engine.setParameter(.drive, 0)
        engine.setParameter(.pitchTranspose, semitones)
        engine.noteOn(midi: 45, velocity: 100)
        return render(engine, frames: 24_000, hostPlaying: nil)
    }

    private func renderScaleNote(scaleEnabled: Bool, note: Int, transpose: AUValue) -> [Float] {
        let engine = Vinegar303Engine()
        engine.prepare(sampleRate: sampleRate)
        engine.setParameter(.sync, 0)
        engine.setParameter(.run, 0)
        engine.setParameter(.midiMode, 1)
        engine.setParameter(.cutoff, 2_000)
        engine.setParameter(.resonance, 0)
        engine.setParameter(.envmod, 0)
        engine.setParameter(.decay, 40)
        engine.setParameter(.waveform, 1)
        engine.setParameter(.volume, 0)
        engine.setParameter(.distortion, 0)
        engine.setParameter(.drive, 0)
        engine.setParameter(.pitchTranspose, transpose)
        engine.setParameter(.scaleEnable, scaleEnabled ? 1 : 0)
        engine.setParameter(.scaleKey, 4)
        engine.setParameter(.scaleType, 1)
        engine.noteOn(midi: note, velocity: 100)
        return render(engine, frames: 48_000, hostPlaying: nil)
    }

    private func estimateFrequency(_ samples: [Float], skipping: Int = 4_800) -> Double {
        let start = skipping * 2
        guard samples.count > start + 2 else { return 0 }
        var crossings = 0
        var previous = samples[start]
        for index in stride(from: start + 2, to: samples.count, by: 2) {
            let current = samples[index]
            if previous < 0 && current >= 0 {
                crossings += 1
            }
            previous = current
        }
        let seconds = Double(samples.count / 2 - skipping) / sampleRate
        return Double(crossings) / max(seconds, 0.0001)
    }

    func testParameterDefaultsAreInRange() {
        for spec in Vinegar303ParameterCatalog.all {
            XCTAssertLessThanOrEqual(spec.minimum, spec.defaultValue, spec.identifier)
            XCTAssertLessThanOrEqual(spec.defaultValue, spec.maximum, spec.identifier)
            XCTAssertEqual(spec.normalized(spec.defaultValue), spec.normalized(spec.value(fromNormalized: spec.normalized(spec.defaultValue))), accuracy: 0.0001)
        }
    }

    func testCutoffRangeIsCalibratedAndClampsDirectEngineWrites() {
        let spec = Vinegar303ParameterCatalog.spec(.cutoff)
        XCTAssertEqual(spec.minimum, 200)
        XCTAssertEqual(spec.maximum, 2_000)

        let engine = Vinegar303Engine()
        engine.setParameter(.cutoff, 12_000)
        XCTAssertEqual(engine.parameter(.cutoff), 2_000, accuracy: 0.1)

        engine.setParameter(.cutoff, 30)
        XCTAssertEqual(engine.parameter(.cutoff), 200, accuracy: 0.1)

        let tree = Vinegar303ParameterTreeFactory.makeTree()
        let cutoff = tree.parameter(withAddress: Vinegar303Parameter.cutoff.rawValue)
        XCTAssertEqual(cutoff?.minValue, 200)
        XCTAssertEqual(cutoff?.maxValue, 2_000)
    }
}
