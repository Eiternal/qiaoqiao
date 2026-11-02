import Foundation

enum InputCountingRule: String {
    case keyAndMouseButtons, keyboardOnly, effectiveActivity
    func includesPointer(_ kind: EffectiveInputKind) -> Bool {
        switch self {
        case .keyAndMouseButtons: return kind == .click
        case .keyboardOnly: return false
        case .effectiveActivity: return true
        }
    }
    var pointerExplanation: String {
        switch self {
        case .keyAndMouseButtons: return "鼠标只在按钮按下时加次数；移动和滚动仅用于保持清醒与休息计时。"
        case .keyboardOnly: return "鼠标不加次数，其活动仅用于保持清醒与休息计时。"
        case .effectiveActivity: return "鼠标点击按次记录，移动和滚动按有效距离与时间聚合记录。"
        }
    }
}

/// Modifier presses arrive as flagsChanged, not ordinary keyDown events.
/// Side-specific bits come from Apple's IOLLEvent.h. Releases never add counts,
/// including releasing one Shift while the other Shift is still held.
final class ModifierPressFilter {
    private static let masks: [Int: UInt64] = [54: 0x10, 55: 0x08, 56: 0x02, 58: 0x20, 59: 0x01, 60: 0x04, 61: 0x40, 62: 0x2000, 63: 0x00800000]
    private var held: Set<Int> = []
    private var capsLogical = false
    private var capsPhysical = false

    func reset(flags: UInt64) {
        held = Set(Self.masks.compactMap { flags & $0.value != 0 ? $0.key : nil })
        capsLogical = flags & 0x00010000 != 0
        capsPhysical = flags & 0x01000000 != 0
    }

    func pressed(code: Int, flags: UInt64) -> Bool {
        if code == 57 {
            let logical = flags & 0x00010000 != 0, physical = flags & 0x01000000 != 0
            // Both toggling Caps Lock on and toggling it off are presses.
            // Stateless flags also cover modern Caps-to-input-source mappings.
            let result = logical != capsLogical || (physical && !capsPhysical)
            capsLogical = logical; capsPhysical = physical
            return result
        }
        guard let mask = Self.masks[code] else { return false }
        if flags & mask == 0 { held.remove(code); return false }
        return held.insert(code).inserted
    }
}

func runPressInputTests() -> Bool {
    var checks = 0, failures: [String] = []
    func check(_ value: Bool, _ message: String) { checks += 1; if !value { failures.append(message) } }
    let now = Date()
    let model = CounterModel(now: now)
    // n i h a o + Space: six down events irrespective of what an IME commits.
    for code in [45, 34, 4, 0, 31, 49] { model.recordKeyboardInput(keyCode: code, at: now) }
    check(model.todayCount == 6, "six physical presses count six; committed text is never consulted")
    for _ in 0..<40 { model.recordKeyboardInput(keyCode: 51, isRepeat: true, at: now) }
    check(model.todayCount == 6, "system auto-repeat does not manufacture new presses")
    model.recordKeyboardInput(keyCode: 51, at: now)
    model.recordKeyboardInput(keyCode: 51, at: now)
    check(model.todayCount == 8, "two separate deletion presses count twice")
    let modifiers = ModifierPressFilter(); modifiers.reset(flags: 0)
    check(modifiers.pressed(code: 56, flags: 0x20002), "left Shift press counts")
    check(!modifiers.pressed(code: 56, flags: 0x20002), "duplicate held modifier does not count")
    check(modifiers.pressed(code: 60, flags: 0x20006), "right Shift is an independent physical key")
    check(!modifiers.pressed(code: 56, flags: 0x20004), "left Shift release is not another press while right Shift remains held")
    check(!modifiers.pressed(code: 60, flags: 0), "right Shift release does not count")
    check(modifiers.pressed(code: 56, flags: 0x20002), "repressing a released Shift counts again")
    for (code, mask) in [(54, UInt64(0x10)), (55, 0x8), (58, 0x20), (59, 0x1), (61, 0x40), (62, 0x2000), (63, 0x800000)] {
        modifiers.reset(flags: 0)
        check(modifiers.pressed(code: code, flags: mask) && !modifiers.pressed(code: code, flags: 0), "modifier \(code) counts down only")
    }
    modifiers.reset(flags: 0)
    check(modifiers.pressed(code: 57, flags: 0x10000), "Caps Lock toggled on counts")
    check(!modifiers.pressed(code: 57, flags: 0x10000), "Caps Lock unchanged flags do not count again")
    check(modifiers.pressed(code: 57, flags: 0), "Caps Lock toggled off also counts")
    modifiers.reset(flags: 0)
    check(modifiers.pressed(code: 57, flags: 0x1000000) && !modifiers.pressed(code: 57, flags: 0), "stateless Caps press and release count once")
    modifiers.reset(flags: 0x100008)
    check(!modifiers.pressed(code: 55, flags: 0x100008) && !modifiers.pressed(code: 55, flags: 0), "a key held before reconnection is not counted on resume or release")
    let rule = InputCountingRule.keyAndMouseButtons
    check(rule.includesPointer(.click) && !rule.includesPointer(.movement) && !rule.includesPointer(.scroll), "only actual mouse button downs count in press mode")
    check(!InputCountingRule.keyboardOnly.includesPointer(.click) && InputCountingRule.effectiveActivity.includesPointer(.movement), "explicit counting preferences remain distinct")
    check(CounterModel.isEffectiveKey(55) && CounterModel.isEffectiveKey(56) && CounterModel.isEffectiveKey(57), "modifier physical presses are eligible")
    print("Physical press tests: \(checks - failures.count)/\(checks) passed")
    failures.forEach { print("FAIL: \($0)") }
    return failures.isEmpty
}
