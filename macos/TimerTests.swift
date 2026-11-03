import AppKit

func runTimerTests() -> Bool {
    var n = 0, failures: [String] = []
    func check(_ ok: Bool, _ label: String) { n += 1; if !ok { failures.append(label) } }
    func rejects(_ action: () throws -> Void) -> Bool { do { try action(); return false } catch { return true } }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let b = TimerBookModel()
    let id = try! b.countdown(title: "喝水", seconds: 61, at: now)
    check(b.display?.id == id && b.display?.seconds(at: now.addingTimeInterval(1)) == 60, "deadline derives remaining independently of callbacks")
    check(DeskTimer.timeText(60.1) == "01:01" && DeskTimer.timeText(3661) == "01:01:01", "readable ceil-to-second formatting")
    check(b.pause(id, at: now.addingTimeInterval(10)) && b.display?.seconds(at: now.addingTimeInterval(9000)) == 51, "pause freezes remaining time")
    let paused = TimerBookModel(saved: try! JSONDecoder().decode(SavedTimerBook.self, from: JSONEncoder().encode(b.saved())))
    check(paused.display?.state == .paused && paused.display?.remaining == 51, "pause survives restart")
    check(paused.pause(id, at: now.addingTimeInterval(100)), "resume restarts deadline from remaining")
    check(!paused.tick(at: now.addingTimeInterval(150.9)), "no early expiration")
    check(paused.tick(at: now.addingTimeInterval(151)) && paused.pending.count == 1, "expiration exactly on deadline")
    check(!paused.tick(at: now.addingTimeInterval(9999)), "expiration delivered only once")
    paused.acknowledge(id)
    check(paused.pending.isEmpty && paused.display?.state == .awaiting, "later hides alert without losing pending item")
    check(paused.restart(id, at: now) && paused.display?.seconds(at: now) == 61, "repeat same countdown")
    _ = paused.tick(at: now.addingTimeInterval(62)); _ = paused.advance(id, at: now.addingTimeInterval(63))
    check(paused.display == nil && paused.items.first?.state == .finished, "acknowledging finished countdown hides badge")
    check(rejects { _ = try b.countdown(title: "bad", seconds: 0, at: now) } && rejects { _ = try b.countdown(title: "bad", seconds: .infinity, at: now) }, "invalid duration rejected")
    check(rejects { _ = try b.countdown(title: String(repeating: "字", count: 41), seconds: 1, at: now) }, "bounded timer title")
    let two = try! b.countdown(title: "煮面", seconds: 20, at: now)
    check(b.items.count == 2 && b.display?.id == two, "multiple countdowns and selected badge")
    b.showBadge = false; check(b.display == nil && b.items.count == 2, "hiding badge keeps timers running")
    b.showBadge = true; b.remove(two); check(b.display?.id == id, "deleting selection falls back to active timer")
    _ = b.pause(id, at: now)
    let resumed = TimerBookModel(saved: b.saved()); _ = resumed.tick(at: now.addingTimeInterval(7200))
    check(resumed.pending.count == 1, "app sleep/restart catches overdue timer")
    let pomo = TimerBookModel(); let pid = try! pomo.pomodoro(focus: 60, short: 60, long: 120, rounds: 2, at: now)
    check(rejects { _ = try pomo.pomodoro(at: now) }, "one active Pomodoro prevents accidental replacement")
    _ = pomo.tick(at: now.addingTimeInterval(100000))
    check(pomo.display?.completedFocus == 1 && pomo.display?.phase == .focus && pomo.display?.state == .awaiting, "long absence never invents completed rounds")
    _ = pomo.advance(pid, at: now); check(pomo.display?.phase == .shortBreak && pomo.display?.duration == 60, "focus advances to short break on confirmation")
    _ = pomo.tick(at: now.addingTimeInterval(60)); _ = pomo.advance(pid, at: now.addingTimeInterval(60))
    check(pomo.display?.phase == .focus && pomo.display?.completedFocus == 1, "break does not increment completed focus")
    _ = pomo.tick(at: now.addingTimeInterval(120)); _ = pomo.advance(pid, at: now.addingTimeInterval(120))
    check(pomo.display?.phase == .longBreak && pomo.display?.duration == 120, "configured round count selects long break")
    _ = pomo.tick(at: now.addingTimeInterval(240)); _ = pomo.advance(pid, at: now.addingTimeInterval(240))
    check(pomo.display?.phase == .focus && pomo.display?.completedFocus == 2, "long break returns to next focus")
    check(pomo.stop(pid) && pomo.display == nil, "stop ends the whole Pomodoro")
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let friday = cal.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 17))!
    let w = TimerBookModel(); let wid = try! w.workday(until: friday.addingTimeInterval(3600), repeatWeekdays: true, at: friday, calendar: cal)
    check(!w.pause(wid, at: friday), "fixed departure time cannot be shifted by pause")
    _ = w.tick(at: friday.addingTimeInterval(3600)); _ = w.advance(wid, at: friday.addingTimeInterval(3601), calendar: cal)
    let monday = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 18))!
    check(w.display?.deadline == monday, "weekday recurrence skips the weekend")
    check(rejects { _ = try TimerBookModel().workday(until: friday, repeatWeekdays: false, at: friday) }, "past departure time rejected")
    let cap = TimerBookModel(); for _ in 0..<20 { try! cap.countdown(title: "", seconds: 1, at: now) }
    check(rejects { _ = try cap.countdown(title: "", seconds: 1, at: now) } && cap.items.count == 20, "bounded list never destroys existing timers")
    let tiny = CGRect(x: 0, y: 0, width: 200, height: 160)
    let frame = ScreenSizing.frame(from: .zero, in: tiny, preference: 1.8, contentSize: NSSize(width: 264, height: 274))
    check(tiny.contains(frame) && abs(frame.width / frame.height - 264.0 / 274) < 0.0001, "expanded timer badge fits small displays without distortion")
    print("Timer tests: \(n - failures.count)/\(n) passed"); failures.forEach { print("FAIL: \($0)") }; return failures.isEmpty
}

