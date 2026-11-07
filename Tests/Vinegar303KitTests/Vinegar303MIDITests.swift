import XCTest
@testable import Vinegar303Kit

final class Vinegar303MIDITests: XCTestCase {
    private func makeStore(includeLaunchkey: Bool = true) -> Vinegar303MIDIProfileStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vinegar303MIDITest-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let store = Vinegar303MIDIProfileStore(directoryURL: directory)
        if includeLaunchkey {
            try? store.save(.launchkeyMini)
        }
        return store
    }

    func testParserHandlesNotesCCPitchBendAndRunningStatus() {
        let messages = Vinegar303MIDIMessage.parse([
            0x90, 36, 100,
            36, 0,
            0xB1, 21, 64,
            0xE0, 0, 64,
            0x80, 36, 0,
        ])

        XCTAssertEqual(messages, [
            .noteOn(channel: 1, note: 36, velocity: 100),
            .noteOff(channel: 1, note: 36),
            .controlChange(channel: 2, controller: 21, value: 64),
            .pitchBend(channel: 1, value: 8_192),
            .noteOff(channel: 1, note: 36),
        ])
    }

    func testLaunchkeyDefaultProfileMatchesSpecifiedCCMap() {
        let profile = Vinegar303MIDIProfile.launchkeyMini
        XCTAssertEqual(profile.channel, 1)

        let expected: [(Int, String)] = [
            (21, "cutoff"),
            (22, "resonance"),
            (23, "envmod"),
            (24, "decay"),
            (25, "accent"),
            (26, "tuning"),
            (27, "volume"),
            (28, "tempo"),
        ]
        for (controller, parameter) in expected {
            let binding = profile.bindings.first {
                $0.source == .controlChange && $0.number == controller
            }
            XCTAssertEqual(binding?.target, .parameter)
            XCTAssertEqual(binding?.parameter, parameter)
        }

        XCTAssertEqual(
            profile.bindings.first { $0.source == .pitchBend }?.parameter,
            "tuning"
        )
        XCTAssertEqual(
            profile.bindings.first { $0.source == .noteOn && $0.number == 36 }?.target,
            .pattern
        )
    }

    func testCCParameterMappingUsesNormalizedRangeAndChannelFilter() {
        let controller = Vinegar303MIDIController(
            store: makeStore(),
            profileName: Vinegar303MIDIProfile.launchkeyMiniName
        )
        var actions: [Vinegar303MIDIAction] = []
        controller.onAction = { actions.append($0) }

        controller.receive(.controlChange(channel: 1, controller: 21, value: 127))
        controller.receive(.controlChange(channel: 2, controller: 21, value: 0))
        controller.receive(.controlChange(channel: 1, controller: 22, value: 64))

        XCTAssertEqual(actions.count, 2)
        guard case .parameter(let cutoff, let cutoffValue) = actions[0] else {
            return XCTFail("Expected cutoff mapping")
        }
        XCTAssertEqual(cutoff, .cutoff)
        XCTAssertEqual(cutoffValue, 2_000, accuracy: 0.1)

        guard case .parameter(let resonance, let resonanceValue) = actions[1] else {
            return XCTFail("Expected resonance mapping")
        }
        XCTAssertEqual(resonance, .resonance)
        XCTAssertEqual(resonanceValue, 50.3937, accuracy: 0.01)
    }

    func testLearnCapturesPadNotesForPatternsAndGates() {
        let controller = Vinegar303MIDIController(
            store: makeStore(),
            profileName: Vinegar303MIDIProfile.launchkeyMiniName
        )
        var actions: [Vinegar303MIDIAction] = []
        controller.onAction = { actions.append($0) }

        controller.setLearnBadgesVisible(true)
        controller.armLearn(.pattern(4))
        controller.receive(.noteOn(channel: 1, note: 96, velocity: 100))
        XCTAssertNil(controller.learnTarget)
        XCTAssertEqual(
            controller.profile.bindings.first {
                $0.source == .noteOn && $0.number == 96
            }?.index,
            4
        )

        // The learned pad assignment replaces the hard-coded pattern pad.
        controller.receive(.noteOn(channel: 1, note: 96, velocity: 100))
        XCTAssertEqual(actions, [.pattern(4)])

        actions.removeAll()
        controller.armLearn(.stepGate(2))
        controller.receive(.noteOn(channel: 1, note: 97, velocity: 100))
        XCTAssertNil(controller.learnTarget)
        controller.receive(.noteOn(channel: 1, note: 97, velocity: 100))
        XCTAssertEqual(actions, [.stepGate(2)])
    }

    func testLearnCapturesSlideTarget() {
        let controller = Vinegar303MIDIController(
            store: makeStore(),
            profileName: Vinegar303MIDIProfile.launchkeyMiniName
        )
        var actions: [Vinegar303MIDIAction] = []
        controller.onAction = { actions.append($0) }

        controller.setLearnBadgesVisible(true)
        controller.armLearn(.stepSlide(5))
        controller.receive(.controlChange(channel: 1, controller: 29, value: 127))

        XCTAssertNil(controller.learnTarget)
        XCTAssertEqual(
            controller.profile.bindings.first {
                $0.source == .controlChange && $0.number == 29
            }?.target,
            .stepSlide
        )

        controller.receive(.controlChange(channel: 1, controller: 29, value: 0))
        controller.receive(.controlChange(channel: 1, controller: 29, value: 127))
        XCTAssertEqual(actions, [.stepSlide(5)])
    }

    func testLearnCapturesNoteSelectorAndUsesFullNoteRange() {
        let controller = Vinegar303MIDIController(
            store: makeStore(),
            profileName: Vinegar303MIDIProfile.launchkeyMiniName
        )
        var actions: [Vinegar303MIDIAction] = []
        controller.onAction = { actions.append($0) }

        controller.setLearnBadgesVisible(true)
        controller.armLearn(.stepNote(3))
        controller.receive(.controlChange(channel: 1, controller: 29, value: 127))
        XCTAssertNil(controller.learnTarget)

        controller.receive(.controlChange(channel: 1, controller: 29, value: 0))
        controller.receive(.controlChange(channel: 1, controller: 29, value: 127))
        XCTAssertEqual(actions, [
            .stepNote(3, Vinegar303PatternLibrary.lowestNote),
            .stepNote(3, Vinegar303PatternLibrary.highestNote),
        ])
    }

    func testLearnCapturesEditModeShiftAndPatternLengthActions() {
        let controller = Vinegar303MIDIController(
            store: makeStore(),
            profileName: Vinegar303MIDIProfile.launchkeyMiniName
        )
        var actions: [Vinegar303MIDIAction] = []
        controller.onAction = { actions.append($0) }

        controller.setLearnBadgesVisible(true)
        controller.armLearn(.editMode)
        controller.receive(.controlChange(channel: 16, controller: 117, value: 127))
        XCTAssertNil(controller.learnTarget)
        XCTAssertFalse(controller.launchkeyEditModeEnabled)

        controller.receive(.controlChange(channel: 16, controller: 117, value: 0))
        controller.receive(.controlChange(channel: 16, controller: 117, value: 127))
        XCTAssertTrue(controller.launchkeyEditModeEnabled)
        controller.receive(.controlChange(channel: 16, controller: 117, value: 0))

        controller.armLearn(.shift)
        controller.receive(.controlChange(channel: 1, controller: 29, value: 127))
        XCTAssertNil(controller.learnTarget)
        XCTAssertFalse(controller.launchkeyShiftHeld)
        controller.receive(.controlChange(channel: 1, controller: 29, value: 0))
        controller.receive(.controlChange(channel: 1, controller: 29, value: 127))
        XCTAssertTrue(controller.launchkeyShiftHeld)
        controller.receive(.controlChange(channel: 1, controller: 29, value: 0))
        XCTAssertFalse(controller.launchkeyShiftHeld)

        controller.armLearn(.patternLengthIncrease)
        controller.receive(.controlChange(channel: 1, controller: 30, value: 127))
        XCTAssertNil(controller.learnTarget)
        controller.receive(.controlChange(channel: 1, controller: 30, value: 127))
        controller.receive(.controlChange(channel: 1, controller: 30, value: 127))
        XCTAssertEqual(actions, [.adjustPatternLength(1)])
        controller.receive(.controlChange(channel: 1, controller: 30, value: 0))
        controller.receive(.controlChange(channel: 1, controller: 30, value: 127))
        XCTAssertEqual(actions, [
            .adjustPatternLength(1),
            .adjustPatternLength(1),
        ])
    }

    func testLearnCapturesNextCCAndPersistsProfile() {
        let store = makeStore()
        let controller = Vinegar303MIDIController(
            store: store,
            profileName: Vinegar303MIDIProfile.launchkeyMiniName
        )

        controller.setLearnBadgesVisible(true)
        XCTAssertTrue(controller.learnBadgesVisible)
        controller.armLearn(.cutoff)
        XCTAssertEqual(controller.learnTarget, .parameter(.cutoff))
        controller.receive(.controlChange(channel: 1, controller: 22, value: 10))

        XCTAssertNil(controller.learnTarget)
        let learned = controller.profile.bindings.first {
            $0.source == .controlChange && $0.number == 22
        }
        XCTAssertEqual(learned?.parameter, "cutoff")
        XCTAssertFalse(
            controller.profile.bindings.contains {
                $0.target == .parameter && $0.parameter == "resonance"
            }
        )

        let reloaded = Vinegar303MIDIController(
            store: store,
            profileName: Vinegar303MIDIProfile.launchkeyMiniName
        )
        XCTAssertEqual(
            reloaded.profile.bindings.first {
                $0.source == .controlChange && $0.number == 22
            }?.parameter,
            "cutoff"
        )
    }

    func testNoteBindingsRoutePatternsStepGatesAndAccents() {
        let controller = Vinegar303MIDIController(
            store: makeStore(),
            profileName: Vinegar303MIDIProfile.launchkeyMiniName
        )
        var actions: [Vinegar303MIDIAction] = []
        controller.onAction = { actions.append($0) }

        controller.receive(.noteOn(channel: 1, note: 36, velocity: 100))
        controller.receive(.noteOn(channel: 1, note: 52, velocity: 100))
        controller.receive(.noteOn(channel: 1, note: 68, velocity: 100))

        XCTAssertEqual(actions, [
            .pattern(0),
            .stepGate(0),
            .stepAccent(0),
        ])
    }

    func testTransportFeedbackFollowsLearnedPadForStepNote() {
        let learnedPad = Vinegar303MIDIBinding(
            source: .noteOn,
            number: 96,
            target: .stepNote,
            index: 3
        )

        let stepFourPads = Vinegar303LaunchkeyPadMap.transportGateIndices(
            forStep: 3,
            bindings: [learnedPad]
        )
        XCTAssertEqual(stepFourPads, [0])
        XCTAssertEqual(
            stepFourPads.compactMap {
                Vinegar303LaunchkeyPadMap.ledMessage(forGate: $0, color: .red)
            },
            [[0x90, 96, 5]]
        )

        // PAD 1 no longer represents step 01 after it is assigned to step 04.
        XCTAssertEqual(
            Vinegar303LaunchkeyPadMap.transportGateIndices(
                forStep: 0,
                bindings: [learnedPad]
            ),
            []
        )
    }

    func testTransportFeedbackFollowsBottomRowAndFallsBackWhenUnmapped() {
        let learnedPad = Vinegar303MIDIBinding(
            source: .noteOn,
            number: 112,
            target: .stepNote,
            index: 3
        )
        XCTAssertEqual(
            Vinegar303LaunchkeyPadMap.transportGateIndices(
                forStep: 3,
                bindings: [learnedPad]
            ),
            [8]
        )
        XCTAssertEqual(
            Vinegar303LaunchkeyPadMap.transportGateIndices(
                forStep: 5,
                bindings: []
            ),
            [5]
        )
    }

    func testLaunchkeyPadMapUsesSessionRows() {
        XCTAssertEqual(Vinegar303LaunchkeyPadMap.topNotes, Array(96...103))
        XCTAssertEqual(Vinegar303LaunchkeyPadMap.bottomNotes, Array(112...119))
        XCTAssertEqual(Vinegar303LaunchkeyPadMap.gateIndex(for: 96), 0)
        XCTAssertEqual(Vinegar303LaunchkeyPadMap.gateIndex(for: 103), 7)
        XCTAssertEqual(Vinegar303LaunchkeyPadMap.gateIndex(for: 112), 8)
        XCTAssertEqual(Vinegar303LaunchkeyPadMap.gateIndex(for: 119), 15)
        XCTAssertNil(Vinegar303LaunchkeyPadMap.gateIndex(for: 104))
        XCTAssertNil(Vinegar303LaunchkeyPadMap.gateIndex(for: 111))
        XCTAssertEqual(Vinegar303LaunchkeyPadMap.note(forGate: 0), 96)
        XCTAssertEqual(Vinegar303LaunchkeyPadMap.note(forGate: 8), 112)
        XCTAssertEqual(
            Vinegar303LaunchkeyPadMap.ledMessage(forGate: 0, color: .red),
            [0x90, 96, 5]
        )
        XCTAssertEqual(
            Vinegar303LaunchkeyPadMap.ledMessage(forGate: 8, color: .green),
            [0x90, 112, 19]
        )
        XCTAssertEqual(
            Vinegar303LaunchkeyPadMap.ledMessage(forGate: 15, color: .off),
            [0x90, 119, 0]
        )
    }

    func testLaunchkeyDAWKnobsUseProfileBindingsOnChannelSixteen() {
        let controller = Vinegar303MIDIController(
            store: makeStore(),
            profileName: Vinegar303MIDIProfile.launchkeyMiniName
        )
        var actions: [Vinegar303MIDIAction] = []
        controller.onAction = { actions.append($0) }

        controller.receive(.controlChange(channel: 16, controller: 21, value: 127))
        controller.receive(.controlChange(channel: 16, controller: 24, value: 64))
        controller.receive(.controlChange(channel: 16, controller: 102, value: 127))

        XCTAssertEqual(actions.count, 2)
        guard case .parameter(let cutoff, let cutoffValue) = actions[0] else {
            return XCTFail("Expected cutoff mapping from a DAW knob")
        }
        XCTAssertEqual(cutoff, .cutoff)
        XCTAssertEqual(cutoffValue, 2_000, accuracy: 0.1)
        guard case .parameter(let decay, let decayValue) = actions[1] else {
            return XCTFail("Expected decay mapping from a DAW knob")
        }
        XCTAssertEqual(decay, .decay)
        XCTAssertGreaterThan(decayValue, 0)
    }

    func testLaunchkeyNoteKnobPickupCoversFullRangeAndSwitchesRows() {
        let controller = Vinegar303MIDIController(
            store: makeStore(),
            profileName: Vinegar303MIDIProfile.launchkeyMiniName
        )
        controller.noteForStep = { index in
            index == 8 ? 40 : 33
        }
        var actions: [Vinegar303MIDIAction] = []
        controller.onAction = { actions.append($0) }

        controller.receive(.controlChange(channel: 16, controller: 117, value: 127))
        XCTAssertTrue(        controller.launchkeyEditModeEnabled)
        XCTAssertEqual(controller.launchkeyNoteKnobRow, "TOP")
        controller.receive(.controlChange(channel: 16, controller: 117, value: 0))
        XCTAssertTrue(        controller.launchkeyEditModeEnabled)

        // The knob starts away from the current note and must pick it up
        // before it can change anything.
        controller.receive(.controlChange(channel: 16, controller: 21, value: 0))
        XCTAssertTrue(actions.isEmpty)
        controller.receive(.controlChange(channel: 16, controller: 21, value: 32))
        XCTAssertEqual(actions, [.stepNote(0, 33)])

        // Once picked up, the complete pot travel spans C1 through C4.
        controller.receive(.controlChange(channel: 16, controller: 21, value: 0))
        XCTAssertEqual(actions.last, .stepNote(0, 24))
        controller.receive(.controlChange(channel: 16, controller: 21, value: 127))
        XCTAssertEqual(actions.last, .stepNote(0, 60))

        controller.receive(.controlChange(channel: 1, controller: 108, value: 127))
        XCTAssertTrue(controller.launchkeyShiftHeld)
        XCTAssertEqual(controller.launchkeyNoteKnobRow, "BOTTOM")

        // The bottom row starts at note 40. Pickup crosses that note, then
        // the full range remains available.
        controller.receive(.controlChange(channel: 16, controller: 21, value: 127))
        XCTAssertEqual(actions.last, .stepNote(0, 60))
        controller.receive(.controlChange(channel: 16, controller: 21, value: 57))
        XCTAssertEqual(actions.last, .stepNote(8, 40))
        controller.receive(.controlChange(channel: 16, controller: 21, value: 127))
        XCTAssertEqual(actions.last, .stepNote(8, 60))

        controller.receive(.controlChange(channel: 1, controller: 108, value: 0))
        XCTAssertFalse(controller.launchkeyShiftHeld)
        XCTAssertEqual(controller.launchkeyNoteKnobRow, "TOP")
        controller.receive(.controlChange(channel: 16, controller: 21, value: 31))
        XCTAssertEqual(actions.last, .stepNote(0, 33))

        controller.receive(.controlChange(channel: 16, controller: 117, value: 127))
        XCTAssertFalse(        controller.launchkeyEditModeEnabled)
    }

    func testLaunchkeyShiftTrackButtonsAdjustPatternLength() {
        let controller = Vinegar303MIDIController(
            store: makeStore(),
            profileName: Vinegar303MIDIProfile.launchkeyMiniName
        )
        var actions: [Vinegar303MIDIAction] = []
        controller.onAction = { actions.append($0) }

        XCTAssertEqual(Vinegar303LaunchkeyPadMap.trackLeftController, 103)
        XCTAssertEqual(Vinegar303LaunchkeyPadMap.trackRightController, 102)

        // Track buttons only adjust the length while SHIFT is held.
        controller.receive(.controlChange(channel: 16, controller: 103, value: 127))
        controller.receive(.controlChange(channel: 16, controller: 102, value: 127))
        XCTAssertTrue(actions.isEmpty)

        controller.receive(.controlChange(channel: 1, controller: 108, value: 127))
        controller.receive(.controlChange(channel: 16, controller: 103, value: 127))
        controller.receive(.controlChange(channel: 16, controller: 102, value: 127))
        XCTAssertEqual(actions, [.adjustPatternLength(-1), .adjustPatternLength(1)])

        // Button releases must not adjust the length a second time.
        controller.receive(.controlChange(channel: 16, controller: 103, value: 0))
        controller.receive(.controlChange(channel: 16, controller: 102, value: 0))
        XCTAssertEqual(actions, [.adjustPatternLength(-1), .adjustPatternLength(1)])

        controller.receive(.controlChange(channel: 1, controller: 108, value: 0))
        controller.receive(.controlChange(channel: 16, controller: 102, value: 127))
        XCTAssertEqual(actions, [.adjustPatternLength(-1), .adjustPatternLength(1)])
    }

    func testLaunchkeyPadsSelectPatternsUntilEditMode() {
        let controller = Vinegar303MIDIController(
            store: makeStore(),
            profileName: Vinegar303MIDIProfile.launchkeyMiniName
        )
        var actions: [Vinegar303MIDIAction] = []
        controller.onAction = { actions.append($0) }

        XCTAssertFalse(controller.launchkeyEditModeEnabled)
        controller.receive(.noteOn(channel: 1, note: 96, velocity: 100))
        controller.receive(.noteOn(channel: 1, note: 103, velocity: 100))
        controller.receive(.noteOn(channel: 1, note: 112, velocity: 100))
        controller.receive(.noteOn(channel: 1, note: 119, velocity: 100))
        XCTAssertEqual(actions, [
            .pattern(0),
            .pattern(7),
            .pattern(8),
            .pattern(15),
        ])

        controller.receive(.controlChange(channel: 16, controller: 117, value: 127))
        XCTAssertTrue(controller.launchkeyEditModeEnabled)
        actions.removeAll()
        controller.receive(.noteOn(channel: 1, note: 96, velocity: 100))
        controller.receive(.noteOn(channel: 1, note: 103, velocity: 100))
        controller.receive(.noteOn(channel: 1, note: 112, velocity: 100))
        controller.receive(.noteOn(channel: 1, note: 119, velocity: 100))
        XCTAssertEqual(actions, [
            .stepGate(0),
            .stepGate(7),
            .stepGate(8),
            .stepGate(15),
        ])

        // The sequencer chip and the hardware button share the same state.
        controller.setLaunchkeyEditMode(false)
        actions.removeAll()
        controller.receive(.noteOn(channel: 1, note: 96, velocity: 100))
        XCTAssertEqual(actions, [.pattern(0)])
    }

    func testLearnVisibilityCancelsPendingTarget() {
        let controller = Vinegar303MIDIController(
            store: makeStore(),
            profileName: Vinegar303MIDIProfile.launchkeyMiniName
        )

        controller.setLearnBadgesVisible(true)
        controller.armLearn(.cutoff)
        XCTAssertEqual(controller.learnTarget, .parameter(.cutoff))

        controller.setLearnBadgesVisible(false)
        XCTAssertFalse(controller.learnBadgesVisible)
        XCTAssertNil(controller.learnTarget)
    }

    func testArmedLearnTakesPriorityOverEditMode() {
        let controller = Vinegar303MIDIController(
            store: makeStore(),
            profileName: Vinegar303MIDIProfile.launchkeyMiniName
        )
        var actions: [Vinegar303MIDIAction] = []
        controller.onAction = { actions.append($0) }

        controller.setLearnBadgesVisible(true)
        controller.setLaunchkeyEditMode(true)
        controller.armLearn(.cutoff)
        controller.receive(.controlChange(channel: 16, controller: 21, value: 127))

        XCTAssertNil(controller.learnTarget)
        XCTAssertTrue(controller.launchkeyEditModeEnabled)
        XCTAssertTrue(actions.isEmpty)
        XCTAssertEqual(
            controller.profile.bindings.first {
                $0.source == .controlChange && $0.number == 21
            }?.parameter,
            "cutoff"
        )
    }

    func testDefaultProfileIsEmbeddedNone() {
        let store = makeStore(includeLaunchkey: false)
        let controller = Vinegar303MIDIController(store: store)

        XCTAssertEqual(controller.profile.name, Vinegar303MIDIProfile.noneName)
        XCTAssertTrue(controller.profile.bindings.isEmpty)
        XCTAssertEqual(controller.profileNames, [Vinegar303MIDIProfile.noneName])
        XCTAssertFalse(controller.deleteProfile(named: Vinegar303MIDIProfile.noneName))
    }

    func testNoneProfileSuppressesLaunchkeyPadsKnobsAndShortcuts() {
        let store = makeStore(includeLaunchkey: false)
        let controller = Vinegar303MIDIController(store: store)
        var actions: [Vinegar303MIDIAction] = []
        var forwarded: [Vinegar303MIDIMessage] = []
        controller.onAction = { actions.append($0) }
        controller.onUnmappedNote = { forwarded.append($0) }

        controller.setLaunchkeyEditMode(true)
        XCTAssertFalse(controller.launchkeyEditModeEnabled)

        controller.receive(.noteOn(channel: 1, note: 96, velocity: 100))
        controller.receive(.controlChange(channel: 16, controller: 21, value: 127))
        controller.receive(.controlChange(channel: 16, controller: 117, value: 127))
        controller.receive(.controlChange(channel: 1, controller: 108, value: 127))
        controller.receive(.controlChange(channel: 16, controller: 103, value: 127))

        XCTAssertTrue(actions.isEmpty)
        XCTAssertFalse(controller.launchkeyEditModeEnabled)
        XCTAssertFalse(controller.launchkeyShiftHeld)
        XCTAssertEqual(forwarded, [
            .noteOn(channel: 1, note: 96, velocity: 100),
        ])
    }

    func testLoadingNoneResetsLaunchkeyModeAndShift() {
        let controller = Vinegar303MIDIController(
            store: makeStore(),
            profileName: Vinegar303MIDIProfile.launchkeyMiniName
        )

        controller.setLaunchkeyEditMode(true)
        controller.receive(.controlChange(channel: 1, controller: 108, value: 127))
        XCTAssertTrue(controller.launchkeyEditModeEnabled)
        XCTAssertTrue(controller.launchkeyShiftHeld)

        controller.loadProfile(named: Vinegar303MIDIProfile.noneName)
        XCTAssertFalse(controller.launchkeyEditModeEnabled)
        XCTAssertFalse(controller.launchkeyShiftHeld)
    }

    func testLearningFromNoneCreatesAndPersistsAMappingProfile() {
        let store = makeStore(includeLaunchkey: false)
        let controller = Vinegar303MIDIController(store: store)

        controller.setLearnBadgesVisible(true)
        controller.armLearn(.cutoff)
        controller.receive(.controlChange(channel: 1, controller: 21, value: 127))

        XCTAssertNil(controller.learnTarget)
        XCTAssertNotEqual(controller.profile.name, Vinegar303MIDIProfile.noneName)
        XCTAssertEqual(controller.profile.bindings.count, 1)
        XCTAssertTrue(controller.profileNames.contains(Vinegar303MIDIProfile.noneName))
        XCTAssertEqual(
            store.loadProfiles().first { $0.name == controller.profile.name }?.bindings.count,
            1
        )
    }

    func testDeletingActiveProfileFallsBackToNone() {
        let store = makeStore()
        let controller = Vinegar303MIDIController(
            store: store,
            profileName: Vinegar303MIDIProfile.launchkeyMiniName
        )

        let saved = controller.saveProfile(named: "Custom Controller")
        XCTAssertEqual(controller.profile.name, "Custom Controller")
        XCTAssertEqual(controller.profileNames.count, 3)

        XCTAssertTrue(controller.deleteProfile(named: saved.name))
        XCTAssertEqual(controller.profile.name, Vinegar303MIDIProfile.noneName)
        XCTAssertEqual(controller.profile.channel, 1)
        XCTAssertTrue(controller.profile.bindings.isEmpty)
        XCTAssertNil(controller.learnTarget)
        XCTAssertFalse(controller.profileNames.contains("Custom Controller"))

        let reloaded = Vinegar303MIDIController(
            store: store,
            profileName: Vinegar303MIDIProfile.launchkeyMiniName
        )
        XCTAssertEqual(reloaded.profile.name, Vinegar303MIDIProfile.launchkeyMiniName)
    }

    func testBuiltInLaunchkeyProfileCannotBeDeleted() {
        let controller = Vinegar303MIDIController(
            store: makeStore(),
            profileName: Vinegar303MIDIProfile.launchkeyMiniName
        )

        XCTAssertFalse(
            controller.deleteProfile(named: Vinegar303MIDIProfile.launchkeyMiniName)
        )
        XCTAssertEqual(controller.profile.name, Vinegar303MIDIProfile.launchkeyMiniName)
        XCTAssertTrue(
            controller.profileNames.contains(Vinegar303MIDIProfile.launchkeyMiniName)
        )
    }

    func testProfileStoreRoundTripsJSONAndCreatesDefault() {
        let store = makeStore(includeLaunchkey: false)
        let defaults = store.loadProfiles()
        XCTAssertEqual(defaults.map(\.name), [Vinegar303MIDIProfile.noneName])
        XCTAssertTrue(defaults[0].bindings.isEmpty)

        // The embedded profile cannot be turned into an on-disk mapping.
        try? store.save(
            Vinegar303MIDIProfile(
                name: Vinegar303MIDIProfile.noneName,
                bindings: [
                    Vinegar303MIDIBinding(
                        source: .controlChange,
                        number: 7,
                        target: .parameter,
                        parameter: "volume"
                    ),
                ]
            )
        )
        XCTAssertTrue(
            store.loadProfiles()
                .first { $0.name == Vinegar303MIDIProfile.noneName }?
                .bindings.isEmpty == true
        )

        let custom = Vinegar303MIDIProfile(
            name: "Custom Controller",
            channel: 4,
            bindings: [
                Vinegar303MIDIBinding(
                    source: .controlChange,
                    number: 7,
                    target: .parameter,
                    parameter: "volume"
                ),
            ]
        )
        XCTAssertNoThrow(try store.save(custom))

        let loaded = store.loadProfiles()
        XCTAssertEqual(
            loaded.map(\.name),
            [Vinegar303MIDIProfile.noneName, "Custom Controller"]
        )
        XCTAssertTrue(loaded.contains(custom))

        let noneURL = store.directoryURL.appendingPathComponent("None.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: noneURL.path))
    }
}
