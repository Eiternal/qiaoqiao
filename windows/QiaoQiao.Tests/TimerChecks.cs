using QiaoQiao.Core;
using System.Text.Json;

internal static class TimerChecks
{
    internal static void Run(Action<bool, string> check)
    {
        var now = new DateTimeOffset(2026, 11, 3, 10, 0, 0, TimeSpan.Zero);
        bool Rejects(Action a) { try { a(); return false; } catch (ArgumentException) { return true; } }
        var b = new TimerBook(); var id = b.Countdown("喝水", 61, now);
        check(b.Display?.Id == id && b.Display.Seconds(now.AddSeconds(1)) == 60, "timer derives remaining from deadline");
        check(DeskTimer.TimeText(60.1) == "01:01" && DeskTimer.TimeText(3661) == "01:01:01", "timer ceil-second formatting");
        check(b.Pause(id, now.AddSeconds(10)) && b.Display?.Seconds(now.AddDays(3)) == 51, "timer pause freezes remaining");
        var restored = new TimerBook(JsonSerializer.Deserialize<SavedTimerBook>(JsonSerializer.Serialize(b.Saved)));
        check(restored.Display?.State == TimerState.Paused && restored.Display.Remaining == 51, "paused timer save round trip");
        check(restored.Pause(id, now.AddSeconds(100)), "timer resume");
        check(!restored.Tick(now.AddSeconds(150.9)), "timer never expires early");
        check(restored.Tick(now.AddSeconds(151)) && restored.Pending.Count == 1, "timer expires at exact deadline");
        check(!restored.Tick(now.AddSeconds(9999)), "timer expiration idempotent");
        restored.Acknowledge(id); check(restored.Pending.Count == 0 && restored.Display?.State == TimerState.Awaiting, "timer later keeps pending phase");
        check(restored.Restart(id, now) && restored.Display?.Seconds(now) == 61, "countdown repeat");
        restored.Tick(now.AddSeconds(62)); restored.Advance(id, now.AddSeconds(63));
        check(restored.Display == null && restored.Items[0].State == TimerState.Finished, "acknowledged countdown hides badge");
        check(Rejects(() => b.Countdown("bad", 0, now)) && Rejects(() => b.Countdown("bad", double.PositiveInfinity, now)), "timer invalid duration");
        check(Rejects(() => b.Countdown(new string('字', 41), 1, now)), "timer bounded title");
        var second = b.Countdown("煮面", 20, now); check(b.Items.Count == 2 && b.Display?.Id == second, "concurrent timer selection");
        b.Saved.ShowBadge = false; check(b.Display == null && b.Items.Count == 2, "hidden badge does not cancel timers");
        b.Saved.ShowBadge = true; b.Remove(second); check(b.Display?.Id == id, "deleted timer selection fallback");
        b.Pause(id, now); var running = new TimerBook(b.Saved); running.Tick(now.AddHours(2)); check(running.Pending.Count == 1, "overdue timer after sleep or restart");
        var pomo = new TimerBook(); var pid = pomo.Pomodoro(now, 60, 60, 120, 2);
        check(Rejects(() => pomo.Pomodoro(now)), "one active Pomodoro");
        pomo.Tick(now.AddDays(3)); check(pomo.Display?.CompletedFocus == 1 && pomo.Display.Phase == PomodoroPhase.Focus && pomo.Display.State == TimerState.Awaiting, "absence never fabricates Pomodoro cycles");
        pomo.Advance(pid, now); check(pomo.Display?.Phase == PomodoroPhase.ShortBreak && pomo.Display.Duration == 60, "Pomodoro short break after focus");
        pomo.Tick(now.AddSeconds(60)); pomo.Advance(pid, now.AddSeconds(60)); check(pomo.Display?.Phase == PomodoroPhase.Focus && pomo.Display.CompletedFocus == 1, "break not counted as focus");
        pomo.Tick(now.AddSeconds(120)); pomo.Advance(pid, now.AddSeconds(120)); check(pomo.Display?.Phase == PomodoroPhase.LongBreak && pomo.Display.Duration == 120, "configured long break cadence");
        pomo.Tick(now.AddSeconds(240)); pomo.Advance(pid, now.AddSeconds(240)); check(pomo.Display?.Phase == PomodoroPhase.Focus && pomo.Display.CompletedFocus == 2, "long break returns to focus");
        check(pomo.Stop(pid) && pomo.Display == null, "stopping Pomodoro ends whole cycle");
        var friday = new DateTimeOffset(2026, 11, 6, 17, 0, 0, TimeSpan.Zero); var w = new TimerBook(); var wid = w.Workday(friday.AddHours(1), true, friday, TimeZoneInfo.Utc);
        check(!w.Pause(wid, friday), "departure deadline cannot pause");
        w.Tick(friday.AddHours(1)); w.Advance(wid, friday.AddHours(1).AddSeconds(1), TimeZoneInfo.Utc);
        check(w.Display?.Deadline == new DateTimeOffset(2026, 11, 9, 18, 0, 0, TimeSpan.Zero), "weekday recurrence skips weekend");
        check(Rejects(() => new TimerBook().Workday(friday, false, friday)), "past departure time rejected");
        var cap = new TimerBook(); for (int i = 0; i < 20; i++) cap.Countdown("", 1, now);
        check(Rejects(() => cap.Countdown("", 1, now)) && cap.Items.Count == 20, "timer capacity preserves existing items");
        var model = new PetModel(new SaveState { Timers = b.Saved }, now);
        for (int i = 0; i < 100; i++) { running.Tick(now.AddSeconds(i)); model.Tick(now.AddSeconds(i)); }
        check(model.Saved.Count == 0 && model.Saved.Lifetime == 0, "timers cannot create input counts");
        var oldSave = JsonSerializer.Deserialize<SaveState>("{\"Count\":15,\"Lifetime\":20}")!;
        check(new TimerBook(oldSave.Timers).Items.Count == 0 && oldSave.Lifetime == 20, "old progress loads without timer schema");
    }
}
