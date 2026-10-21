import Foundation
import Testing
@testable import TesseraCore

struct WindowActionTests {
    @Test func rawValuesAreStablePersistenceKeys() {
        #expect(WindowAction.leftHalf.rawValue == "leftHalf")
        #expect(WindowAction.topLeft.rawValue == "topLeft")
        #expect(WindowAction.rightTwoThirds.rawValue == "rightTwoThirds")
        #expect(WindowAction.previousDisplay.rawValue == "previousDisplay")
    }

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(WindowAction.allCases)
        let decoded = try JSONDecoder().decode([WindowAction].self, from: data)
        #expect(decoded == WindowAction.allCases)
    }
}
