import Foundation

enum ScheduledReminderState: String, Codable { case scheduled, pending, done }

struct ScheduledReminder: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var dueAt: Date
    var createdAt: Date
    var updatedAt: Date
    var state: ScheduledReminderState
    var acknowledgedAt: Date?
}

struct SavedReminderBook: Codable {
    var version = 1
    var items: [ScheduledReminder]
}

enum ReminderValidation: LocalizedError {
    case empty, tooLong, invalidDate, pastDate, full, missing
    var errorDescription: String? {
        switch self {
        case .empty: return "先写下要提醒的事项。"
        case .tooLong: return "事项最多 200 个字，稍微写短一点吧。"
        case .invalidDate: return "这个时间无效，请重新选择。"
        case .pastDate: return "请选择一个还没到的时间。"
        case .full: return "提醒本已有 200 条，请先清理不需要的事项。"
        case .missing: return "这条提醒已经不存在了。"
        }
    }
}

/// One-off reminders use absolute dates. Delivery and human acknowledgement are
/// separate: a crash, sleep or restart cannot silently mark a reminder completed.
final class ReminderBookModel {
    static let maximumItems = 200
    private(set) var items: [ScheduledReminder]
    var awaiting: [ScheduledReminder] {
        items.filter { $0.state == .pending && $0.acknowledgedAt == nil }.sorted(by: Self.byTime)
    }
    var pendingCount: Int { awaiting.count }
    var sortedItems: [ScheduledReminder] {
        items.sorted {
            let a = Self.rank($0), b = Self.rank($1)
            return a == b ? Self.byTime($0, $1) : a < b
        }
    }
    private static func byTime(_ a: ScheduledReminder, _ b: ScheduledReminder) -> Bool {
        if a.dueAt != b.dueAt { return a.dueAt < b.dueAt }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }
    private static func rank(_ item: ScheduledReminder) -> Int {
        if item.state == .pending { return item.acknowledgedAt == nil ? 0 : 2 }
        return item.state == .scheduled ? 1 : 3
    }

    init(saved: SavedReminderBook? = nil) {
        // Preserve the newest copy of an ID if a damaged save contains duplicates.
        var unique: [UUID: ScheduledReminder] = [:]
        for var item in saved?.items ?? [] {
            item.title = Self.normalizedTitle(item.title)
            guard !item.title.isEmpty, item.dueAt.timeIntervalSince1970.isFinite else { continue }
            item.title = String(item.title.prefix(200))
            if item.state == .scheduled { item.acknowledgedAt = nil }
            if let previous = unique[item.id], previous.updatedAt > item.updatedAt { continue }
            unique[item.id] = item
        }
        items = unique.values.sorted(by: Self.byTime)
    }

    static func normalizedTitle(_ value: String) -> String {
        value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
    private func validTitle(_ title: String) throws -> String {
        let result = Self.normalizedTitle(title)
        guard !result.isEmpty else { throw ReminderValidation.empty }
        guard result.count <= 200 else { throw ReminderValidation.tooLong }
        return result
    }
    private func validFuture(_ date: Date, now: Date) throws {
        guard date.timeIntervalSince1970.isFinite else { throw ReminderValidation.invalidDate }
        guard date > now else { throw ReminderValidation.pastDate }
    }
    func item(_ id: UUID) -> ScheduledReminder? { items.first { $0.id == id } }

    @discardableResult
    func add(title: String, dueAt: Date, now: Date = Date()) throws -> ScheduledReminder {
        let title = try validTitle(title); try validFuture(dueAt, now: now)
        guard items.count < Self.maximumItems else { throw ReminderValidation.full }
        let reminder = ScheduledReminder(id: UUID(), title: title, dueAt: dueAt, createdAt: now, updatedAt: now, state: .scheduled, acknowledgedAt: nil)
        items.append(reminder); return reminder
    }

    @discardableResult
    func update(id: UUID, title: String, dueAt: Date, now: Date = Date()) throws -> ScheduledReminder {
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw ReminderValidation.missing }
        let title = try validTitle(title)
        let reschedule = dueAt != items[index].dueAt || items[index].state == .done
        if reschedule || items[index].state == .scheduled { try validFuture(dueAt, now: now) }
        items[index].title = title; items[index].dueAt = dueAt; items[index].updatedAt = now
        if reschedule { items[index].state = .scheduled; items[index].acknowledgedAt = nil }
        return items[index]
    }

