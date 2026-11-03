import AppKit

extension AppController {
    @objc func showTimerCenter() {
        if timerWindow == nil {
            timerWindow = TimerWindowController(book: timers) { [weak self] line in self?.timersChanged(line) }
            timerWindow?.onClose = { [weak self] in
                guard let self = self else { return }
                if self.wardrobeWindow?.window?.isVisible != true && self.reminderWindow?.window?.isVisible != true && self.testWindow?.isVisible != true { NSApp.setActivationPolicy(.accessory) }
            }
        }
        timerWindow?.editor.refresh(); feedback.react(.settings); refresh()
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
        timerWindow?.showWindow(nil); timerWindow?.window?.makeKeyAndOrderFront(nil)
    }
    func timersChanged(_ line: String) {
        feedback.react(.settings)
        // Timer-specific speech uses the existing transient bubble mechanism.
        feedback.timerFeedback(line)
        processTimers(at: Date()); save(); timerWindow?.editor.refresh(); refresh()
    }
    func clearTimerPresentation() {
        timerPresenter?.hide(); activeTimer = nil; pet.timedReminderVisible = activeScheduledReminder != nil
    }
    func processTimers(at now: Date) {
        let changed = timers.tick(at: now)
        let activePomodoro = timers.items.contains { $0.kind == .pomodoro && $0.active }
        if hadPomodoro && !activePomodoro { rest.resetAfterRest(at: now); pendingRestReminder = false }
        hadPomodoro = activePomodoro
        pet.timerDisplay = timers.display
        if pet.bounds.size != pet.logicalSize && !pet.isInteracting { applySizing(anchor: .topLeft) }
        if changed { save() }
        if timerWindow?.window?.isVisible == true { timerWindow?.editor.refresh() }
        guard !machineSleeping, !sessionInactive, activeScheduledReminder == nil else { return }
        if let id = activeTimer, timers.pending.contains(where: { $0.id == id }) { return }
        if activeTimer != nil { clearTimerPresentation() }
        guard !pet.isInteracting, let t = timers.pending.first else { return }
        if timerPresenter == nil {
            let presenter = ScheduledReminderPresenter()
            presenter.onComplete = { [weak self] id in
                guard let self = self else { return }
                _ = self.timers.advance(id, at: Date()); self.clearTimerPresentation(); self.timersChanged("记好啦，按自己的节奏来。")
            }
            presenter.onSnooze = { [weak self] id in
                guard let self = self, let timer = self.timers.items.first(where: { $0.id == id }) else { return }
                if timer.kind == .countdown { _ = self.timers.restart(id, at: Date()) }
                else { self.timers.acknowledge(id) }
                self.clearTimerPresentation(); self.timersChanged(timer.kind == .countdown ? "再计一次，到点叫你。" : "先收好，准备好了再开始。")
                if timer.kind == .workday { self.showTimerCenter() }
            }
            presenter.onLater = { [weak self] id in
                guard let self = self, let timer = self.timers.items.first(where: { $0.id == id }) else { return }
                if timer.kind == .countdown { self.timers.acknowledge(id) }
                else { _ = self.timers.stop(id) }
                self.clearTimerPresentation(); self.timersChanged("收好啦，辛苦了。")
            }
            timerPresenter = presenter
        }
        let titles = t.kind == .countdown ? ["知道啦", "再计一次", "稍后查看"] : [t.advanceTitle, t.kind == .workday ? "计时列表" : "稍后查看", t.kind == .workday ? "结束计时" : "结束番茄"]
        let item = ScheduledReminder(id: t.id, title: t.completionText, dueAt: now, createdAt: now, updatedAt: now, state: .pending, acknowledgedAt: nil)
        activeTimer = t.id; pet.timedReminderVisible = true
        feedback.react(.scheduledReminder, at: now)
        if desktopVisible { panel.orderFrontRegardless() }
        timerPresenter?.show(item, count: timers.pending.count, near: panel.frame, buttonTitles: titles)
    }
}
