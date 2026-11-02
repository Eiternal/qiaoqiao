import Foundation

enum PetMood: String {
    case awake, typing, drowsy, sleeping, paused
}

struct SavedCounter: Codable {
    var day: String
    var count: Int
    var sleepSeconds: TimeInterval
    var lifetimeCount: Int? = nil
}

/// Counts meaningful keyboard and pointer actions, never their content.
final class CounterModel {
    private(set) var todayCount: Int
    private(set) var lifetimeCount: Int
    private(set) var day: String
    private(set) var recent: [TimeInterval] = []
    private(set) var lastInput: Date?
    private(set) var isPaused = false
    private(set) var pressSerial = 0
    var sleepSeconds: TimeInterval
    let launchedAt: Date
    private let calendar: Calendar

    init(now: Date = Date(), saved: SavedCounter? = nil, calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
        launchedAt = now
        day = Self.dayKey(now, calendar: calendar)
        todayCount = saved?.day == day ? max(0, saved?.count ?? 0) : 0
        // Pre-0.4 saves only contain one day's count; credit the recorded amount once.
        lifetimeCount = max(todayCount, max(0, saved?.lifetimeCount ?? saved?.count ?? 0))
        sleepSeconds = [30.0, 60.0, 120.0].contains(saved?.sleepSeconds ?? 60) ? (saved?.sleepSeconds ?? 60) : 60
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }

    static func isTypingKey(_ code: Int) -> Bool {
        // ANSI/ISO/JIS letters, punctuation, digits, space, tab, return, deletion and keypad.
        // Modifiers, Escape, arrows, navigation, function and media keys are omitted.
        if (0...51).contains(code) { return true }
        return Set([65, 67, 69, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 93, 94, 95, 102, 104, 117]).contains(code)
    }

    static func isEffectiveKey(_ code: Int) -> Bool {
        (0...127).contains(code)
    }

    func noteActivity(at now: Date = Date()) {
        guard !isPaused else { return }; tick(at: now); lastInput = now
    }
    @discardableResult
    func recordEffectiveInput(at now: Date = Date()) -> Bool {
        tick(at: now); guard !isPaused else { return false }
        todayCount += 1; lifetimeCount += 1; pressSerial += 1
        recent.append(now.timeIntervalSince1970); lastInput = now
        return true
    }
    @discardableResult
    func recordKeyboardInput(keyCode: Int, isRepeat: Bool = false, at now: Date = Date()) -> Bool {
        guard !isPaused, Self.isEffectiveKey(keyCode) else { return false }
        if isRepeat { noteActivity(at: now); return false }
        return recordEffectiveInput(at: now)
    }

    @discardableResult
    func record(keyCode: Int, isRepeat: Bool = false, command: Bool = false, control: Bool = false, at now: Date = Date()) -> Bool {
        tick(at: now)
        guard !isPaused, !command, !control, Self.isTypingKey(keyCode) else { return false }
        if isRepeat { lastInput = now; return false }
        todayCount += 1
        lifetimeCount += 1
        pressSerial += 1
        recent.append(now.timeIntervalSince1970)
        lastInput = now
        return true
    }

    func tick(at now: Date = Date()) {
        let currentDay = Self.dayKey(now, calendar: calendar)
        if currentDay != day {
            day = currentDay
            todayCount = 0
        }
        let cutoff = now.timeIntervalSince1970 - 60
        recent.removeAll { $0 <= cutoff || $0 > now.timeIntervalSince1970 }
    }

    func rate(at now: Date = Date()) -> Int {
        tick(at: now)
        return recent.count
    }

    func histogram(at now: Date = Date()) -> [Int] {
        tick(at: now)
        var bins = Array(repeating: 0, count: 24)
        for time in recent {
            let index = min(23, max(0, Int((time - (now.timeIntervalSince1970 - 60)) / 2.5)))
            bins[index] += 1
        }
        return bins
    }

    func mood(at now: Date = Date()) -> PetMood {
        if isPaused { return .paused }
        let idle = max(0, now.timeIntervalSince(lastInput ?? launchedAt))
        if idle >= sleepSeconds { return .sleeping }
        // Drowsiness is a brief lead-in to the chosen sleep deadline, rather
        // than 15...120 seconds of an endless nodding animation.
        if idle >= max(0, sleepSeconds - 5) { return .drowsy }
        if lastInput != nil && idle < 1.15 { return .typing }
        return .awake
    }

    func setPaused(_ value: Bool, at now: Date = Date()) {
        isPaused = value
        recent.removeAll()
        if !value { lastInput = now }
    }

    func saved() -> SavedCounter {
        SavedCounter(day: day, count: todayCount, sleepSeconds: sleepSeconds, lifetimeCount: lifetimeCount)
    }
}

