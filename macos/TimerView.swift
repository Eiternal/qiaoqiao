import AppKit

private final class TimerCanvas: NSView { override var isFlipped: Bool { true } }
private func timerLabel(_ value: String, _ size: CGFloat = 12) -> NSTextField {
    let v = NSTextField(labelWithString: value); v.font = .systemFont(ofSize: size); v.textColor = OutfitRenderer.ink; return v
}

final class TimerCenterView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    let book: TimerBookModel
    let mode = NSSegmentedControl(labels: ["下班倒计时", "自由倒计时", "番茄钟"], trackingMode: .selectOne, target: nil, action: nil)
    let workTime = NSDatePicker()
    let repeats = NSButton(checkboxWithTitle: "之后在工作日重复（周一至周五）", target: nil, action: nil)
    let titleField = NSTextField()
    let hours = NSTextField(string: "0"), minutes = NSTextField(string: "20"), seconds = NSTextField(string: "0")
    let focus = NSTextField(string: "25"), shortBreak = NSTextField(string: "5"), longBreak = NSTextField(string: "15"), rounds = NSTextField(string: "4")
    let table = NSTableView()
    let message = timerLabel("")
    let badgeCheck = NSButton(checkboxWithTitle: "在头像下显示选中的计时（仅图标＋时间）", target: nil, action: nil)
    let pauseButton = NSButton(title: "暂停", target: nil, action: nil)
    let advanceButton = NSButton(title: "下一阶段", target: nil, action: nil)
    let displayButton = NSButton(title: "显示这个", target: nil, action: nil)
    let stopButton = NSButton(title: "结束计时", target: nil, action: nil)
    let deleteButton = NSButton(title: "删除", target: nil, action: nil)
    var onChange: ((String) -> Void)?
    private let forms = [TimerCanvas(), TimerCanvas(), TimerCanvas()]
    private var rows: [DeskTimer] = []
    private var refreshing = false
    override var isFlipped: Bool { true }
    init(book: TimerBookModel, size: NSSize) {
        self.book = book; super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true; layer?.backgroundColor = OutfitRenderer.color(0xFFFAF2).cgColor
        func label(_ value: String, _ rect: NSRect, _ parent: NSView? = nil, size: CGFloat = 12) {
            let v = timerLabel(value, size); v.frame = rect; (parent ?? self).addSubview(v)
        }
        func field(_ v: NSTextField, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ parent: NSView) {
            v.frame = NSRect(x: x, y: y, width: w, height: 26); parent.addSubview(v)
            if v !== titleField { let f = NumberFormatter(); f.numberStyle = .decimal; f.minimum = 0; f.maximumFractionDigits = 0; f.isLenient = false; v.formatter = f }
        }
        label("小计时器", NSRect(x: 24, y: 18, width: 300, height: 30), size: 22)
        label("给工作收个尾，也给自己留点喘气的时间。", NSRect(x: 25, y: 51, width: 600, height: 20))
        mode.frame = NSRect(x: 24, y: 82, width: size.width - 48, height: 28); mode.selectedSegment = 0
        mode.target = self; mode.action = #selector(changeTimerMode); addSubview(mode)
        for form in forms { form.frame = NSRect(x: 24, y: 123, width: size.width - 48, height: 145); addSubview(form) }
        let work = forms[0]
        label("下班时间", NSRect(x: 0, y: 6, width: 76, height: 20), work)
        workTime.frame = NSRect(x: 82, y: 0, width: 270, height: 30)
        workTime.datePickerStyle = .textFieldAndStepper; workTime.datePickerElements = [.yearMonthDay, .hourMinute]
        let now = Date(), cal = Calendar.autoupdatingCurrent
        let today = cal.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now.addingTimeInterval(3600)
        workTime.dateValue = today > now ? today : (cal.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(3600)); work.addSubview(workTime)
        repeats.frame = NSRect(x: 82, y: 44, width: 420, height: 24); work.addSubview(repeats)
        label("可选具体日期，跨夜下班也可以。首次时间以你的选择为准。", NSRect(x: 0, y: 83, width: 600, height: 20), work)
        let custom = forms[1]
        label("事项", NSRect(x: 0, y: 7, width: 70, height: 20), custom)
        titleField.placeholderString = "喝水、煮面、离开屏幕…"; field(titleField, 72, 0, 400, custom)
        label("时长", NSRect(x: 0, y: 50, width: 70, height: 20), custom)
        for (v, x, unit) in [(hours, 72.0, "时"), (minutes, 177.0, "分"), (seconds, 282.0, "秒")] {
            field(v, x, 43, 57, custom); label(unit, NSRect(x: x + 64, y: 50, width: 30, height: 20), custom)
        }
        label("1 秒到 7 天，可同时开多个；在下方选择显示哪一个。", NSRect(x: 0, y: 83, width: 600, height: 20), custom)
        let pomo = forms[2]
        for (v, x, name) in [(focus, 0.0, "专注"), (shortBreak, 196.0, "短休息"), (longBreak, 400.0, "长休息")] {
            label(name, NSRect(x: x, y: 7, width: 62, height: 20), pomo); field(v, x + 65, 0, 53, pomo)
            label("分钟", NSRect(x: x + 125, y: 7, width: 40, height: 20), pomo)
        }
        label("每", NSRect(x: 0, y: 50, width: 30, height: 20), pomo); field(rounds, 35, 43, 53, pomo)
        label("轮专注后长休息", NSRect(x: 97, y: 50, width: 200, height: 20), pomo)
        label("到点由我提醒，点击后再进入下一段。番茄钟期间不重复提醒工作休息。", NSRect(x: 0, y: 83, width: 660, height: 20), pomo)
        for form in forms {
            let start = NSButton(title: "开始计时", target: self, action: #selector(startTimer)); start.bezelStyle = .rounded
            start.frame = NSRect(x: size.width - 187, y: 111, width: 138, height: 30); form.addSubview(start)
        }
        message.frame = NSRect(x: 24, y: 276, width: size.width - 48, height: 22); message.textColor = OutfitRenderer.color(0x9B738A); addSubview(message)
        badgeCheck.frame = NSRect(x: 24, y: 303, width: size.width - 48, height: 24); badgeCheck.target = self; badgeCheck.action = #selector(toggleBadge); addSubview(badgeCheck)
        let scroll = NSScrollView(frame: NSRect(x: 24, y: 341, width: size.width - 48, height: size.height - 417))
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        for (id, title, width) in [("title", "事项", 220.0), ("remaining", "剩余", 110.0), ("state", "状态", 270.0)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); c.title = title; c.width = width; table.addTableColumn(c)
        }
        table.dataSource = self; table.delegate = self; table.rowHeight = 31; table.allowsEmptySelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle; scroll.documentView = table; addSubview(scroll)
        let controls: [(NSButton, Selector, CGFloat, CGFloat)] = [
            (displayButton, #selector(selectDisplay), 24, 96),
            (pauseButton, #selector(pauseTimer), 130, 85), (advanceButton, #selector(advanceTimer), 225, 155),
            (stopButton, #selector(stopTimer), 390, 105),
            (deleteButton, #selector(deleteTimer), 505, 85)]
        for (button, action, x, width) in controls { button.target = self; button.action = action; button.bezelStyle = .rounded; button.frame = NSRect(x: x, y: size.height - 57, width: width, height: 30); addSubview(button) }
        changeTimerMode(); refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func changeTimerMode() { for (i, form) in forms.enumerated() { form.isHidden = i != mode.selectedSegment } }
    private var selected: DeskTimer? { rows.indices.contains(table.selectedRow) ? rows[table.selectedRow] : nil }
    func refresh() {
        let id = selected?.id ?? book.selectedID
        refreshing = true; rows = book.items; table.reloadData()
        if let index = rows.firstIndex(where: { $0.id == id }) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        else if !rows.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        badgeCheck.state = book.showBadge ? .on : .off; refreshing = false; updateButtons()
    }
    private func updateButtons() {
        pauseButton.isEnabled = selected?.canPause == true; pauseButton.title = selected?.state == .paused ? "继续" : "暂停"
        advanceButton.isEnabled = selected?.state == .awaiting; advanceButton.title = selected?.state == .awaiting ? (selected?.advanceTitle ?? "下一阶段") : "下一阶段"
        displayButton.isEnabled = selected?.active == true; stopButton.isEnabled = selected?.active == true; deleteButton.isEnabled = selected != nil
    }
    private func changed(_ text: String) { message.stringValue = text; refresh(); onChange?(text) }
    @objc private func startTimer() {
        window?.makeFirstResponder(nil)
        do {
            if mode.selectedSegment == 0 { try book.workday(until: workTime.dateValue, repeatWeekdays: repeats.state == .on, at: Date()) }
            else if mode.selectedSegment == 1 {
                guard (0...168).contains(hours.integerValue), (0...59).contains(minutes.integerValue), (0...59).contains(seconds.integerValue) else { throw TimerIssue.invalid }
                try book.countdown(title: titleField.stringValue, seconds: Double(hours.integerValue * 3600 + minutes.integerValue * 60 + seconds.integerValue), at: Date())
            } else { try book.pomodoro(focus: focus.doubleValue * 60, short: shortBreak.doubleValue * 60, long: longBreak.doubleValue * 60, rounds: rounds.integerValue, at: Date()) }
            changed("开始啦，到点我叫你。")
        } catch { message.stringValue = error.localizedDescription }
    }
    @objc private func toggleBadge() { book.showBadge = badgeCheck.state == .on; changed("计时显示记住啦。") }
    @objc private func selectDisplay() { guard let t = selected else { return }; book.selectedID = t.id; book.showBadge = true; changed("这一项交给我盯着。") }
    @objc private func pauseTimer() { guard let t = selected else { return }; if book.pause(t.id, at: Date()) { changed(t.state == .paused ? "继续啦。" : "暂停一下，等你回来。") } }
    @objc private func advanceTimer() { guard let t = selected else { return }; if book.advance(t.id, at: Date()) { changed(t.kind == .pomodoro ? "准备好啦，下一段开始。" : "辛苦啦，记好啦。") } }
    @objc private func stopTimer() { guard let t = selected else { return }; if book.stop(t.id) { changed("这一项先收起来啦。") } }
    @objc private func deleteTimer() { guard let t = selected else { return }; book.remove(t.id); changed("已经划掉啦。") }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableViewSelectionDidChange(_ notification: Notification) { if !refreshing { updateButtons() } }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let t = rows[row], id = tableColumn?.identifier.rawValue ?? ""
        let value: String
        if id == "title" { value = (book.display?.id == t.id ? "● " : "") + t.title }
        else if id == "remaining" { value = DeskTimer.timeText(t.seconds(at: Date())) }
        else { value = t.state == .awaiting ? "到时间啦 · 等你确认" : (t.state == .finished ? "已结束" : (t.state == .paused ? "已暂停" : t.phaseTitle + (t.kind == .pomodoro ? " · 已完成 \(t.completedFocus) 轮" : ""))) }
        let label = timerLabel(value); label.lineBreakMode = .byTruncatingTail; return label
    }
}

final class TimerWindowController: NSWindowController, NSWindowDelegate {
    let editor: TimerCenterView
    var onClose: (() -> Void)?
    init(book: TimerBookModel, onChange: @escaping (String) -> Void) {
        // A scrollable content view keeps every control reachable on small screens.
        let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(width: min(760, max(600, area.width - 48)), height: min(660, max(360, area.height - 72)))
        editor = TimerCenterView(book: book, size: NSSize(width: 716, height: 640))
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: size)); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.documentView = editor
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window); window.title = "敲敲 · 小计时器"; window.contentView = scroll
        window.isReleasedWhenClosed = false; window.delegate = self; window.center(); editor.onChange = onChange
    }
    required init?(coder: NSCoder) { fatalError() }
    func windowWillClose(_ notification: Notification) { onClose?() }
}