func runTimerPresentationTests() -> Bool {
    let now = Date(), book = TimerBookModel()
    try! book.countdown(title: "喝水", seconds: 1234, at: now)
    let editor = TimerCenterView(book: book, size: NSSize(width: 716, height: 640))
    let host = NSWindow(contentRect: editor.bounds, styleMask: .borderless, backing: .buffered, defer: false); host.contentView = editor
    let model = CounterModel(now: now), pet = PetView(model: model)
    pet.demo = true; pet.now = now; pet.timerDisplay = book.display; pet.setFrameSize(pet.logicalSize); pet.bounds.size = pet.logicalSize
    let window = NSWindow(contentRect: pet.bounds, styleMask: .borderless, backing: .buffered, defer: false); window.contentView = pet
    var opened = 0; pet.onTimers = { opened += 1 }
    let location = pet.convert(NSPoint(x: 132, y: 250), to: nil)
    let event = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    pet.mouseDown(with: event)
    let before = book.display?.state; editor.pauseButton.performClick(nil)
    let paused = book.display?.state; editor.pauseButton.performClick(nil)
    let presenter = ScheduledReminderPresenter()
    let result = [opened == 1 && !pet.isInteracting, pet.logicalSize.height == 274, model.todayCount == 0, editor.table.numberOfRows == 1, before == .running && paused == .paused && book.display?.state == .running, !presenter.panel.canBecomeKey && !presenter.panel.canBecomeMain]
    print("Timer presentation tests: \(result.filter { $0 }.count)/\(result.count) passed"); return result.allSatisfy { $0 }
}

func exportTimerPreviews(to directory: String) throws {
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let now = Date(), book = TimerBookModel()
    try book.workday(until: now.addingTimeInterval(3661), repeatWeekdays: true, at: now)
    try book.countdown(title: "喝口水", seconds: 180, at: now)
    try book.pomodoro(at: now)
    let view = TimerCenterView(book: book, size: NSSize(width: 716, height: 640))
    let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false); window.contentView = view
    renderPreview(view, to: directory + "/计时中心.png")
    view.mode.selectedSegment = 2; view.mode.sendAction(view.mode.action, to: view.mode.target)
    renderPreview(view, to: directory + "/番茄钟设置.png")
    let pet = previewScene("安静", now: now); pet.timerDisplay = book.display; pet.frame.size = pet.logicalSize; pet.bounds.size = pet.logicalSize
    let petWindow = NSWindow(contentRect: pet.bounds, styleMask: .borderless, backing: .buffered, defer: false); petWindow.contentView = pet
    renderPreview(pet, to: directory + "/桌宠倒计时.png")
    _ = book.tick(at: now.addingTimeInterval(1501))
    let t = book.items.first { $0.kind == .pomodoro }!
    let item = ScheduledReminder(id: t.id, title: t.completionText, dueAt: now, createdAt: now, updatedAt: now, state: .pending, acknowledgedAt: nil)
    let balloon = ScheduledReminderBalloonView(item: item, count: 1, size: NSSize(width: 340, height: 170), tailAtTop: false, buttonTitles: [t.advanceTitle, "稍后查看", "结束番茄"])
    let alert = NSWindow(contentRect: balloon.bounds, styleMask: .borderless, backing: .buffered, defer: false); alert.contentView = balloon
    renderPreview(balloon, to: directory + "/番茄钟到点.png")
    print("Timer previews exported to \(directory)")
}
