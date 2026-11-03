namespace QiaoQiao.Core;

public enum TimerKind { Countdown, Workday, Pomodoro }
public enum TimerState { Running, Paused, Awaiting, Finished }
public enum PomodoroPhase { Focus, ShortBreak, LongBreak }

public sealed class DeskTimer
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Title { get; set; } = "";
    public TimerKind Kind { get; set; }
    public TimerState State { get; set; }
    public PomodoroPhase Phase { get; set; }
    public DateTimeOffset? Deadline { get; set; }
    public double Remaining { get; set; }
    public double Duration { get; set; }
    public double FocusSeconds { get; set; } = 1500;
    public double ShortSeconds { get; set; } = 300;
    public double LongSeconds { get; set; } = 900;
    public int Rounds { get; set; } = 4;
    public int CompletedFocus { get; set; }
    public bool RepeatWeekdays { get; set; }
    public int WorkHour { get; set; } = 18;
    public int WorkMinute { get; set; }
    public bool Acknowledged { get; set; }
    public bool Active => State != TimerState.Finished;
    public bool CanPause => Kind != TimerKind.Workday && State is TimerState.Running or TimerState.Paused;
    public double Seconds(DateTimeOffset now) => State == TimerState.Paused ? Math.Max(0, Remaining) : State == TimerState.Running ? Math.Max(0, (Deadline - now)?.TotalSeconds ?? 0) : 0;
    public double Progress(DateTimeOffset now) => Math.Clamp(1 - Seconds(now) / Math.Max(1, Duration), 0, 1);
    public string PhaseTitle => Kind == TimerKind.Pomodoro ? Phase == PomodoroPhase.Focus ? "专注" : Phase == PomodoroPhase.ShortBreak ? "短休息" : "长休息" : Kind == TimerKind.Workday ? "下班倒计时" : "自由倒计时";
    public string Symbol => State == TimerState.Paused ? "Ⅱ" : Kind == TimerKind.Pomodoro ? "◉" : Kind == TimerKind.Workday ? "☼" : "◷";
    public string CompletionText => Kind == TimerKind.Workday ? "到下班时间啦，辛苦了～" : Kind == TimerKind.Countdown ? Title + "，到时间啦。" : Phase == PomodoroPhase.Focus ? "这一段专注完成啦，歇一会儿吧。" : "休息结束啦，准备好再继续。";
    public string AdvanceTitle => Kind != TimerKind.Pomodoro ? "知道啦" : Phase == PomodoroPhase.Focus ? CompletedFocus % Math.Max(1, Rounds) == 0 ? "开始长休息" : "开始短休息" : "开始专注";
    public static string TimeText(double seconds)
    {
        int n = double.IsFinite(seconds) ? (int)Math.Clamp(Math.Ceiling(seconds), 0, 604800) : 0;
        return n >= 3600 ? $"{n / 3600:00}:{n / 60 % 60:00}:{n % 60:00}" : $"{n / 60:00}:{n % 60:00}";
    }
}
public sealed class SavedTimerBook
{
    public List<DeskTimer> Items { get; set; } = [];
    public Guid? SelectedId { get; set; }
    public bool ShowBadge { get; set; } = true;
}

