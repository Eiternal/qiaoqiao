import Foundation

enum EffectiveInputKind: String { case keyboard, click, movement, scroll }
struct PointerDecision {
    var active = false
    var counted = false
}

/// Aggregate high-rate device samples into meaningful actions. No pointer positions
/// or input content are stored. A stopped pointer cannot earn counts on a timer.
final class PointerInputFilter {
    private var moveDistance = 0.0, moveActivityDistance = 0.0, scrollDistance = 0.0
    private var lastMove = Date.distantPast, lastScroll = Date.distantPast
    private var lastMoveCount = Date.distantPast, lastMoveActivity = Date.distantPast
    private var lastScrollCount = Date.distantPast, lastScrollActivity = Date.distantPast

    func reset() {
        moveDistance = 0; moveActivityDistance = 0; scrollDistance = 0
        lastMove = .distantPast; lastScroll = .distantPast
        lastMoveCount = .distantPast; lastMoveActivity = .distantPast
        lastScrollCount = .distantPast; lastScrollActivity = .distantPast
    }

    func process(_ kind: EffectiveInputKind, dx: Double = 0, dy: Double = 0, momentum: Bool = false, at now: Date = Date()) -> PointerDecision {
        if kind == .click { return PointerDecision(active: true, counted: true) }
        guard dx.isFinite, dy.isFinite else { return PointerDecision() }
        if kind == .movement {
            let distance = hypot(dx, dy)
            guard distance >= 0.5 else { return PointerDecision() }
            if now.timeIntervalSince(lastMove) > 1.5 || now < lastMove { moveDistance = 0; moveActivityDistance = 0 }
            lastMove = now
            moveDistance = min(96, moveDistance + distance)
            moveActivityDistance += distance
            var result = PointerDecision()
            if moveActivityDistance >= 4 && now.timeIntervalSince(lastMoveActivity) >= 0.25 {
                result.active = true; moveActivityDistance = 0; lastMoveActivity = now
            }
            if moveDistance >= 24 && now.timeIntervalSince(lastMoveCount) >= 1 {
                result.counted = true; result.active = true; moveDistance = 0; lastMoveCount = now
            }
            return result
        }
        if kind == .scroll {
            guard !momentum else { return PointerDecision() }
            let distance = abs(dx) + abs(dy)
            guard distance > 0.01 else { return PointerDecision() }
            if now.timeIntervalSince(lastScroll) > 0.8 || now < lastScroll { scrollDistance = 0 }
            lastScroll = now; scrollDistance = min(64, scrollDistance + distance)
            var result = PointerDecision()
            if now.timeIntervalSince(lastScrollActivity) >= 0.2 { result.active = true; lastScrollActivity = now }
            if scrollDistance >= 8 && now.timeIntervalSince(lastScrollCount) >= 0.2 {
                result.counted = true; result.active = true; scrollDistance = 0; lastScrollCount = now
            }
            return result
        }
        return PointerDecision()
    }
}

struct SavedRestSession: Codable {
    var enabled: Bool
    var intervalSeconds: TimeInterval
    var activeSeconds: TimeInterval
    var nextReminderActive: TimeInterval
    var lastActivityAt: Date?
    var savedAt: Date
}

/// An input-based estimate, not a claim to detect reading or the contents of work.
/// Short idle gaps pause accumulation; a genuine five-minute break resets it.
final class RestReminderModel {
    private(set) var enabled: Bool
    private(set) var intervalSeconds: TimeInterval
    private(set) var activeSeconds: TimeInterval
    private(set) var nextReminderActive: TimeInterval
    private(set) var lastActivity: Date?
    private(set) var isSuspended = false
    let idleGrace: TimeInterval
    let resetAfterBreak: TimeInterval
    private var accountedAt: Date
    private var suspendedAt: Date?
    private var lastKnownActivity: Date?

    init(now: Date = Date(), saved: SavedRestSession? = nil, interval: TimeInterval = 45 * 60, idleGrace: TimeInterval = 60, resetAfterBreak: TimeInterval = 5 * 60) {
        self.idleGrace = idleGrace; self.resetAfterBreak = resetAfterBreak
        enabled = saved?.enabled ?? true
        let candidate = saved?.intervalSeconds ?? interval
        intervalSeconds = candidate.isFinite && candidate >= 1 && candidate <= 86400 ? candidate : 45 * 60
        activeSeconds = 0; nextReminderActive = intervalSeconds; accountedAt = now
        if let saved = saved, now >= saved.savedAt,
           now.timeIntervalSince(saved.lastActivityAt ?? saved.savedAt) < resetAfterBreak {
            activeSeconds = saved.activeSeconds.isFinite ? max(0, saved.activeSeconds) : 0
            nextReminderActive = saved.nextReminderActive.isFinite && saved.nextReminderActive > 0 ? saved.nextReminderActive : activeSeconds + intervalSeconds
            lastKnownActivity = saved.lastActivityAt
        }
        // App downtime is never credited. Wait for a new event to resume.
    }

