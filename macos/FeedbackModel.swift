import Foundation

enum PetReaction: String {
    case typing, fast, deleting, drowsy, sleeping, waking, pressed, petting
    case dragging, dropped, resizing, resized, hover, menu
    case paused, resumed, shown, hidden, ghost, solid, connected, blocked
    case settings, testing, permission, screenChanged, newDay, goodbye
    case outfitUnlocked, wardrobeStored, dressed, original, catalog
    case mousing, scrolling, rest, restPreview, restDone
    case scheduledReminder, reminderSaved, reminderEdited, reminderDone, reminderSnoozed, reminderAcknowledged, reminderDeleted, reminderBook

    var priority: Int {
        switch self {
        case .scheduledReminder: return 90
        case .reminderSaved, .reminderEdited, .reminderDone, .reminderSnoozed, .reminderAcknowledged, .reminderDeleted, .reminderBook: return 100
        case .dragging, .dropped, .resizing, .resized, .petting, .hidden, .goodbye: return 100
        case .paused, .resumed, .ghost, .solid, .connected, .blocked, .settings, .testing, .permission, .dressed, .original, .catalog, .restDone, .restPreview: return 100
        case .rest: return 85
        case .outfitUnlocked, .wardrobeStored: return 95
        case .waking: return 50
        case .deleting: return 70
        case .fast: return 60
        case .drowsy, .sleeping, .shown, .screenChanged, .newDay: return 30
        default: return 10
        }
    }
    var line: String? {
        switch self {
        case .reminderSaved: return "记好啦，到点叫你。"
        case .reminderEdited: return "改好啦，到点叫你。"
        case .reminderDone: return "又完成一件，真不错。"
        case .reminderSnoozed: return "十分钟后再叫你。"
        case .reminderAcknowledged: return "我收在提醒本里。"
        case .reminderDeleted: return "已经划掉啦。"
        case .reminderBook: return "告诉我，到点叫你。"
        case .fast: return "哇，爪子跟不上啦！"
        case .deleting: return "慢慢改，我陪你。"
        case .drowsy: return "没动静了，我眯会儿。"
        case .sleeping: return "呼……叫我就醒。"
        case .waking: return "醒啦，继续陪你！"
        case .petting: return "喵～在呢。"
        case .dragging: return "诶？要搬家吗？"
        case .dropped: return "这里也不错。"
        case .resizing: return "变大，还是变小？"
        case .resized: return "这个大小刚刚好。"
        case .paused: return "那就一起歇一会儿。"
        case .resumed: return "准备好啦！"
        case .shown: return "我回来啦。"
        case .hidden: return "有事叫我哦。"
        case .ghost: return "我让开，你忙。"
        case .solid: return "又可以摸到我啦。"
        case .connected: return "听见你的键盘啦！"
        case .blocked: return "点数字，帮我连上键盘吧。"
        case .settings: return "记住啦。"
        case .testing: return "试试你的爪速？"
        case .permission: return "我等你回来。"
        case .screenChanged: return "新屏幕，调整好啦。"
        case .newDay: return "新的一天，一起加油。"
        case .goodbye: return "待会儿见。"
        case .outfitUnlocked: return "新装扮！我穿上啦。"
        case .wardrobeStored: return "衣柜又多一套啦。"
        case .dressed: return "换好啦，好看吗？"
        case .original: return "原来的样子也不错。"
        case .catalog: return "来看看我的小衣柜。"
        case .rest, .restPreview: return "陪你忙很久啦，休息一下？"
        case .restDone: return "回来啦，我们慢慢来。"
        default: return nil
        }
    }
    var cooldown: TimeInterval {
        switch self {
        case .fast: return 18
        case .deleting: return 12
        case .drowsy, .sleeping: return 15
        case .petting: return 1.5
        case .resizing: return 8
        case .screenChanged: return 8
        default: return 0
        }
    }
}

struct PetSpeech {
    let reaction: PetReaction
    let text: String
    let began: Date
    let ends: Date
    func alpha(at now: Date) -> Double {
        max(0, min(1, now.timeIntervalSince(began) / 0.12, ends.timeIntervalSince(now) / 0.28))
    }
}

final class FeedbackModel {
    enum Interaction { case none, pressed, dragging, resizing }
    private(set) var interaction = Interaction.none
    private(set) var speech: PetSpeech?
    private(set) var lastPress = Date.distantPast
    private(set) var lastInputResponse = Date.distantPast
    private(set) var inputSerial = 0
    private(set) var motion: PetReaction?
    private(set) var motionBegan = Date.distantPast
    private var motionEnds = Date.distantPast
    private var lastSpoken: [PetReaction: Date] = [:]
    private var burst: [Date] = []
    private var deletes: [Date] = []
    private var lastMood: PetMood?
    var hovered = false
    var lookX: Double = 0
    var lookY: Double = 0