    @discardableResult
    func collectDue(at now: Date = Date()) -> [UUID] {
        var due: [UUID] = []
        for index in items.indices where items[index].state == .scheduled && items[index].dueAt <= now {
            items[index].state = .pending; items[index].acknowledgedAt = nil; items[index].updatedAt = now
            due.append(items[index].id)
        }
        return due
    }

    @discardableResult
    func complete(_ id: UUID, now: Date = Date()) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        items[index].state = .done; items[index].acknowledgedAt = now; items[index].updatedAt = now
        return true
    }

    @discardableResult
    func acknowledge(_ id: UUID, now: Date = Date()) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id && $0.state == .pending }) else { return false }
        items[index].acknowledgedAt = now; items[index].updatedAt = now; return true
    }

    @discardableResult
    func snooze(_ id: UUID, until: Date, now: Date = Date()) throws -> ScheduledReminder {
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw ReminderValidation.missing }
        try validFuture(until, now: now)
        items[index].dueAt = until; items[index].updatedAt = now
        items[index].state = .scheduled; items[index].acknowledgedAt = nil
        return items[index]
    }

    @discardableResult
    func remove(_ id: UUID) -> Bool {
        let count = items.count; items.removeAll { $0.id == id }; return count != items.count
    }
    func saved() -> SavedReminderBook { SavedReminderBook(items: items) }
}