    func advance(at now: Date) {
        guard !isSuspended else { accountedAt = now; return }
        if now < accountedAt { accountedAt = now; lastActivity = nil; lastKnownActivity = nil; return }
        if let last = lastActivity {
            let end = min(now, last.addingTimeInterval(idleGrace))
            if end > accountedAt { activeSeconds += end.timeIntervalSince(accountedAt) }
            if now.timeIntervalSince(last) >= resetAfterBreak {
                activeSeconds = 0; nextReminderActive = intervalSeconds; lastActivity = nil; lastKnownActivity = nil
            }
        } else if let known = lastKnownActivity, now.timeIntervalSince(known) >= resetAfterBreak {
            activeSeconds = 0; nextReminderActive = intervalSeconds; lastKnownActivity = nil
        }
        accountedAt = now
    }

    func activity(at now: Date) {
        guard !isSuspended else { return }
        advance(at: now)
        lastActivity = now; lastKnownActivity = now
    }

    func reminderDue(at now: Date) -> Bool {
        advance(at: now)
        guard enabled, !isSuspended, let last = lastActivity else { return false }
        let age = now.timeIntervalSince(last)
        return age >= 0 && age <= 10 && activeSeconds >= nextReminderActive
    }

    func markReminded(at now: Date) { advance(at: now); nextReminderActive = activeSeconds + intervalSeconds }
    func snooze(at now: Date, seconds: TimeInterval = 10 * 60) { advance(at: now); nextReminderActive = activeSeconds + seconds }
    func resetAfterRest(at now: Date) { activeSeconds = 0; nextReminderActive = intervalSeconds; accountedAt = now; lastActivity = nil; lastKnownActivity = nil }
    func setEnabled(_ value: Bool, at now: Date) { advance(at: now); enabled = value; nextReminderActive = activeSeconds + intervalSeconds }
    func setInterval(_ value: TimeInterval, at now: Date) {
        guard value.isFinite, value >= 1, value <= 86400 else { return }
        advance(at: now); intervalSeconds = value; nextReminderActive = activeSeconds + value
    }
    func setSuspended(_ value: Bool, at now: Date) {
        guard isSuspended != value else { return }
        if value { advance(at: now); suspendedAt = now }
        else {
            if let began = suspendedAt, now.timeIntervalSince(began) >= resetAfterBreak { resetAfterRest(at: now) }
            lastActivity = nil; accountedAt = now; suspendedAt = nil
        }
        isSuspended = value
    }
    func saved(at now: Date) -> SavedRestSession {
        advance(at: now)
        return SavedRestSession(enabled: enabled, intervalSeconds: intervalSeconds, activeSeconds: activeSeconds, nextReminderActive: nextReminderActive, lastActivityAt: lastActivity ?? lastKnownActivity, savedAt: now)
    }
}