    func visibleSpeech(at now: Date) -> PetSpeech? {
        guard let speech = speech, speech.ends > now else { return nil }
        return speech
    }

    func pose(mood: PetMood, at now: Date) -> PetReaction? {
        switch interaction {
        case .pressed: return .pressed
        case .dragging: return .dragging
        case .resizing: return .resizing
        default: break
        }
        if let motion = motion, motionEnds > now { return motion }
        switch mood {
        case .sleeping: return .sleeping
        case .drowsy: return .drowsy
        case .paused: return .paused
        case .typing: return .typing
        default: return nil
        }
    }

    func isAnimating(at now: Date) -> Bool {
        interaction != .none || now.timeIntervalSince(lastPress) < 0.4 || motionEnds > now || visibleSpeech(at: now) != nil
    }

    func press(at now: Date) { interaction = .pressed; lastPress = now }
    func drag(at now: Date) {
        guard interaction != .dragging else { return }
        interaction = .dragging; react(.dragging, at: now)
    }
    func beginResize(at now: Date) {
        interaction = .resizing; react(.resizing, at: now)
    }
    func release(wasDragged: Bool, at now: Date) {
        interaction = .none
        react(wasDragged ? .dropped : .petting, at: now)
    }
    func endResize(at now: Date) { interaction = .none; react(.resized, at: now) }

    func react(_ reaction: PetReaction, at now: Date = Date(), say: Bool = true, fromInput: Bool = false) {
        let onlySpeech: Set<PetReaction> = [.menu, .hover, .permission, .connected, .blocked, .settings, .testing, .screenChanged, .newDay, .goodbye, .hidden, .ghost, .solid, .catalog, .wardrobeStored]
        // Speech can finish independently. Real input must never wait for a
        // greeting, costume celebration, rest pose or landing animation.
        let ambient: Set<PetReaction> = [.outfitUnlocked, .dressed, .rest, .restPreview, .scheduledReminder, .waking, .shown, .resumed, .restDone, .reminderSaved, .reminderEdited, .reminderDone, .reminderSnoozed, .reminderAcknowledged, .reminderDeleted]
        let freshInput = now.timeIntervalSince(lastInputResponse) < 0.25
        let mayReplaceMotion = !onlySpeech.contains(reaction) && !(freshInput && !fromInput && ambient.contains(reaction)) && (fromInput || motionEnds <= now || reaction.priority >= (motion?.priority ?? 0))
        if mayReplaceMotion {
            motion = reaction; motionBegan = now
            let duration: Double = [.rest, .restPreview].contains(reaction) ? 6 : ([.fast, .deleting].contains(reaction) ? 2.1 : ([.typing, .mousing, .scrolling].contains(reaction) ? 0.25 : 1.25))
            motionEnds = now.addingTimeInterval(duration)
        }
        guard say, let line = reaction.line else { return }
        if let previous = lastSpoken[reaction], now.timeIntervalSince(previous) < reaction.cooldown { return }
        if let current = visibleSpeech(at: now), current.reaction.priority > reaction.priority { return }
        speech = PetSpeech(reaction: reaction, text: line, began: now, ends: now.addingTimeInterval([.rest, .restPreview].contains(reaction) ? 8 : 3.2))
        lastSpoken[reaction] = now
    }

    func observe(mood: PetMood, at now: Date) {
        defer { lastMood = mood }
        guard let previous = lastMood, previous != mood, interaction == .none else { return }
        if mood == .drowsy { react(.drowsy, at: now) }
        else if mood == .sleeping { react(.sleeping, at: now) }
    }

    func key(code: Int, repeated: Bool, counted: Bool, previousMood: PetMood, at now: Date) {
        guard counted || repeated else { return }
        lastPress = now
        lastInputResponse = now; inputSerial &+= 1
        if previousMood == .sleeping || previousMood == .drowsy { react(.waking, at: now) }
        lastMood = .typing
        if repeated && ![51, 117].contains(code) { react(.typing, at: now, say: false, fromInput: true); return }
        burst.removeAll { now.timeIntervalSince($0) > 2 }
        deletes.removeAll { now.timeIntervalSince($0) > 3 }
        if [51, 117].contains(code) {
            deletes.append(now)
            burst.removeAll()
            if deletes.count >= 6 { react(.deleting, at: now, fromInput: true) }
            else { react(.typing, at: now, say: false, fromInput: true) }
        } else if counted {
            deletes.removeAll()
            burst.append(now)
            if burst.count >= 12 { react(.fast, at: now, fromInput: true) }
            else { react(.typing, at: now, say: false, fromInput: true) }
        }
    }