@discardableResult
func runReminderTests() -> Bool {
    var count = 0, failures: [String] = []
    func check(_ value: @autoclosure () -> Bool, _ label: String) { count += 1; if !value() { failures.append(label) } }
    func rejects(_ action: () throws -> Void) -> Bool { do { try action(); return false } catch { return true } }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let book = ReminderBookModel()
    check(rejects { _ = try book.add(title: " \n ", dueAt: now.addingTimeInterval(60), now: now) }, "empty matter rejected")
    check(rejects { _ = try book.add(title: String(repeating: "猫", count: 201), dueAt: now.addingTimeInterval(60), now: now) }, "overlong matter rejected")
    check(rejects { _ = try book.add(title: "浇花", dueAt: now, now: now) }, "past or current time rejected")
    check(rejects { _ = try book.add(title: "浇花", dueAt: Date(timeIntervalSince1970: .infinity), now: now) }, "nonfinite time rejected")
    let first = try! book.add(title: "  给绿植\n浇水  ", dueAt: now.addingTimeInterval(60), now: now)
    check(first.title == "给绿植 浇水" && first.state == .scheduled, "matter normalized and scheduled")
    check(book.collectDue(at: now.addingTimeInterval(59)).isEmpty, "not delivered before chosen time")
    check(book.collectDue(at: now.addingTimeInterval(60)) == [first.id], "fires at exact boundary")
    check(book.pendingCount == 1 && book.item(first.id)?.state == .pending, "delivery keeps item awaiting confirmation")
    check(book.collectDue(at: now.addingTimeInterval(61)).isEmpty, "polling does not repeatedly deliver same item")
    let encoded = try! JSONEncoder().encode(book.saved())
    let restored = ReminderBookModel(saved: try! JSONDecoder().decode(SavedReminderBook.self, from: encoded))
    check(restored.awaiting.first?.id == first.id, "unconfirmed reminder survives app restart")
    check(restored.acknowledge(first.id, now: now.addingTimeInterval(62)) && restored.pendingCount == 0 && restored.item(first.id)?.state == .pending, "later-view acknowledgement is distinct from completion")
    let seen = ReminderBookModel(saved: restored.saved())
    check(seen.pendingCount == 0 && seen.items.count == 1, "acknowledged item does not pop up again on restart")
    _ = try! restored.snooze(first.id, until: now.addingTimeInterval(662), now: now.addingTimeInterval(62))
    check(restored.item(first.id)?.state == .scheduled && restored.item(first.id)?.acknowledgedAt == nil, "snooze makes a fresh pending delivery")
    check(restored.collectDue(at: now.addingTimeInterval(661)).isEmpty && restored.collectDue(at: now.addingTimeInterval(662)) == [first.id], "snoozed reminder fires only at new time")
    check(restored.complete(first.id, now: now.addingTimeInterval(663)) && restored.awaiting.isEmpty, "completed item leaves pending queue")
    check(restored.collectDue(at: now.addingTimeInterval(10000)).isEmpty, "completed item never fires again")
    let overdue = ReminderBookModel()
    let old = try! overdue.add(title: "交报告", dueAt: now.addingTimeInterval(10), now: now)
    let reopened = ReminderBookModel(saved: overdue.saved())
    check(reopened.collectDue(at: now.addingTimeInterval(5000)) == [old.id], "app sleep or downtime catches up overdue reminder")
    _ = try! reopened.update(id: old.id, title: "交修改后的报告", dueAt: old.dueAt, now: now.addingTimeInterval(5001))
    check(reopened.item(old.id)?.state == .pending, "editing overdue text alone retains pending state")
    _ = try! reopened.update(id: old.id, title: "明天交报告", dueAt: now.addingTimeInterval(9000), now: now.addingTimeInterval(5002))
    check(reopened.item(old.id)?.state == .scheduled && reopened.pendingCount == 0, "changing due time reschedules")
    let before = reopened.item(old.id)
    check(rejects { _ = try reopened.update(id: old.id, title: " ", dueAt: now.addingTimeInterval(10000), now: now) } && reopened.item(old.id) == before, "invalid edit is atomic")
    let many = ReminderBookModel()
    let later = try! many.add(title: "晚一点", dueAt: now.addingTimeInterval(30), now: now)
    let sooner = try! many.add(title: "早一点", dueAt: now.addingTimeInterval(20), now: now)
    _ = many.collectDue(at: now.addingTimeInterval(40))
    check(many.awaiting.map(\.id) == [sooner.id, later.id], "simultaneous overdue reminders queued chronologically")
    check(many.remove(sooner.id) && many.item(sooner.id) == nil && !many.remove(sooner.id), "deletion removes only chosen item")
    check(!many.complete(UUID()) && !many.acknowledge(UUID()), "unknown IDs do not alter state")
    let duplicate = ReminderBookModel(saved: SavedReminderBook(items: [first, ScheduledReminder(id: first.id, title: "新版", dueAt: first.dueAt, createdAt: first.createdAt, updatedAt: now.addingTimeInterval(1), state: .scheduled, acknowledgedAt: nil)]))
    check(duplicate.items.count == 1 && duplicate.items.first?.title == "新版", "duplicate IDs keep newest copy")
    let capacity = ReminderBookModel()
    for i in 0..<200 { _ = try! capacity.add(title: "事项\(i)", dueAt: now.addingTimeInterval(Double(i + 1)), now: now) }
    check(rejects { _ = try capacity.add(title: "额外", dueAt: now.addingTimeInterval(999), now: now) } && capacity.items.count == 200, "capacity overflow does not destroy saved items")
    let exact = now.addingTimeInterval(3600)
    let absolute = ReminderBookModel()
    _ = try! absolute.add(title: "按约定时间", dueAt: exact, now: now)
    let roundTrip = ReminderBookModel(saved: try! JSONDecoder().decode(SavedReminderBook.self, from: JSONEncoder().encode(absolute.saved())))
    check(roundTrip.items.first?.dueAt == exact, "absolute due instant survives encoding without timezone drift")
    print("Scheduled reminder tests: \(count - failures.count)/\(count) passed")
    failures.forEach { print("FAIL: \($0)") }; return failures.isEmpty
}
