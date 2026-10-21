import Foundation
import Testing
@testable import TesseraCore

struct TesseraSettingsTests {
    private let custom = KeyboardShortcut(keyCode: KeyCode.d, modifiers: [.command, .option])

    @Test func usesDefaultsInitially() {
        #expect(TesseraSettings().effectiveShortcuts == DefaultShortcuts.all)
    }

    @Test func customShortcutOverridesDefault() {
        var settings = TesseraSettings()
        settings.setShortcut(custom, for: .leftHalf)
        #expect(settings.shortcut(for: .leftHalf) == custom)
        #expect(settings.shortcut(for: .rightHalf) == DefaultShortcuts.all[.rightHalf])
    }

    @Test func clearingDisablesShortcut() {
        var settings = TesseraSettings()
        settings.setShortcut(nil, for: .center)
        #expect(settings.shortcut(for: .center) == nil)
        #expect(settings.effectiveShortcuts[.center] == nil)
    }

    @Test func assigningDefaultAgainStoresNoOverride() {
        var settings = TesseraSettings()
        settings.setShortcut(custom, for: .leftHalf)
        settings.setShortcut(DefaultShortcuts.all[.leftHalf], for: .leftHalf)
        #expect(settings.customShortcuts.isEmpty)
        #expect(settings.disabledShortcuts.isEmpty)
    }

    @Test func resetRestoresDefaults() {
        var settings = TesseraSettings()
        settings.setShortcut(custom, for: .leftHalf)
        settings.setShortcut(nil, for: .center)
        settings.resetShortcuts()
        #expect(settings.effectiveShortcuts == DefaultShortcuts.all)
    }

    @Test func detectsConflictWithAnotherAction() {
        let settings = TesseraSettings()
        let rightHalf = DefaultShortcuts.all[.rightHalf]!
        #expect(settings.conflict(for: rightHalf, assigningTo: .leftHalf) == .action(.rightHalf))
        #expect(settings.conflict(for: rightHalf, assigningTo: .rightHalf) == nil)
    }

    @Test func detectsConflictWithWindowSwitcher() {
        let settings = TesseraSettings()
        #expect(settings.conflict(for: DefaultShortcuts.switchWindowsForward, assigningTo: .maximize) == .windowSwitcher)
    }

    @Test func disabledShortcutNoLongerConflicts() {
        var settings = TesseraSettings()
        settings.setShortcut(nil, for: .rightHalf)
        #expect(settings.conflict(for: DefaultShortcuts.all[.rightHalf]!, assigningTo: .leftHalf) == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        var settings = TesseraSettings()
        settings.gap = 8
        settings.isDragSnappingEnabled = false
        settings.showsWindowPreviews = true
        settings.setShortcut(custom, for: .leftHalf)
        settings.setShortcut(nil, for: .center)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(TesseraSettings.self, from: data) == settings)
    }

    @Test func encodesShortcutsKeyedByActionName() throws {
        var settings = TesseraSettings()
        settings.setShortcut(custom, for: .leftHalf)
        let json = try #require(String(data: JSONEncoder().encode(settings), encoding: .utf8))
        #expect(json.contains("\"leftHalf\":{"))
    }

    @Test func decodesOlderSettingsWithMissingFields() throws {
        let decoded = try JSONDecoder().decode(TesseraSettings.self, from: Data(#"{"gap": 12}"#.utf8))
        var expected = TesseraSettings()
        expected.gap = 12
        #expect(decoded == expected)
    }
}