    func activity(kind: EffectiveInputKind, counted: Bool, previousMood: PetMood, at now: Date) {
        if counted { lastPress = now; lastInputResponse = now; inputSerial &+= 1 }
        if previousMood == .sleeping || previousMood == .drowsy { react(.waking, at: now) }
        lastMood = .typing
        if counted || previousMood == .sleeping || previousMood == .drowsy {
            react(kind == .scroll ? .scrolling : (kind == .keyboard ? .typing : .mousing), at: now, say: false, fromInput: true)
        }
    }
}

@discardableResult
func runFeedbackTests() -> Bool {
    var failures: [String] = []; var count = 0
    func check(_ result: @autoclosure () -> Bool, _ message: String) {
        count += 1; if !result() { failures.append(message) }
    }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let f = FeedbackModel()
    check(f.visibleSpeech(at: now) == nil, "quiet by default")
    for i in 0..<12 { f.key(code: 0, repeated: false, counted: true, previousMood: .typing, at: now.addingTimeInterval(Double(i) * 0.1)) }
    check(f.visibleSpeech(at: now.addingTimeInterval(1.2))?.reaction == .fast, "fast typing produces feedback")
    let first = f.speech?.began
    f.key(code: 0, repeated: false, counted: true, previousMood: .typing, at: now.addingTimeInterval(1.3))
    check(f.speech?.began == first, "fast typing cannot restart speech on every key")
    check(f.visibleSpeech(at: now.addingTimeInterval(5)) == nil, "speech disappears")
    let d = FeedbackModel()
    for i in 0..<6 { d.key(code: 51, repeated: i > 0, counted: i == 0, previousMood: .typing, at: now.addingTimeInterval(Double(i) * 0.12)) }
    check(d.visibleSpeech(at: now.addingTimeInterval(0.8))?.reaction == .deleting, "held deletion also reacts without counting repeats")
    let broken = FeedbackModel()
    for i in 0..<5 { broken.key(code: 51, repeated: false, counted: true, previousMood: .typing, at: now.addingTimeInterval(Double(i) * 0.1)) }
    broken.key(code: 0, repeated: false, counted: true, previousMood: .typing, at: now.addingTimeInterval(0.6))
    broken.key(code: 51, repeated: false, counted: true, previousMood: .typing, at: now.addingTimeInterval(0.7))
    check(broken.visibleSpeech(at: now.addingTimeInterval(0.8)) == nil, "normal input breaks deletion streak")
    let idle = FeedbackModel()
    idle.observe(mood: .awake, at: now)
    idle.observe(mood: .drowsy, at: now.addingTimeInterval(15))
    check(idle.visibleSpeech(at: now.addingTimeInterval(16))?.reaction == .drowsy, "drowsy transition reacts")
    idle.observe(mood: .sleeping, at: now.addingTimeInterval(60))
    check(idle.visibleSpeech(at: now.addingTimeInterval(61))?.reaction == .sleeping, "sleep transition reacts")
    idle.key(code: 0, repeated: false, counted: true, previousMood: .sleeping, at: now.addingTimeInterval(70))
    check(idle.visibleSpeech(at: now.addingTimeInterval(71))?.reaction == .waking, "key wakes with feedback")
    let wakeFast = FeedbackModel()
    for i in 0..<12 { wakeFast.key(code: 0, repeated: false, counted: true, previousMood: i == 0 ? .sleeping : .typing, at: now.addingTimeInterval(Double(i) * 0.1)) }
    check(wakeFast.visibleSpeech(at: now.addingTimeInterval(1.2))?.reaction == .fast, "fast typing supersedes wake greeting")
    let wakeDelete = FeedbackModel()
    for i in 0..<6 { wakeDelete.key(code: 51, repeated: false, counted: true, previousMood: i == 0 ? .sleeping : .typing, at: now.addingTimeInterval(Double(i) * 0.1)) }
    check(wakeDelete.visibleSpeech(at: now.addingTimeInterval(0.7))?.reaction == .deleting, "deletion feedback supersedes wake greeting")
    let direct = FeedbackModel()
    direct.press(at: now)
    check(direct.pose(mood: .sleeping, at: now) == .pressed, "press overrides sleeping pose")
    direct.drag(at: now)
    direct.react(.fast, at: now.addingTimeInterval(0.2))
    check(direct.pose(mood: .typing, at: now.addingTimeInterval(0.2)) == .dragging, "drag overrides keyboard reaction")
    check(direct.visibleSpeech(at: now.addingTimeInterval(0.2))?.reaction == .dragging, "typing cannot overwrite drag speech")
    direct.release(wasDragged: true, at: now.addingTimeInterval(1))
    check(direct.visibleSpeech(at: now.addingTimeInterval(1.1))?.reaction == .dropped, "drop acknowledges new position")
    direct.beginResize(at: now.addingTimeInterval(2))
    check(direct.pose(mood: .awake, at: now.addingTimeInterval(2.1)) == .resizing, "resize pose persists during gesture")
    direct.endResize(at: now.addingTimeInterval(3))
    check(direct.visibleSpeech(at: now.addingTimeInterval(3.1))?.reaction == .resized, "resize completion reacts")
    let speech = PetSpeech(reaction: .petting, text: "喵", began: now, ends: now.addingTimeInterval(3))
    check(speech.alpha(at: now) == 0 && speech.alpha(at: now.addingTimeInterval(1)) == 1 && speech.alpha(at: now.addingTimeInterval(4)) == 0, "bubble fades in and out")
    let reminder = FeedbackModel(); reminder.react(.rest, at: now)
    check(reminder.visibleSpeech(at: now.addingTimeInterval(7))?.reaction == .rest && reminder.visibleSpeech(at: now.addingTimeInterval(9)) == nil, "rest bubble stays briefly then disappears")
    let heldReminder = FeedbackModel(); heldReminder.press(at: now); heldReminder.drag(at: now); heldReminder.react(.rest, at: now.addingTimeInterval(0.1))
    check(heldReminder.visibleSpeech(at: now.addingTimeInterval(0.2))?.reaction == .dragging, "automatic rest feedback does not overwrite direct manipulation")
    for reaction in [PetReaction.waking, .petting, .dropped, .outfitUnlocked, .dressed, .resized, .rest, .reminderDone] {
        let responsive = FeedbackModel(); responsive.react(reaction, at: now)
        let keyAt = now.addingTimeInterval(0.001)
        responsive.key(code: 0, repeated: false, counted: true, previousMood: .typing, at: keyAt)
        check(responsive.pose(mood: .typing, at: keyAt) == .typing && responsive.visibleSpeech(at: keyAt)?.reaction == reaction,
              "input immediately interrupts \(reaction.rawValue) without discarding its speech")
    }
    let wakingInput = FeedbackModel()
    wakingInput.key(code: 0, repeated: false, counted: true, previousMood: .sleeping, at: now)
    check(wakingInput.pose(mood: .typing, at: now) == .typing && wakingInput.visibleSpeech(at: now)?.reaction == .waking, "first waking key responds immediately and greets")
    for kind in [EffectiveInputKind.click, .movement, .scroll] {
        let pointer = FeedbackModel(); pointer.react(.rest, at: now)
        pointer.activity(kind: kind, counted: true, previousMood: .typing, at: now.addingTimeInterval(0.001))
        check(pointer.pose(mood: .typing, at: now.addingTimeInterval(0.001)) == (kind == .scroll ? .scrolling : .mousing) && pointer.inputSerial == 1, "\(kind) immediately responds through rest pose")
    }
    let noMouse = FeedbackModel(); noMouse.react(.fast, at: now)
    noMouse.activity(kind: .movement, counted: false, previousMood: .typing, at: now.addingTimeInterval(0.001))
    check(noMouse.motion == .fast && noMouse.inputSerial == 0, "uncounted movement does not cancel typing or manufacture paw impacts")
    let simultaneous = FeedbackModel()
    simultaneous.key(code: 0, repeated: false, counted: true, previousMood: .awake, at: now)
    simultaneous.react(.outfitUnlocked, at: now.addingTimeInterval(0.01))
    check(simultaneous.pose(mood: .typing, at: now.addingTimeInterval(0.01)) == .typing && simultaneous.visibleSpeech(at: now.addingTimeInterval(0.01))?.reaction == .outfitUnlocked, "a just-unlocked outfit cannot steal the current key's frame")
    print("Feedback tests: \(count - failures.count)/\(count) passed")
    failures.forEach { print("FAIL: \($0)") }
    return failures.isEmpty
}
