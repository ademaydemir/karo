import Carbon.HIToolbox
import Testing
@testable import KaroCore

struct DefaultShortcutsTests {
    @Test func everyActionHasAShortcut() {
        #expect(Set(DefaultShortcuts.all.keys) == Set(WindowAction.allCases))
    }

    @Test func shortcutsAreUnique() {
        let shortcuts = Array(DefaultShortcuts.all.values)
            + [DefaultShortcuts.switchWindowsForward, DefaultShortcuts.switchWindowsBackward]
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
            (KeyCode.tab, kVK_Tab), (KeyCode.escape, kVK_Escape),
            (KeyCode.equal, kVK_ANSI_Equal), (KeyCode.minus, kVK_ANSI_Minus),
            (KeyCode.h, kVK_ANSI_H), (KeyCode.m, kVK_ANSI_M), (KeyCode.q, kVK_ANSI_Q), (KeyCode.w, kVK_ANSI_W),
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