// Absolute deadlines do not depend on the render timer's callback frequency.
// Expiration waits for the person to start the next Pomodoro phase explicitly.
public sealed class TimerBook
{
    public SavedTimerBook Saved { get; }
    public IReadOnlyList<DeskTimer> Items => Saved.Items;
    public IReadOnlyList<DeskTimer> Pending => Saved.Items.Where(t => t.State == TimerState.Awaiting && !t.Acknowledged).ToArray();
    public DeskTimer? Display => !Saved.ShowBadge ? null : Saved.Items.FirstOrDefault(t => t.Id == Saved.SelectedId && t.Active) ?? Pending.FirstOrDefault() ?? Saved.Items.Where(t => t.State == TimerState.Running).OrderBy(t => t.Deadline).FirstOrDefault() ?? Saved.Items.FirstOrDefault(t => t.Active);
    public TimerBook(SavedTimerBook? saved = null)
    {
        Saved = saved ?? new();
        Saved.Items = (Saved.Items ?? []).Where(t => t != null && Enum.IsDefined(t.Kind) && Enum.IsDefined(t.State) && Enum.IsDefined(t.Phase)).DistinctBy(t => t.Id).Take(20).ToList();
        foreach (var t in Saved.Items)
        {
            t.Title = string.Concat((t.Title ?? "").Trim().EnumerateRunes().Take(40).Select(r => r.ToString()));
            if (t.Title.Length == 0) t.Title = t.Kind == TimerKind.Pomodoro ? "番茄钟" : "倒计时";
            t.Duration = Safe(t.Duration, 1500, 1, 604800); t.Remaining = Safe(t.Remaining, t.Duration, 0, 604800);
            t.FocusSeconds = Safe(t.FocusSeconds, 1500, 60, 10800); t.ShortSeconds = Safe(t.ShortSeconds, 300, 60, 3600); t.LongSeconds = Safe(t.LongSeconds, 900, 60, 7200);
            t.Rounds = Math.Clamp(t.Rounds, 1, 12); t.CompletedFocus = Math.Clamp(t.CompletedFocus, 0, 1000000);
            t.WorkHour = Math.Clamp(t.WorkHour, 0, 23); t.WorkMinute = Math.Clamp(t.WorkMinute, 0, 59);
            if (t.State == TimerState.Running && t.Deadline == null) { t.State = TimerState.Paused; t.Remaining = t.Duration; }
        }
    }
    private static double Safe(double value, double fallback, double lo, double hi) => double.IsFinite(value) ? Math.Clamp(value, lo, hi) : fallback;
    private void Room(TimerKind kind)
    {
        if (Saved.Items.Count >= 20) throw new ArgumentException("最多保存 20 个计时，请先删除已结束的项目。");
        if (kind != TimerKind.Countdown && Items.Any(t => t.Kind == kind && t.Active)) throw new ArgumentException("这个模式已经在计时啦，请先结束原来的计时。");
    }
    private static string Name(string title, string fallback)
    {
        title = title.Trim(); if (title.EnumerateRunes().Count() > 40) throw new ArgumentException("名称最多 40 字。"); return title.Length == 0 ? fallback : title;
    }
    public Guid Countdown(string title, double seconds, DateTimeOffset now)
    {
        Room(TimerKind.Countdown);
        if (!double.IsFinite(seconds) || seconds < 1 || seconds > 604800) throw new ArgumentException("自由倒计时为 1 秒到 7 天。");
        var t = new DeskTimer { Title = Name(title, "自由倒计时"), Kind = TimerKind.Countdown, Deadline = now.AddSeconds(seconds), Duration = seconds };
        Saved.Items.Add(t); Saved.SelectedId = t.Id; return t.Id;
    }
    public Guid Workday(DateTimeOffset end, bool repeatWeekdays, DateTimeOffset now, TimeZoneInfo? zone = null)
    {
        Room(TimerKind.Workday); var duration = (end - now).TotalSeconds;
        if (duration <= 0 || duration > 604800) throw new ArgumentException("请选择未来 7 天内的下班时间。");
        var local = TimeZoneInfo.ConvertTime(end, zone ?? TimeZoneInfo.Local);
        var t = new DeskTimer { Title = "下班倒计时", Kind = TimerKind.Workday, Deadline = end, Duration = duration, RepeatWeekdays = repeatWeekdays, WorkHour = local.Hour, WorkMinute = local.Minute };
        Saved.Items.Add(t); Saved.SelectedId = t.Id; return t.Id;
    }
    public Guid Pomodoro(DateTimeOffset now, double focus = 1500, double shortBreak = 300, double longBreak = 900, int rounds = 4)
    {
        Room(TimerKind.Pomodoro);
        if (!double.IsFinite(focus) || !double.IsFinite(shortBreak) || !double.IsFinite(longBreak) || focus is < 60 or > 10800 || shortBreak is < 60 or > 3600 || longBreak is < 60 or > 7200 || rounds is < 1 or > 12) throw new ArgumentException("专注 1–180 分钟，短休息 1–60 分钟，长休息 1–120 分钟，每 1–12 轮长休息。");
        var t = new DeskTimer { Title = "番茄钟", Kind = TimerKind.Pomodoro, Deadline = now.AddSeconds(focus), Duration = focus, FocusSeconds = focus, ShortSeconds = shortBreak, LongSeconds = longBreak, Rounds = rounds };
        Saved.Items.Add(t); Saved.SelectedId = t.Id; return t.Id;
    }
    public bool Tick(DateTimeOffset now)
    {
        bool changed = false;
        foreach (var t in Saved.Items.Where(t => t.State == TimerState.Running && t.Deadline <= now))
        {
            t.State = TimerState.Awaiting; t.Deadline = null; t.Remaining = 0;
            t.Acknowledged = false;
            if (t.Kind == TimerKind.Pomodoro && t.Phase == PomodoroPhase.Focus) t.CompletedFocus = Math.Min(1000000, t.CompletedFocus + 1);
            changed = true;
        }
        return changed;
    }
    public bool Pause(Guid id, DateTimeOffset now)
    {
        Tick(now); var t = Saved.Items.FirstOrDefault(t => t.Id == id);
        if (t == null || !t.CanPause) return false;
        if (t.State == TimerState.Running) { t.Remaining = t.Seconds(now); t.Deadline = null; t.State = TimerState.Paused; }
        else { t.Deadline = now.AddSeconds(t.Remaining); t.State = TimerState.Running; }
        t.Acknowledged = false; return true;
    }
    public void Acknowledge(Guid id) { var t = Saved.Items.FirstOrDefault(t => t.Id == id); if (t != null) t.Acknowledged = true; }
    public bool Restart(Guid id, DateTimeOffset now)
    {
        var t = Saved.Items.FirstOrDefault(t => t.Id == id && t.Kind == TimerKind.Countdown); if (t == null) return false;
        t.State = TimerState.Running; t.Deadline = now.AddSeconds(t.Duration); t.Acknowledged = false; return true;
    }
    public bool Advance(Guid id, DateTimeOffset now, TimeZoneInfo? zone = null)
    {
        var t = Saved.Items.FirstOrDefault(t => t.Id == id && t.State == TimerState.Awaiting); if (t == null) return false;
        if (t.Kind == TimerKind.Pomodoro)
        {
            t.Phase = t.Phase == PomodoroPhase.Focus ? t.CompletedFocus % t.Rounds == 0 ? PomodoroPhase.LongBreak : PomodoroPhase.ShortBreak : PomodoroPhase.Focus;
            t.Duration = t.Phase == PomodoroPhase.Focus ? t.FocusSeconds : t.Phase == PomodoroPhase.ShortBreak ? t.ShortSeconds : t.LongSeconds;
            t.Deadline = now.AddSeconds(t.Duration); t.State = TimerState.Running;
        }
        else if (t.Kind == TimerKind.Workday && t.RepeatWeekdays && NextWorkday(now, t.WorkHour, t.WorkMinute, zone ?? TimeZoneInfo.Local) is DateTimeOffset next)
        { t.Deadline = next; t.Duration = (next - now).TotalSeconds; t.State = TimerState.Running; }
        else t.State = TimerState.Finished;
        t.Acknowledged = false; return true;
    }
    public bool Stop(Guid id)
    {
        var t = Saved.Items.FirstOrDefault(t => t.Id == id && t.Active); if (t == null) return false;
        t.State = TimerState.Finished; t.Deadline = null; t.Remaining = 0; return true;
    }
    public void Remove(Guid id) { Saved.Items.RemoveAll(t => t.Id == id); if (Saved.SelectedId == id) Saved.SelectedId = null; }
    public static DateTimeOffset? NextWorkday(DateTimeOffset now, int hour, int minute, TimeZoneInfo zone)
    {
        var today = TimeZoneInfo.ConvertTime(now, zone).Date;
        for (int day = 0; day <= 8; day++)
        {
            var local = DateTime.SpecifyKind(today.AddDays(day).AddHours(hour).AddMinutes(minute), DateTimeKind.Unspecified);
            if (local.DayOfWeek is DayOfWeek.Saturday or DayOfWeek.Sunday) continue;
            // Match Calendar's next valid civil time across a daylight-saving gap.
            for (int m = 0; m < 180 && zone.IsInvalidTime(local); m++) local = local.AddMinutes(1);
            if (zone.IsInvalidTime(local)) continue;
            var target = new DateTimeOffset(local, zone.GetUtcOffset(local)); if (target > now) return target;
        }
        return null;
    }
}
