import Foundation

enum DeskTimerKind: String, Codable { case countdown, workday, pomodoro }
enum DeskTimerState: String, Codable { case running, paused, awaiting, finished }
enum PomodoroPhase: String, Codable { case focus, shortBreak, longBreak }

struct DeskTimer: Codable, Identifiable {
    var id = UUID()
    var title: String
    var kind: DeskTimerKind
    var state: DeskTimerState = .running
    var phase: PomodoroPhase = .focus
    var deadline: Date?
    var remaining: Double = 0
    var duration: Double
    var focusSeconds: Double = 1500
    var shortSeconds: Double = 300
    var longSeconds: Double = 900
    var rounds: Int = 4
    var completedFocus: Int = 0
    var repeatWeekdays = false
    var workHour = 18
    var workMinute = 0
    var acknowledged = false
    var active: Bool { state != .finished }
    var canPause: Bool { kind != .workday && (state == .running || state == .paused) }
    func seconds(at now: Date) -> Double {
        if state == .paused { return max(0, remaining) }
        return state == .running ? max(0, deadline?.timeIntervalSince(now) ?? 0) : 0
    }
    func progress(at now: Date) -> Double { min(1, max(0, 1 - seconds(at: now) / max(1, duration))) }
    var phaseTitle: String { kind == .pomodoro ? (phase == .focus ? "专注" : (phase == .shortBreak ? "短休息" : "长休息")) : (kind == .workday ? "下班倒计时" : "自由倒计时") }
    var symbol: String { state == .paused ? "Ⅱ" : (kind == .pomodoro ? "◉" : (kind == .workday ? "☼" : "◷")) }
    var completionText: String {
        if kind == .workday { return "到下班时间啦，辛苦了～" }
        if kind == .countdown { return title + "，到时间啦。" }
        return phase == .focus ? "这一段专注完成啦，歇一会儿吧。" : "休息结束啦，准备好再继续。"
    }
    var advanceTitle: String {
        if kind != .pomodoro { return "知道啦" }
        return phase == .focus ? (completedFocus % max(1, rounds) == 0 ? "开始长休息" : "开始短休息") : "开始专注"
    }
    static func timeText(_ seconds: Double) -> String {
        let n = seconds.isFinite ? Int(min(604800, max(0, ceil(seconds)))) : 0
        return n >= 3600 ? String(format: "%02d:%02d:%02d", n / 3600, n / 60 % 60, n % 60) : String(format: "%02d:%02d", n / 60, n % 60)
    }
}

struct SavedTimerBook: Codable {
    var items: [DeskTimer] = []
    var selectedID: UUID?
    var showBadge = true
}

enum TimerIssue: LocalizedError {
    case invalid, full, alreadyRunning
    var errorDescription: String? {
        switch self {
        case .invalid: return "请填写有效的名称和时间；自由倒计时为 1 秒到 7 天。"
        case .full: return "最多保存 20 个计时，请先删除已结束的项目。"
        case .alreadyRunning: return "这个模式已经在计时啦，请先结束原来的计时。"
        }
    }
}

