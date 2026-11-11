import Testing
@testable import KaroCore

struct ModifierDragPolicyTests {
    private let combo: KeyboardShortcut.Modifiers = [.control, .option]

    private func relevant(isPress: Bool, held: KeyboardShortcut.Modifiers, configured: KeyboardShortcut.Modifiers? = [.control, .option], active: Bool = false) -> Bool {
        ModifierDragPolicy.isRelevant(isPress: isPress, held: held, configured: configured, isGestureActive: active)
    }

    @Test func pressWithExactComboIsRelevant() {
        #expect(relevant(isPress: true, held: combo))
    }

    @Test func pressWithoutTheComboIsIrrelevant() {
        #expect(!relevant(isPress: true, held: []))
        #expect(!relevant(isPress: true, held: [.control]))
        #expect(!relevant(isPress: true, held: [.command]))
        #expect(!relevant(isPress: true, held: [.control, .option, .command]))
    }

    @Test func featureOffIsIrrelevant() {
        #expect(!relevant(isPress: true, held: combo, configured: nil))
        #expect(!relevant(isPress: true, held: [], configured: nil))
    }

    @Test func dragOrReleaseWithoutGestureIsIrrelevant() {
        #expect(!relevant(isPress: false, held: combo))
        #expect(!relevant(isPress: false, held: []))
    }

    @Test func activeGestureMakesEverythingRelevant() {
        #expect(relevant(isPress: false, held: [], active: true))
        #expect(relevant(isPress: false, held: combo, active: true))
        #expect(relevant(isPress: true, held: [], active: true))
        #expect(relevant(isPress: false, held: [], configured: nil, active: true))
    }
}