@discardableResult
func runModelTests() -> Bool {
    var failures: [String] = []
    var count = 0
    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        count += 1
        if !condition() { failures.append(message) }
    }
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let model = CounterModel(now: now, calendar: utc)
    check(model.record(keyCode: 0, at: now), "letters count")
    check(model.record(keyCode: 49, at: now.addingTimeInterval(1)), "space counts")
    check(model.record(keyCode: 51, at: now.addingTimeInterval(2)), "delete counts")
    check(model.todayCount == 3, "count matches physical presses")
    check(!model.record(keyCode: 0, isRepeat: true, at: now.addingTimeInterval(2)), "auto-repeat ignored")
    check(!model.record(keyCode: 0, command: true, at: now.addingTimeInterval(2)), "Command shortcut ignored")
    check(!model.record(keyCode: 0, control: true, at: now.addingTimeInterval(2)), "Control shortcut ignored")
    check(!model.record(keyCode: 123, at: now.addingTimeInterval(2)), "arrow ignored")
    check(!model.record(keyCode: 56, at: now.addingTimeInterval(2)), "modifier ignored")
    check(!model.record(keyCode: 53, at: now.addingTimeInterval(2)), "Escape ignored")
    check(model.rate(at: now.addingTimeInterval(59.9)) == 3, "rolling window retains recent presses")
    check(model.rate(at: now.addingTimeInterval(60)) == 2, "exactly 60-second-old press expires")
    check(model.rate(at: now.addingTimeInterval(62)) == 0, "rate becomes zero without new input")
    check(model.todayCount == 3, "rolling expiry does not reset daily total")
    let pet = CounterModel(now: now, calendar: utc)
    check(pet.mood(at: now) == .awake, "starts awake")
    check(pet.mood(at: now.addingTimeInterval(15)) == .awake, "does not spend the whole idle period nodding")
    check(pet.mood(at: now.addingTimeInterval(55)) == .drowsy, "drowsy only in the five seconds before sleep")
    check(pet.mood(at: now.addingTimeInterval(60)) == .sleeping, "sleep after 60 seconds")
    pet.record(keyCode: 2, at: now.addingTimeInterval(70))
    check(pet.mood(at: now.addingTimeInterval(70)) == .typing, "one key wakes pet immediately")
    check(pet.mood(at: now.addingTimeInterval(72)) == .awake, "typing returns to idle")
    pet.setPaused(true, at: now.addingTimeInterval(73))
    check(!pet.record(keyCode: 0, at: now.addingTimeInterval(74)), "pause prevents recording")
    check(pet.mood(at: now.addingTimeInterval(75)) == .paused, "paused mood")
    check(pet.rate(at: now.addingTimeInterval(75)) == 0, "pause clears live rate")
    pet.setPaused(false, at: now.addingTimeInterval(80))
    check(pet.record(keyCode: 0, at: now.addingTimeInterval(81)), "resume records again")
    let histogram = pet.histogram(at: now.addingTimeInterval(82))
    check(histogram.count == 24 && histogram.reduce(0, +) == 1, "histogram matches window")
    let today = CounterModel.dayKey(now, calendar: utc)
    let restored = CounterModel(now: now, saved: SavedCounter(day: today, count: 55, sleepSeconds: 120), calendar: utc)
    check(restored.todayCount == 55 && restored.sleepSeconds == 120, "restore same-day count and preference")
    let nextDay = utc.startOfDay(for: now).addingTimeInterval(86_401)
    restored.tick(at: nextDay)
    check(restored.todayCount == 0, "daily total resets at local midnight")
    let old = CounterModel(now: nextDay, saved: SavedCounter(day: today, count: 55, sleepSeconds: 60), calendar: utc)
    check(old.todayCount == 0, "yesterday's saved count is not shown today")
    let data = try! JSONEncoder().encode(pet.saved())
    check((try? JSONDecoder().decode(SavedCounter.self, from: data))?.count == pet.todayCount, "persistence round trip")
    let thirty = CounterModel(now: now, saved: SavedCounter(day: today, count: 0, sleepSeconds: 30), calendar: utc)
    check(thirty.mood(at: now.addingTimeInterval(30)) == .sleeping, "custom sleep threshold")
    check(restored.lifetimeCount == 55, "lifetime progress survives midnight")
    check(old.lifetimeCount == 55 && old.todayCount == 0, "legacy save migration credits recorded historical count")
    let lifetime = CounterModel(now: now, saved: SavedCounter(day: today, count: 20, sleepSeconds: 60, lifetimeCount: 500), calendar: utc)
    lifetime.record(keyCode: 0, at: now)
    lifetime.record(keyCode: 0, isRepeat: true, at: now)
    check(lifetime.lifetimeCount == 501 && lifetime.todayCount == 21, "only accepted keys increment lifetime")
    let legacyData = Data("{\"day\":\"\(today)\",\"count\":91,\"sleepSeconds\":60}".utf8)
    let legacySave = try? JSONDecoder().decode(SavedCounter.self, from: legacyData)
    check(legacySave != nil && CounterModel(now: now, saved: legacySave, calendar: utc).lifetimeCount == 91, "old JSON remains decodable")
    let allInput = CounterModel(now: now, calendar: utc)
    check(allInput.recordKeyboardInput(keyCode: 123, at: now), "navigation keys count as effective work input")
    check(allInput.recordKeyboardInput(keyCode: 122, at: now), "function keys count as effective work input")
    check(allInput.recordKeyboardInput(keyCode: 55, at: now), "a real modifier press counts")
    check(!allInput.recordKeyboardInput(keyCode: 1000, at: now), "invalid key code does not count")
    check(allInput.recordEffectiveInput(at: now) && allInput.todayCount == 4, "pointer and keyboard share one counter")
    allInput.noteActivity(at: now.addingTimeInterval(100))
    check(allInput.mood(at: now.addingTimeInterval(100)) == .typing && allInput.todayCount == 4, "active mouse prevents sleep without inflating count")
    allInput.setPaused(true, at: now)
    check(!allInput.recordEffectiveInput(at: now), "pause applies to pointer input too")
    print("Counter tests: \(count - failures.count)/\(count) passed")
    failures.forEach { print("FAIL: \($0)") }
    return failures.isEmpty
}