@discardableResult
func runActivityTests() -> Bool {
    var failures: [String] = []; var count = 0
    func check(_ value: @autoclosure () -> Bool, _ label: String) { count += 1; if !value() { failures.append(label) } }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let f = PointerInputFilter()
    check(f.process(.click, at: now).counted && f.process(.click, at: now).counted, "each discrete click counts")
    check(!f.process(.movement, at: now).active, "zero pointer delta is ignored")
    check(!f.process(.movement, dx: 0.1, dy: 0.1, at: now).active, "subpixel jitter is ignored")
    check(!f.process(.movement, dx: .nan, at: now).counted, "invalid delta is ignored")
    var moveCount = 0, activityCount = 0
    for i in 0..<1000 {
        let d = f.process(.movement, dx: 3, at: now.addingTimeInterval(Double(i) / 1000))
        if d.counted { moveCount += 1 }; if d.active { activityCount += 1 }
    }
    check(moveCount == 1 && activityCount <= 5, "1000 Hz movement cannot inflate count")
    check(f.process(.movement, dx: 25, at: now.addingTimeInterval(1.1)).counted, "continued movement counts after one second")
    check(!f.process(.movement, dx: 1, at: now.addingTimeInterval(5)).counted, "old distance cannot trigger a count after idle")
    let scroll = PointerInputFilter()
    check(!scroll.process(.scroll, dx: 0, dy: 0, at: now).active, "empty scroll is ignored")
    check(!scroll.process(.scroll, dy: 100, momentum: true, at: now).active, "trackpad momentum is not user input")
    check(scroll.process(.scroll, dy: 10, at: now).counted, "real scroll counts")
    check(!scroll.process(.scroll, dy: 10, at: now.addingTimeInterval(0.01)).counted, "scroll samples are throttled")
    check(scroll.process(.scroll, dy: 10, at: now.addingTimeInterval(0.21)).counted, "later scroll action counts")
    let r = RestReminderModel(now: now, interval: 10, idleGrace: 3, resetAfterBreak: 10)
    r.activity(at: now); r.activity(at: now.addingTimeInterval(2)); r.activity(at: now.addingTimeInterval(4)); r.activity(at: now.addingTimeInterval(6)); r.activity(at: now.addingTimeInterval(8))
    check(!r.reminderDue(at: now.addingTimeInterval(9)), "no early work reminder")
    r.activity(at: now.addingTimeInterval(10))
    check(r.reminderDue(at: now.addingTimeInterval(10)), "continuous work reaches reminder threshold")
    r.markReminded(at: now.addingTimeInterval(10))
    check(!r.reminderDue(at: now.addingTimeInterval(11)), "reminder cannot repeat every tick")
    r.advance(at: now.addingTimeInterval(15))
    check(abs(r.activeSeconds - 13) < 0.001, "idle time beyond grace is not credited")
    r.advance(at: now.addingTimeInterval(20))
    check(r.activeSeconds == 0, "long break resets work session")
    r.activity(at: now.addingTimeInterval(21))
    check(!r.reminderDue(at: now.addingTimeInterval(21)), "returning from a real break does not nag immediately")
    let suspension = RestReminderModel(now: now, interval: 10, idleGrace: 3, resetAfterBreak: 10)
    suspension.activity(at: now); suspension.setSuspended(true, at: now.addingTimeInterval(2)); suspension.advance(at: now.addingTimeInterval(100))
    check(abs(suspension.activeSeconds - 2) < 0.001, "suspended/locked time is not work")
    suspension.setSuspended(false, at: now.addingTimeInterval(100))
    check(suspension.activeSeconds == 0, "long sleep resets work session")
    let saved = SavedRestSession(enabled: true, intervalSeconds: 10, activeSeconds: 6, nextReminderActive: 10, lastActivityAt: now, savedAt: now)
    let restored = RestReminderModel(now: now.addingTimeInterval(3), saved: saved, idleGrace: 3, resetAfterBreak: 10)
    restored.advance(at: now.addingTimeInterval(6))
    check(restored.activeSeconds == 6, "app downtime is not credited on restore")
    let afterBreak = RestReminderModel(now: now.addingTimeInterval(20), saved: saved, idleGrace: 3, resetAfterBreak: 10)
    check(afterBreak.activeSeconds == 0, "long app downtime counts as a break")
    restored.setEnabled(false, at: now.addingTimeInterval(6)); restored.activity(at: now.addingTimeInterval(7))
    check(!restored.reminderDue(at: now.addingTimeInterval(8)), "reminders can be disabled")
    restored.snooze(at: now.addingTimeInterval(8), seconds: 10)
    check(abs(restored.nextReminderActive - restored.activeSeconds - 10) < 0.001, "snooze is based on active work")
    restored.resetAfterRest(at: now.addingTimeInterval(9))
    check(restored.activeSeconds == 0 && restored.lastActivity == nil, "manual rest resets the timer")
    let rollback = RestReminderModel(now: now, interval: 10)
    rollback.activity(at: now); rollback.advance(at: now.addingTimeInterval(-100))
    check(rollback.activeSeconds == 0 && !rollback.reminderDue(at: now.addingTimeInterval(-99)), "clock rollback cannot create activity or reminders")
    let data = try! JSONEncoder().encode(restored.saved(at: now.addingTimeInterval(9)))
    check((try? JSONDecoder().decode(SavedRestSession.self, from: data)) != nil, "rest preferences and progress are serializable")
    let defaults = RestReminderModel(now: now)
    for second in stride(from: 0, to: 2700, by: 30) { defaults.activity(at: now.addingTimeInterval(Double(second))) }
    defaults.activity(at: now.addingTimeInterval(2699))
    check(!defaults.reminderDue(at: now.addingTimeInterval(2699)), "default interval is not shorter than 45 active minutes")
    defaults.activity(at: now.addingTimeInterval(2700))
    check(defaults.reminderDue(at: now.addingTimeInterval(2700)), "default reminder becomes due at 45 active minutes")
    let shortRestore = RestReminderModel(now: now.addingTimeInterval(3), saved: saved, idleGrace: 3, resetAfterBreak: 10)
    let resaved = shortRestore.saved(at: now.addingTimeInterval(6))
    let secondRestore = RestReminderModel(now: now.addingTimeInterval(11), saved: resaved, idleGrace: 3, resetAfterBreak: 10)
    check(secondRestore.activeSeconds == 0 && resaved.lastActivityAt == now, "repeated app restarts cannot erase a real idle break")
    print("Activity tests: \(count - failures.count)/\(count) passed")
    failures.forEach { print("FAIL: \($0)") }; return failures.isEmpty
}
