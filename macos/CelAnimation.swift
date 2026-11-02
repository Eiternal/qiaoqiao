import Foundation

enum CelState: String, CaseIterable {
    case idle, typing, fast, deleting, drowsy, sleeping, waking, dragging, petting, resizing, rest, reminder
    var title: String {
        switch self {
        case .idle: return "安静陪伴"
        case .typing: return "跟着敲字"
        case .fast: return "爪子忙不过来"
        case .deleting: return "慢慢修改"
        case .drowsy: return "开始犯困"
        case .sleeping: return "呼呼睡觉"
        case .waking: return "伸个懒腰"
        case .dragging: return "被提起来啦"
        case .petting: return "摸摸小星狸"
        case .resizing: return "弹一弹"
        case .rest: return "喝口茶歇一歇"
        case .reminder: return "到时间啦"
        }
    }
    static func forReaction(_ pose: PetReaction?, reminder: Bool = false) -> CelState {
        if reminder { return .reminder }
        switch pose {
        case .typing, .mousing, .scrolling: return .typing
        case .fast: return .fast
        case .deleting: return .deleting
        case .drowsy: return .drowsy
        case .sleeping, .paused: return .sleeping
        case .waking, .resumed: return .waking
        case .dragging: return .dragging
        case .resizing: return .resizing
        case .rest, .restPreview: return .rest
        case .scheduledReminder: return .reminder
        case .pressed, .petting, .dropped, .resized, .shown, .dressed, .outfitUnlocked, .original, .restDone,
             .reminderSaved, .reminderEdited, .reminderDone, .reminderSnoozed, .reminderAcknowledged, .reminderDeleted: return .petting
        default: return .idle
        }
    }
    /// Exposure is measured in 24 fps ticks. Most acting is on twos; quiet cels
    /// hold longer. The fast paw-smear drawings last exactly one tick.
    var exposures: [(cel: Int, ticks: Int)] {
        switch self {
        case .idle: return [(0,18),(1,6),(0,18),(1,6),(0,18),(2,3),(0,12),(3,5)]
        case .typing: return [(0,2),(1,3),(2,2),(3,3)]
        case .fast: return [(0,2),(1,1),(2,2),(3,1)]
        case .deleting: return [(0,5),(1,5),(2,5),(3,9)]
        case .drowsy: return [(0,18),(1,16),(2,12),(3,22),(1,52)]
        // Stay on the settled, closed-eye drawing. Breathing is a tiny
        // continuous deformation, never a loop of lifting/dropping the head.
        case .sleeping: return [(1,24)]
        case .waking: return [(0,3),(1,9),(2,5),(3,13)]
        case .dragging: return [(0,5),(1,5),(0,5),(2,5),(3,5)]
        case .petting: return [(0,3),(1,6),(2,10),(3,11)]
        case .resizing: return [(0,3),(1,4),(2,4),(3,5)]
        case .rest: return [(0,9),(1,8),(2,12),(3,13)]
        case .reminder: return [(0,5),(1,4),(2,5),(3,10)]
        }
    }
    var loops: Bool { ![.waking, .petting, .drowsy].contains(self) }
    /// Live typing starts on contact, rather than waiting for the anticipation
    /// drawing in the authored loop. Each event alternates paws; release does
    /// not continue an unrelated typing loop after the user has stopped.
    func inputCel(age: TimeInterval, serial: Int, reduced: Bool) -> Int? {
        guard [.typing, .fast, .deleting].contains(self) else { return nil }
        if reduced { return self == .deleting ? 3 : 1 }
        let age = max(0, age)
        if self == .deleting { return age < 0.09 ? (serial % 2 == 0 ? 2 : 1) : 3 }
        if age < 0.09 { return serial % 2 == 0 ? 3 : 1 }
        return serial % 2 == 0 ? 2 : 0
    }
    func cel(at elapsed: TimeInterval, reduced: Bool = false) -> Int {
        if reduced { return self == .sleeping ? 1 : (self == .drowsy ? 0 : (self == .typing ? 1 : (self == .petting || self == .waking ? 3 : 0))) }
        let entries = exposures, total = entries.reduce(0) { $0 + $1.ticks }
        let safe = elapsed.isFinite ? max(0, elapsed) : 0
        let frame = min(Double(Int.max / 2), floor(safe * 24 + 0.0000001))
        var tick = loops ? Int(frame) % total : min(total - 1, Int(frame))
        for entry in entries { if tick < entry.ticks { return entry.cel }; tick -= entry.ticks }
        return entries.last!.cel
    }
}

