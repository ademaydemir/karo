import Carbon.HIToolbox
import Testing
@testable import TesseraCore

struct DefaultShortcutsTests {
    @Test func everyActionExceptDisplayMovesHasAShortcut() {
        let expected = Set(WindowAction.allCases).subtracting([.nextDisplay, .previousDisplay])
        #expect(Set(DefaultShortcuts.all.keys) == expected)
    }

    @Test func shortcutsAreUnique() {
        let shortcuts = Array(DefaultShortcuts.all.values)
        #expect(Set(shortcuts).count == shortcuts.count)
    }

    @Test func matchesRectangleDefaults() {
        #expect(DefaultShortcuts.all[.leftHalf] == KeyboardShortcut(keyCode: KeyCode.leftArrow, modifiers: [.control, .option]))
        #expect(DefaultShortcuts.all[.maximize] == KeyboardShortcut(keyCode: KeyCode.returnKey, modifiers: [.control, .option]))
        #expect(DefaultShortcuts.all[.restore] == KeyboardShortcut(keyCode: KeyCode.delete, modifiers: [.control, .option]))
    }

    @Test func keyCodesMatchCarbon() {
        let pairs: [(UInt32, Int)] = [
            (KeyCode.leftArrow, kVK_LeftArrow), (KeyCode.rightArrow, kVK_RightArrow),
            (KeyCode.downArrow, kVK_DownArrow), (KeyCode.upArrow, kVK_UpArrow),
            (KeyCode.returnKey, kVK_Return), (KeyCode.delete, kVK_Delete),
            (KeyCode.c, kVK_ANSI_C), (KeyCode.d, kVK_ANSI_D), (KeyCode.e, kVK_ANSI_E),
            (KeyCode.f, kVK_ANSI_F), (KeyCode.g, kVK_ANSI_G), (KeyCode.i, kVK_ANSI_I),
            (KeyCode.j, kVK_ANSI_J), (KeyCode.k, kVK_ANSI_K), (KeyCode.t, kVK_ANSI_T),
            (KeyCode.u, kVK_ANSI_U),
        ]
        for (ours, carbon) in pairs {
            #expect(ours == UInt32(carbon))
        }
    }
}
