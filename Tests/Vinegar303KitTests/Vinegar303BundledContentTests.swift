import XCTest
@testable import Vinegar303Kit

final class Vinegar303BundledContentTests: XCTestCase {
    func testInstallCopiesGoodiesOnceAndRespectsDeletion() throws {
        let fileManager = FileManager.default
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vinegar303BundledContentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let content = root.appendingPathComponent("Content", isDirectory: true)
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let presetSource = content
            .appendingPathComponent("Presets/Goodies", isDirectory: true)
            .appendingPathComponent("Lead.v303preset")
        let profileSource = content
            .appendingPathComponent("MIDI/Profiles", isDirectory: true)
            .appendingPathComponent("Controller.json")
        try fileManager.createDirectory(
            at: presetSource.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: profileSource.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("preset".utf8).write(to: presetSource)
        try Data("profile".utf8).write(to: profileSource)
        try Data("ignore".utf8).write(
            to: content.appendingPathComponent("Presets/README.md")
        )

        let first = Vinegar303BundledContent.install(from: content, to: support)
        XCTAssertEqual(
            first,
            Set([
                "Presets/Goodies/Lead.v303preset",
                "MIDI/Profiles/Controller.json",
            ])
        )

        let presetDestination = support
            .appendingPathComponent("Presets/Goodies/Lead.v303preset")
        let profileDestination = support
            .appendingPathComponent("MIDI/Profiles/Controller.json")
        XCTAssertEqual(try Data(contentsOf: presetDestination), Data("preset".utf8))
        XCTAssertEqual(try Data(contentsOf: profileDestination), Data("profile".utf8))
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: support.appendingPathComponent("Presets/README.md").path
            )
        )

        // Deleting a bundled goodie is permanent. Adding another goodie still
        // installs the new one on the next launch.
        try fileManager.removeItem(at: presetDestination)
        let secondPreset = content
            .appendingPathComponent("Presets/Goodies", isDirectory: true)
            .appendingPathComponent("Second.v303preset")
        try Data("second".utf8).write(to: secondPreset)

        let second = Vinegar303BundledContent.install(from: content, to: support)
        XCTAssertFalse(fileManager.fileExists(atPath: presetDestination.path))
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: support.appendingPathComponent("Presets/Goodies/Second.v303preset").path
            )
        )
        XCTAssertEqual(
            second,
            first.union(["Presets/Goodies/Second.v303preset"])
        )
    }

    func testInstallNeverOverwritesAnExistingUserFile() throws {
        let fileManager = FileManager.default
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vinegar303BundledContentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let content = root.appendingPathComponent("Content", isDirectory: true)
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let source = content
            .appendingPathComponent("MIDI/Profiles", isDirectory: true)
            .appendingPathComponent("Controller.json")
        let destination = support
            .appendingPathComponent("MIDI/Profiles", isDirectory: true)
            .appendingPathComponent("Controller.json")
        try fileManager.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("bundled".utf8).write(to: source)
        try Data("user edits".utf8).write(to: destination)

        let seeded = Vinegar303BundledContent.install(from: content, to: support)
        XCTAssertTrue(seeded.contains("MIDI/Profiles/Controller.json"))
        XCTAssertEqual(try Data(contentsOf: destination), Data("user edits".utf8))
    }
}