final class CelAnimator {
    private(set) var state: CelState?
    private(set) var began = Date.distantPast
    func elapsed(for newState: CelState, at now: Date) -> TimeInterval {
        if state != newState || now < began { state = newState; began = now }
        return max(0, now.timeIntervalSince(began))
    }
}

@discardableResult
func runCelAnimationTests() -> Bool {
    var n=0, failed:[String]=[]
    func check(_ v: Bool,_ message:String){n+=1;if !v{failed.append(message)}}
    check(CelState.allCases.count==12,"twelve authored states")
    check(CelState.typing.cel(at:0)==0 && CelState.typing.cel(at:2.0/24)==1,"typing anticipation precedes impact")
    check(CelState.typing.cel(at:0.01)==CelState.typing.cel(at:0.07),"drawing holds on twos")
    check(CelState.fast.cel(at:2.0/24)==1 && CelState.fast.cel(at:3.0/24)==2,"smear exposure lasts one 24fps tick")
    check([0.0, 1, 5, 60, 3600].allSatisfy { CelState.sleeping.cel(at:$0)==1 },"sleep stays on the closed-eye drawing without nodding again")
    check(!CelState.drowsy.loops && CelState.drowsy.cel(at: 5) == 1 && CelState.drowsy.cel(at: 90) == 1, "drowsiness settles once instead of replaying its yawn")
    check(CelState.waking.cel(at:4)==3 && CelState.petting.cel(at:4)==3,"one-shot reactions settle instead of looping")
    check(CelState.forReaction(.mousing) == .typing && CelState.forReaction(.scrolling) == .typing,"mouse and scroll retain paw feedback")
    check(CelState.forReaction(.paused) == .sleeping && CelState.forReaction(.restPreview) == .rest,"pause and rest map to authored poses")
    check(CelState.forReaction(.sleeping,reminder:true) == .reminder,"due reminder overrides idle sleep")
    check(CelState.forReaction(.reminderSaved) == .petting && CelState.forReaction(.dressed) == .petting,"settings and wardrobe acknowledge with expression")
    let clock=CelAnimator(),now=Date(timeIntervalSince1970:1800000000)
    _=clock.elapsed(for:.typing,at:now)
    let elapsed=clock.elapsed(for:.typing,at:now.addingTimeInterval(0.25))
    check(elapsed==0.25,"continued key presses do not restart the paw cycle")
    check(clock.elapsed(for:.fast,at:now.addingTimeInterval(0.3))==0,"new state begins at anticipation")
    check(clock.elapsed(for:.fast,at:now.addingTimeInterval(-1))==0,"backward clock is recovered safely")
    for state in CelState.allCases {
        check((0..<500).allSatisfy{(0...3).contains(state.cel(at:Double($0)/37))},"\(state.rawValue) cannot select a missing cel")
    }
    check(CelState.allCases.allSatisfy{state in Set((0..<30).map{state.cel(at:Double($0),reduced:true)}).count==1},"reduced-motion mode freezes cel cycling")
    check(CelState.typing.inputCel(age: 0, serial: 1, reduced: false) == 1, "first live key starts on contact with no anticipation delay")
    check(CelState.typing.inputCel(age: 0, serial: 2, reduced: false) == 3, "next live key immediately alternates the paw")
    check(CelState.typing.inputCel(age: 0.1, serial: 1, reduced: false) == 0 && CelState.typing.inputCel(age: 0.1, serial: 2, reduced: false) == 2, "paws lift after each impact")
    check((1...30).allSatisfy { CelState.typing.inputCel(age: Double($0), serial: 1, reduced: false) == 0 }, "no phantom typing loop after input stops")
    check([CelState.fast, .deleting].allSatisfy { [1, 2, 3].contains($0.inputCel(age: 0, serial: 1, reduced: false) ?? 0) }, "fast and delete also start on visible contact")
    check(CelState.typing.inputCel(age: 0, serial: 1, reduced: true) == CelState.typing.inputCel(age: 0, serial: 2, reduced: true), "reduced motion does not alternate on every event")
    check(CelState.dragging.inputCel(age: 0, serial: 1, reduced: false) == nil && CelState.sleeping.inputCel(age: 0, serial: 1, reduced: false) == nil, "direct manipulation and sleep retain authored animation")
    print("Cel animation tests: \(n-failed.count)/\(n) passed");failed.forEach{print("FAIL: \($0)")};return failed.isEmpty
}
