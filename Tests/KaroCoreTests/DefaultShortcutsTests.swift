import Carbon.HIToolbox
import Testing
@testable import KaroCore

struct DefaultShortcutsTests {
    @Test func everyActionHasAShortcut() {
        #expect(Set(DefaultShortcuts.all.keys) == Set(WindowAction.allCases))
    }

    @Test func shortcutsAreUnique() {
        let switcher = DefaultShortcuts.switcher(.option)
        let shortcuts = Array(DefaultShortcuts.all.values) + [switcher.forward, switcher.backward]
        #expect(Set(shortcuts).count == shortcuts.count)
    }

    @Test func optionSwitcherMatchesPreviousValues() {
        let switcher = DefaultShortcuts.switcher(.option)
        #expect(switcher.forward == KeyboardShortcut(keyCode: KeyCode.tab, modifiers: [.option]))
        #expect(switcher.backward == KeyboardShortcut(keyCode: KeyCode.tab, modifiers: [.option, .shift]))
        #expect(switcher.next == KeyboardShortcut(keyCode: KeyCode.rightArrow, modifiers: [.option]))
        #expect(switcher.previous == KeyboardShortcut(keyCode: KeyCode.leftArrow, modifiers: [.option]))
        #expect(switcher.choose == KeyboardShortcut(keyCode: KeyCode.returnKey, modifiers: [.option]))
        #expect(switcher.cancel == KeyboardShortcut(keyCode: KeyCode.escape, modifiers: [.option]))
        #expect(switcher.larger == KeyboardShortcut(keyCode: KeyCode.equal, modifiers: [.option]))
        #expect(switcher.smaller == KeyboardShortcut(keyCode: KeyCode.minus, modifiers: [.option]))
    }

    @Test func commandSwitcherUsesCommandModifiers() {
        let switcher = DefaultShortcuts.switcher(.command)
        #expect(switcher.forward == KeyboardShortcut(keyCode: KeyCode.tab, modifiers: [.command]))
        #expect(switcher.backward == KeyboardShortcut(keyCode: KeyCode.tab, modifiers: [.command, .shift]))
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
