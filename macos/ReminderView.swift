import AppKit

enum ReminderMutation { case saved, edited, completed, snoozed, acknowledged, deleted }

private class ReminderCanvas: NSView {
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private func reminderLabel(_ title: String, font: CGFloat = 12, color: NSColor = .labelColor) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: font); label.textColor = color
    return label
}

func reminderDateText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent; formatter.timeZone = .autoupdatingCurrent
    formatter.dateStyle = .short; formatter.timeStyle = .medium
    return formatter.string(from: date)
}

final class ReminderBookView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    let book: ReminderBookModel
    let titleField = NSTextField()
    let timePicker = NSDatePicker()
    let statusLabel = reminderLabel("", color: .secondaryLabelColor)
    let countLabel = reminderLabel("", color: OutfitRenderer.color(0xA08AA9))
    let saveButton = NSButton(title: "添加提醒", target: nil, action: nil)
    let doneButton = NSButton(title: "完成", target: nil, action: nil)
    let laterButton = NSButton(title: "10 分钟后", target: nil, action: nil)
    let deleteButton = NSButton(title: "删除", target: nil, action: nil)
    let table = NSTableView()
    var onMutation: ((ReminderMutation) -> Void)?
    private var rows: [ScheduledReminder] = []
    private var editingID: UUID?
    private var refreshing = false
    override var isFlipped: Bool { true }

    init(book: ReminderBookModel, size: NSSize) {
        self.book = book
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true; layer?.backgroundColor = OutfitRenderer.color(0xFFFCF8).cgColor
        let heading = reminderLabel("小提醒本", font: 22)
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        heading.frame = NSRect(x: 22, y: 17, width: 200, height: 31); addSubview(heading)
        countLabel.frame = NSRect(x: size.width - 230, y: 25, width: 205, height: 19)
        countLabel.alignment = .right; addSubview(countLabel)
        let matterLabel = reminderLabel("事项")
        matterLabel.frame = NSRect(x: 23, y: 68, width: 48, height: 20); addSubview(matterLabel)
        titleField.frame = NSRect(x: 77, y: 61, width: size.width - 101, height: 30)
        titleField.placeholderString = "比如：给绿植浇水、带上雨伞…"
        titleField.font = .systemFont(ofSize: 13)
        titleField.setAccessibilityLabel("提醒事项")
        addSubview(titleField)
        let whenLabel = reminderLabel("时间")
        whenLabel.frame = NSRect(x: 23, y: 112, width: 48, height: 20); addSubview(whenLabel)
        timePicker.frame = NSRect(x: 77, y: 103, width: min(360, size.width - 102), height: 30)
        timePicker.datePickerStyle = .textFieldAndStepper
        timePicker.datePickerElements = [.yearMonthDay, .hourMinuteSecond]
        timePicker.timeZone = .autoupdatingCurrent; timePicker.locale = .autoupdatingCurrent
        timePicker.setAccessibilityLabel("提醒日期与时间")
        addSubview(timePicker)
        for (index, minutes) in [1, 5, 30].enumerated() {
            let button = NSButton(title: "\(minutes) 分钟后", target: self, action: #selector(quickTime(_:)))
            button.tag = minutes; button.bezelStyle = .rounded; button.font = .systemFont(ofSize: 11)
            button.frame = NSRect(x: 77 + index * 88, y: 146, width: 83, height: 27); addSubview(button)
        }
        saveButton.target = self; saveButton.action = #selector(saveReminder)
        saveButton.bezelStyle = .rounded; saveButton.keyEquivalent = "\r"
        saveButton.frame = NSRect(x: size.width - 135, y: 143, width: 111, height: 31); addSubview(saveButton)
        statusLabel.frame = NSRect(x: 23, y: 183, width: size.width - 46, height: 20); addSubview(statusLabel)
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 214, width: size.width - 40, height: size.height - 276))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .bezelBorder
        table.frame = NSRect(origin: .zero, size: scroll.contentSize)
        for (name, title, width) in [("matter", "事项", size.width - 330), ("time", "提醒时间", CGFloat(194)), ("state", "状态", CGFloat(85))] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(name))
            column.title = title; column.width = width; table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.rowHeight = 34; table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false; table.delegate = self; table.dataSource = self
        table.setAccessibilityLabel("已保存的提醒")
        scroll.documentView = table; addSubview(scroll)
        let new = NSButton(title: "新建", target: self, action: #selector(newEditor))
        new.bezelStyle = .rounded; new.frame = NSRect(x: 20, y: size.height - 45, width: 75, height: 29); addSubview(new)
        for (button, x, width, action) in [(doneButton, CGFloat(104), CGFloat(75), #selector(completeSelected)), (laterButton, CGFloat(187), CGFloat(115), #selector(snoozeSelected)), (deleteButton, size.width - 105, CGFloat(85), #selector(deleteSelected))] {
            button.frame = NSRect(x: x, y: size.height - 45, width: width, height: 29)
            button.target = self; button.action = action; button.bezelStyle = .rounded; addSubview(button)
        }
        newEditor(); refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func refresh() {
        refreshing = true
        rows = book.sortedItems; table.reloadData()
        if let id = editingID, let row = rows.firstIndex(where: { $0.id == id }) { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        else { table.deselectAll(nil); if editingID != nil { editingID = nil } }
        countLabel.stringValue = "\(book.items.count) 条事项 · \(book.pendingCount) 条待确认"
        refreshing = false; updateButtons()
    }
    func selectReminder(_ id: UUID) {
        guard let row = rows.firstIndex(where: { $0.id == id }) else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row); loadSelected()
    }
    private func updateButtons() {
        let item = editingID.flatMap { book.item($0) }
        doneButton.isEnabled = item != nil && item?.state != .done
        laterButton.isEnabled = item != nil; deleteButton.isEnabled = item != nil
        saveButton.title = item == nil ? "添加提醒" : (item?.state == .done ? "重新安排" : "保存修改")
    }
    private func loadSelected() {
        guard table.selectedRow >= 0, table.selectedRow < rows.count else { updateButtons(); return }
        let item = rows[table.selectedRow]
        editingID = item.id; titleField.stringValue = item.title; timePicker.dateValue = item.dueAt
        statusLabel.stringValue = item.state == .pending ? (item.acknowledgedAt == nil ? "这条提醒已到时间，等待确认。" : "已经提醒过，可以完成或重新安排。") : "正在查看这条提醒。"
        statusLabel.textColor = .secondaryLabelColor; updateButtons()
    }
    @objc func newEditor() {
        refreshing = true; table.deselectAll(nil); refreshing = false
        editingID = nil; titleField.stringValue = ""; timePicker.dateValue = Date().addingTimeInterval(600)
        statusLabel.stringValue = "写下事项，再选一个日期和时间。"; statusLabel.textColor = .secondaryLabelColor
        updateButtons()
    }
    @objc private func quickTime(_ sender: NSButton) {
        timePicker.dateValue = Date().addingTimeInterval(Double(sender.tag * 60))
        statusLabel.stringValue = "时间选好了，记得保存。"; statusLabel.textColor = .secondaryLabelColor
    }
    @objc private func saveReminder() {
        window?.makeFirstResponder(nil)
        do {
            let item: ScheduledReminder
            let editing = editingID != nil
            if let id = editingID { item = try book.update(id: id, title: titleField.stringValue, dueAt: timePicker.dateValue) }
            else { item = try book.add(title: titleField.stringValue, dueAt: timePicker.dateValue) }
            editingID = item.id; refresh()
            statusLabel.stringValue = "已记好：\(reminderDateText(item.dueAt))"
            statusLabel.textColor = OutfitRenderer.color(0x6C987B)
            onMutation?(editing ? .edited : .saved)
        } catch { statusLabel.stringValue = error.localizedDescription; statusLabel.textColor = .systemRed }
    }
    @objc private func completeSelected() {
        guard let id = editingID, book.complete(id) else { return }
        refresh(); loadSelected(); onMutation?(.completed)
    }
    @objc private func snoozeSelected() {
        guard let id = editingID else { return }
        do {
            _ = try book.snooze(id, until: Date().addingTimeInterval(600))
            refresh(); loadSelected(); onMutation?(.snoozed)
        } catch { statusLabel.stringValue = error.localizedDescription; statusLabel.textColor = .systemRed }
    }
    @objc private func deleteSelected() {
        guard let id = editingID, let item = book.item(id) else { return }
        let alert = NSAlert(); alert.messageText = "删除这条提醒？"; alert.informativeText = item.title
        alert.addButton(withTitle: "删除"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { statusLabel.stringValue = "已保留这条提醒。"; return }
        _ = book.remove(id); editingID = nil; refresh(); newEditor(); onMutation?(.deleted)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableViewSelectionDidChange(_ notification: Notification) { if !refreshing { loadSelected() } }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count, let column = tableColumn else { return nil }
        let id = column.identifier
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? NSTableCellView(frame: NSRect(x: 0, y: 0, width: column.width, height: 34))
        cell.identifier = id
        if cell.textField == nil {
            let text = reminderLabel(""); text.frame = NSRect(x: 8, y: 8, width: column.width - 16, height: 19)
            text.autoresizingMask = [.width]; text.lineBreakMode = .byTruncatingTail
            cell.addSubview(text); cell.textField = text
        }
        let item = rows[row]
        switch id.rawValue {
        case "matter": cell.textField?.stringValue = item.title
        case "time": cell.textField?.stringValue = reminderDateText(item.dueAt)
        default: cell.textField?.stringValue = item.state == .scheduled ? "未到时" : (item.state == .done ? "已完成" : (item.acknowledgedAt == nil ? "待确认" : "已提醒"))
        }
        cell.textField?.textColor = item.state == .done ? .secondaryLabelColor : (item.state == .pending && item.acknowledgedAt == nil ? OutfitRenderer.color(0xBA7B86) : .labelColor)
        return cell
    }
}

final class ReminderWindowController: NSWindowController, NSWindowDelegate {
    let editor: ReminderBookView
    var onClose: (() -> Void)?
    init(book: ReminderBookModel, onMutation: @escaping (ReminderMutation) -> Void) {
        let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(width: min(760, max(600, area.width * 0.88)), height: min(610, max(430, area.height * 0.85)))
        editor = ReminderBookView(book: book, size: size)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        editor.onMutation = onMutation
        window.title = "敲敲 · 小提醒本"; window.contentView = editor; window.isReleasedWhenClosed = false
        window.delegate = self; window.acceptsMouseMovedEvents = true; window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func refresh() { editor.refresh() }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

final class ScheduledReminderBalloonView: NSView {
    let item: ScheduledReminder
    let tailAtTop: Bool
    let messageLabel: NSTextField
    var onComplete: (() -> Void)?
    var onSnooze: (() -> Void)?
    var onLater: (() -> Void)?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    static func preferredSize(for title: String, maxWidth: CGFloat, maxHeight: CGFloat) -> NSSize {
        let width = min(340, maxWidth)
        let textHeight = (title as NSString).boundingRect(with: NSSize(width: width - 40, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium)]).height
        return NSSize(width: width, height: min(maxHeight, max(156, ceil(textHeight) + 126)))
    }
    init(item: ScheduledReminder, count: Int, size: NSSize, tailAtTop: Bool, buttonTitles: [String] = ["完成", "10 分钟后", "稍后查看"]) {
        self.item = item; self.tailAtTop = tailAtTop
        messageLabel = NSTextField(wrappingLabelWithString: item.title)
        super.init(frame: NSRect(origin: .zero, size: size))
        let top: CGFloat = tailAtTop ? 24 : 14
        let heading = reminderLabel("到时间啦", font: 13, color: OutfitRenderer.color(0x9B7FA7))
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.frame = NSRect(x: 20, y: top, width: size.width - 40, height: 20); addSubview(heading)
        let date = reminderLabel(reminderDateText(item.dueAt) + (count > 1 ? " · 还有 \(count - 1) 条" : ""), font: 10, color: .secondaryLabelColor)
        date.frame = NSRect(x: 20, y: top + 23, width: size.width - 40, height: 17); addSubview(date)
        let buttonY = size.height - (tailAtTop ? 45 : 55)
        let scrollRect = NSRect(x: 20, y: top + 46, width: size.width - 40, height: max(20, buttonY - top - 58))
        let scroll = NSScrollView(frame: scrollRect)
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let fullHeight = ceil((item.title as NSString).boundingRect(with: NSSize(width: scrollRect.width, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium)]).height) + 8
        let document = ReminderCanvas(frame: NSRect(x: 0, y: 0, width: scrollRect.width, height: max(fullHeight, scrollRect.height)))
        messageLabel.font = .systemFont(ofSize: 14, weight: .medium); messageLabel.textColor = OutfitRenderer.ink
        messageLabel.maximumNumberOfLines = 0; messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.frame = NSRect(x: 0, y: 0, width: scrollRect.width, height: fullHeight)
        messageLabel.setAccessibilityLabel("提醒事项：" + item.title)
        document.addSubview(messageLabel); scroll.documentView = document; addSubview(scroll)
        let width = (size.width - 56) / 3
        for (index, title, action) in [(0, buttonTitles[0], #selector(completeReminder)), (1, buttonTitles[1], #selector(snooze)), (2, buttonTitles[2], #selector(later))] {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded; button.font = .systemFont(ofSize: size.width < 270 ? 10 : 12)
            button.frame = NSRect(x: 20 + CGFloat(index) * (width + 8), y: buttonY, width: width, height: 28)
            addSubview(button)
        }
        setAccessibilityLabel("定时提醒：" + item.title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ dirtyRect: NSRect) {
        let body = NSRect(x: 1, y: tailAtTop ? 12 : 1, width: bounds.width - 2, height: bounds.height - 14)
        let path = NSBezierPath(roundedRect: body, xRadius: 17, yRadius: 17)
        OutfitRenderer.color(0xFFFCF7).setFill(); path.fill()
        OutfitRenderer.color(0xD9C9D5).setStroke(); path.lineWidth = 1.2; path.stroke()
        let tip = NSBezierPath(), x = bounds.midX
        tip.move(to: NSPoint(x: x - 10, y: tailAtTop ? 13 : bounds.height - 14))
        tip.line(to: NSPoint(x: x, y: tailAtTop ? 1 : bounds.height - 1))
        tip.line(to: NSPoint(x: x + 10, y: tailAtTop ? 13 : bounds.height - 14)); tip.close()
        OutfitRenderer.color(0xFFFCF7).setFill(); tip.fill()
    }
    @objc private func completeReminder() { onComplete?() }
    @objc private func snooze() { onSnooze?() }
    @objc private func later() { onLater?() }
}

final class ScheduledReminderPresenter {
    let panel: CompanionPanel
    private(set) var itemID: UUID?
    var onComplete: ((UUID) -> Void)?
    var onSnooze: ((UUID) -> Void)?
    var onLater: ((UUID) -> Void)?
    private var item: ScheduledReminder?
    private var count = 0
    private var buttonTitles = ["完成", "10 分钟后", "稍后查看"]
    init() {
        panel = CompanionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "敲敲 · 定时提醒"; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.hasShadow = true; panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false; panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
    func show(_ item: ScheduledReminder, count: Int, near pet: NSRect, buttonTitles: [String] = ["完成", "10 分钟后", "稍后查看"]) {
        self.item = item; itemID = item.id; self.count = count
        self.buttonTitles = buttonTitles
        reposition(near: pet); panel.orderFrontRegardless()
    }
    func reposition(near pet: NSRect) {
        guard let item = item else { return }
        let screens = NSScreen.screens
        guard let index = ScreenSizing.screenIndex(for: pet, screens: screens.map(\.frame)) else { return }
        let area = screens[index].visibleFrame
        let size = ScheduledReminderBalloonView.preferredSize(for: item.title, maxWidth: max(160, area.width - 20), maxHeight: max(130, area.height - 20))
        let scale = pet.width / ScreenSizing.baseSize.width
        let above = pet.maxY - 49 * scale + 8
        let useAbove = above + size.height <= area.maxY - 8
        var y = useAbove ? above : pet.minY - size.height - 8
        y = min(max(y, area.minY + 8), max(area.minY + 8, area.maxY - size.height - 8))
        let x = min(max(pet.midX - size.width / 2, area.minX + 8), max(area.minX + 8, area.maxX - size.width - 8))
        let view = ScheduledReminderBalloonView(item: item, count: count, size: size, tailAtTop: !useAbove, buttonTitles: buttonTitles)
        view.onComplete = { [weak self] in self?.onComplete?(item.id) }
        view.onSnooze = { [weak self] in self?.onSnooze?(item.id) }
        view.onLater = { [weak self] in self?.onLater?(item.id) }
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: false)
        panel.contentView = view
    }
    func hide() { panel.orderOut(nil); item = nil; itemID = nil }
}

@discardableResult
func runReminderPresentationTests() -> Bool {
    let now = Date(), book = ReminderBookModel()
    let title = String(repeating: "这是一条需要完整显示的提醒事项", count: 10)
    let item = try! book.add(title: title, dueAt: now.addingTimeInterval(600), now: now)
    let size = ScheduledReminderBalloonView.preferredSize(for: title, maxWidth: 340, maxHeight: 300)
    let balloon = ScheduledReminderBalloonView(item: item, count: 2, size: size, tailAtTop: false)
    let editor = ReminderBookView(book: book, size: NSSize(width: 760, height: 560))
    editor.selectReminder(item.id)
    let presenter = ScheduledReminderPresenter()
    let results = [balloon.messageLabel.stringValue == title, balloon.messageLabel.maximumNumberOfLines == 0, size.width <= 340 && size.height <= 300, balloon.subviews.compactMap { $0 as? NSButton }.count == 3, editor.titleField.stringValue == title, editor.timePicker.dateValue == item.dueAt, !presenter.panel.canBecomeKey && !presenter.panel.canBecomeMain && presenter.panel.styleMask.contains(.nonactivatingPanel)]
    print("Reminder presentation tests: \(results.filter { $0 }.count)/\(results.count) passed")
    return results.allSatisfy { $0 }
}

func exportReminderPreviews(to directory: String) throws {
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let now = Date(), book = ReminderBookModel()
    let first = try book.add(title: "给绿植浇水，顺便看看阳台的小花。", dueAt: now.addingTimeInterval(600), now: now)
    _ = try book.add(title: "提交整理好的项目报告", dueAt: now.addingTimeInterval(3600), now: now)
    let due = try book.add(title: "记得把晾好的衣服收回来。", dueAt: now.addingTimeInterval(1), now: now)
    _ = book.collectDue(at: now.addingTimeInterval(2))
    let editor = ReminderBookView(book: book, size: NSSize(width: 760, height: 560))
    editor.selectReminder(first.id)
    let window = NSWindow(contentRect: editor.bounds, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = editor; editor.layoutSubtreeIfNeeded(); renderPreview(editor, to: directory + "/定时提醒设置.png")
    let size = ScheduledReminderBalloonView.preferredSize(for: due.title, maxWidth: 340, maxHeight: 300)
    let balloon = ScheduledReminderBalloonView(item: due, count: 1, size: size, tailAtTop: false)
    let alert = NSWindow(contentRect: balloon.bounds, styleMask: .borderless, backing: .buffered, defer: false)
    alert.contentView = balloon; renderPreview(balloon, to: directory + "/定时提醒气泡.png")
    let canvas = ReminderCanvas(frame: NSRect(x: 0, y: 0, width: 400, height: size.height + 210))
    canvas.wantsLayer = true; canvas.layer?.backgroundColor = OutfitRenderer.color(0xF5F0F5).cgColor
    let combinedBalloon = ScheduledReminderBalloonView(item: due, count: 1, size: size, tailAtTop: false)
    combinedBalloon.frame.origin = NSPoint(x: 30, y: 10); canvas.addSubview(combinedBalloon)
    let cat = previewScene("安静", now: now)
    cat.timedReminderVisible = true; cat.frame.origin = NSPoint(x: 68, y: size.height - 30)
    canvas.addSubview(cat)
    let combinedWindow = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
    combinedWindow.contentView = canvas; renderPreview(canvas, to: directory + "/定时提醒效果.png")
    print("Reminder editor and alert previews rendered to \(directory)")
}
