import AppKit
import SwiftUI
import XCTest
@testable import Vinegar303Kit

final class Vinegar303AppearanceTests: XCTestCase {
    func testUnknownStoredValueFallsBackToSystem() {
        let mode = Vinegar303AppearanceMode(rawValue: "unknown") ?? .system
        XCTAssertEqual(mode, .system)
    }

    func testColorSchemeMapping() {
        XCTAssertNil(Vinegar303AppearanceMode.system.colorScheme)
        XCTAssertEqual(Vinegar303AppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(Vinegar303AppearanceMode.dark.colorScheme, .dark)
    }

    func testAppKitAppearanceMapping() {
        XCTAssertNil(Vinegar303AppearanceMode.system.nsAppearance)
        XCTAssertEqual(Vinegar303AppearanceMode.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(Vinegar303AppearanceMode.dark.nsAppearance?.name, .darkAqua)
    }

    func testModesExposeDistinctIcons() {
        let symbols = Set(Vinegar303AppearanceMode.allCases.map(\.symbol))
        XCTAssertEqual(symbols, ["circle.lefthalf.filled", "sun.max.fill", "moon.fill"])
    }

}
