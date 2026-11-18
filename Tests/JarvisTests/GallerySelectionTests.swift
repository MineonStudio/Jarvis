@testable import Jarvis
import SwiftUI
import XCTest

@MainActor
final class GallerySelectionTests: XCTestCase {
    func testFirstClickTogglesImmediatelyAndSecondClickOpensWithoutKeepingSelection() {
        var state = GallerySelection<String>()
        let selection = Binding(get: { state }, set: { state = $0 })
        var opened: [String] = []

        GallerySelection.handleClick(1, on: "first", selection: selection) { opened.append("first") }
        XCTAssertEqual(state.selectedID, "first")
        XCTAssertTrue(opened.isEmpty)

        GallerySelection.handleClick(2, on: "first", selection: selection) { opened.append("first") }
        XCTAssertNil(state.selectedID)
        XCTAssertEqual(opened, ["first"])
    }

    func testOpeningAnotherCardRestoresThePreviouslySelectedCard() {
        var state = GallerySelection<String>()
        state.toggle("first")
        let selection = Binding(get: { state }, set: { state = $0 })

        GallerySelection.handleClick(1, on: "second", selection: selection) {}
        XCTAssertEqual(state.selectedID, "second")

        GallerySelection.handleClick(2, on: "second", selection: selection) {
            XCTAssertEqual(state.selectedID, "first")
        }
    }

    func testRemovedSelectionIsNotRestored() {
        var state = GallerySelection<String>()
        state.toggle("first")
        let selection = Binding(get: { state }, set: { state = $0 })

        GallerySelection.handleClick(1, on: "second", selection: selection) {}
        state.retain { $0 == "second" }
        GallerySelection.handleClick(2, on: "second", selection: selection) {
            XCTAssertNil(state.selectedID)
        }
    }
}