/// UI pulses repaint only. Absolute deadlines survive delayed callbacks,
/// app termination and machine sleep; a missed Pomodoro never invents rounds.
final class TimerBookModel {
    private(set) var items: [DeskTimer]
    var selectedID: UUID?
    var showBadge: Bool
    var pending: [DeskTimer] { items.filter { $0.state == .awaiting && !$0.acknowledged } }
    var display: DeskTimer? {
        guard showBadge else { return nil }
        return items.first { $0.id == selectedID && $0.active } ?? items.first { $0.state == .awaiting } ?? items.filter { $0.state == .running }.min { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) } ?? items.first { $0.active }
    }
    init(saved: SavedTimerBook? = nil) {
        var seen = Set<UUID>()
        items = (saved?.items ?? []).filter { seen.insert($0.id).inserted }.prefix(20).map { value in
            var t = value
            t.title = String(t.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            if t.title.isEmpty { t.title = t.kind == .pomodoro ? "番茄钟" : "倒计时" }
            t.duration = Self.safe(t.duration, fallback: 1500, min: 1, max: 604800)
            t.remaining = Self.safe(t.remaining, fallback: t.duration, min: 0, max: 604800)
            t.focusSeconds = Self.safe(t.focusSeconds, fallback: 1500, min: 60, max: 10800)
            t.shortSeconds = Self.safe(t.shortSeconds, fallback: 300, min: 60, max: 3600)
            t.longSeconds = Self.safe(t.longSeconds, fallback: 900, min: 60, max: 7200)
            t.rounds = min(12, max(1, t.rounds)); t.completedFocus = min(1_000_000, max(0, t.completedFocus))
            t.workHour = min(23, max(0, t.workHour)); t.workMinute = min(59, max(0, t.workMinute))
            if t.state == .running && (t.deadline == nil || t.deadline?.timeIntervalSince1970.isFinite != true) { t.state = .paused; t.deadline = nil; t.remaining = t.duration }
            return t
        }
        selectedID = saved?.selectedID; showBadge = saved?.showBadge ?? true
    }
    private static func safe(_ v: Double, fallback: Double, min lo: Double, max hi: Double) -> Double { v.isFinite ? min(hi, max(lo, v)) : fallback }
    private func room(_ kind: DeskTimerKind) throws {
        guard items.count < 20 else { throw TimerIssue.full }
        if kind != .countdown && items.contains(where: { $0.kind == kind && $0.active }) { throw TimerIssue.alreadyRunning }
    }
    private func name(_ value: String, fallback: String) throws -> String {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count <= 40 else { throw TimerIssue.invalid }; return title.isEmpty ? fallback : title
    }
    @discardableResult func countdown(title: String, seconds: Double, at now: Date) throws -> UUID {
        try room(.countdown)
        guard seconds.isFinite && seconds >= 1 && seconds <= 604800 else { throw TimerIssue.invalid }
        let t = DeskTimer(title: try name(title, fallback: "自由倒计时"), kind: .countdown, deadline: now.addingTimeInterval(seconds), duration: seconds)
        items.append(t); selectedID = t.id; return t.id
    }
    @discardableResult func workday(until end: Date, repeatWeekdays: Bool, at now: Date, calendar: Calendar = .autoupdatingCurrent) throws -> UUID {
        try room(.workday)
        let duration = end.timeIntervalSince(now)
        guard duration.isFinite && duration > 0 && duration <= 604800 else { throw TimerIssue.invalid }
        var t = DeskTimer(title: "下班倒计时", kind: .workday, deadline: end, duration: duration)
        t.repeatWeekdays = repeatWeekdays; t.workHour = calendar.component(.hour, from: end); t.workMinute = calendar.component(.minute, from: end)
        items.append(t); selectedID = t.id; return t.id
    }
    @discardableResult func pomodoro(focus: Double = 1500, short: Double = 300, long: Double = 900, rounds: Int = 4, at now: Date) throws -> UUID {
        try room(.pomodoro)
        guard focus.isFinite && short.isFinite && long.isFinite && (60...10800).contains(focus) && (60...3600).contains(short) && (60...7200).contains(long) && (1...12).contains(rounds) else { throw TimerIssue.invalid }
        var t = DeskTimer(title: "番茄钟", kind: .pomodoro, deadline: now.addingTimeInterval(focus), duration: focus)
        t.focusSeconds = focus; t.shortSeconds = short; t.longSeconds = long; t.rounds = rounds
        items.append(t); selectedID = t.id; return t.id
    }
    @discardableResult func tick(at now: Date) -> Bool {
        var changed = false
        for i in items.indices where items[i].state == .running && (items[i].deadline ?? .distantFuture) <= now {
            items[i].state = .awaiting; items[i].deadline = nil; items[i].remaining = 0
            items[i].acknowledged = false
            if items[i].kind == .pomodoro && items[i].phase == .focus { items[i].completedFocus = min(1_000_000, items[i].completedFocus + 1) }
            changed = true
        }
        return changed
    }
    @discardableResult func pause(_ id: UUID, at now: Date) -> Bool {
        _ = tick(at: now)
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].canPause else { return false }
        if items[i].state == .running {
            items[i].remaining = items[i].seconds(at: now); items[i].deadline = nil; items[i].state = .paused
        } else { items[i].deadline = now.addingTimeInterval(items[i].remaining); items[i].state = .running }
        return true
    }
    @discardableResult func advance(_ id: UUID, at now: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].state == .awaiting else { return false }
        var t = items[i]
        if t.kind == .pomodoro {
            t.phase = t.phase == .focus ? (t.completedFocus % t.rounds == 0 ? .longBreak : .shortBreak) : .focus
            t.duration = t.phase == .focus ? t.focusSeconds : (t.phase == .shortBreak ? t.shortSeconds : t.longSeconds)
            t.deadline = now.addingTimeInterval(t.duration); t.state = .running
        } else if t.kind == .workday && t.repeatWeekdays, let next = Self.nextWorkday(after: now, hour: t.workHour, minute: t.workMinute, calendar: calendar) {
            t.deadline = next; t.duration = next.timeIntervalSince(now); t.state = .running
        } else { t.state = .finished }
        t.acknowledged = false; items[i] = t; return true
    }
    func acknowledge(_ id: UUID) { if let i = items.firstIndex(where: { $0.id == id }) { items[i].acknowledged = true } }
    @discardableResult func restart(_ id: UUID, at now: Date) -> Bool {
        guard let i = items.firstIndex(where: { $0.id == id && $0.kind == .countdown }) else { return false }
        items[i].state = .running; items[i].deadline = now.addingTimeInterval(items[i].duration); items[i].acknowledged = false; return true
    }
    @discardableResult func stop(_ id: UUID) -> Bool {
        guard let i = items.firstIndex(where: { $0.id == id && $0.active }) else { return false }
        items[i].state = .finished; items[i].deadline = nil; items[i].remaining = 0; return true
    }
    func remove(_ id: UUID) { items.removeAll { $0.id == id }; if selectedID == id { selectedID = nil } }
    func saved() -> SavedTimerBook { SavedTimerBook(items: items, selectedID: selectedID, showBadge: showBadge) }
    static func nextWorkday(after now: Date, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        for day in 0...8 {
            guard let date = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: now)), (2...6).contains(calendar.component(.weekday, from: date)),
                  let target = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date), target > now else { continue }
            return target
        }
        return nil
    }
}
