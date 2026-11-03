using System.Text.Json;

namespace QiaoQiao.Core;

public sealed class Reminder
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Title { get; set; } = "";
    public DateTimeOffset Due { get; set; }
    public bool Done { get; set; }
    public bool Acknowledged { get; set; }
}

public sealed class SaveState
{
    public int Schema { get; set; } = 1;
    public string Day { get; set; } = "";
    public long Count { get; set; }
    public long Lifetime { get; set; }
    public int SleepSeconds { get; set; } = 60;
    public int RestMinutes { get; set; } = 45;
    public double Size { get; set; } = 1;
    public int? Outfit { get; set; }
    public bool Automatic { get; set; } = true;
    public bool ReducedMotion { get; set; }
    public double? Left { get; set; }
    public double? Top { get; set; }
    public List<Reminder> Reminders { get; set; } = [];
    public SavedTimerBook Timers { get; set; } = new();
}

// Key identity includes the device and extended scan code. Only this transient
// set sees a scan code; no key, typed text or pointer position enters the save.
public sealed class PressFilter
{
    private readonly HashSet<(long Device, int Key)> held = [];
    public bool Accept(long device, int scan, int virtualKey, int flags)
    {
        if (virtualKey is <= 0 or >= 255 || scan == 255) return false;
        var key = scan == 0 ? 0x10000 | virtualKey : scan | ((flags & 6) << 8);
        var identity = (device, key);
        if ((flags & 1) != 0) { held.Remove(identity); return false; }
        // Pause has no corresponding break on many keyboards.
        if (virtualKey == 0x13) return true;
        return held.Add(identity);
    }
    public void Reset() => held.Clear();
    public void Remove(long device) => held.RemoveWhere(k => k.Device == device);
}

public sealed class PetModel
{
    public SaveState Saved { get; }
    private readonly Queue<DateTimeOffset> recent = [];
    private readonly Queue<DateTimeOffset> deletes = [];
    private readonly Dictionary<string, DateTimeOffset> spoken = [];
    private DateTimeOffset lastTick;
    private DateTimeOffset lastActivity;
    private double workSeconds;
    private string reaction = "idle";
    private DateTimeOffset reactionUntil;
    private string lastState = "idle";
    private DateTimeOffset stateBegan;
    private string previousMood = "idle";
    public DateTimeOffset LastPress { get; private set; } = DateTimeOffset.MinValue;
    public DateTimeOffset SpeechUntil { get; private set; }
    public string Speech { get; private set; } = "";
    public int InputSerial { get; private set; }
    public bool Paused { get; private set; }
    public bool Dirty { get; set; }
    public bool RestDue { get; private set; }
    public int Unlocked => (int)Math.Min(100, Saved.Lifetime / 100);
    public IReadOnlyList<Reminder> Due(DateTimeOffset now) => Saved.Reminders.Where(r => !r.Done && !r.Acknowledged && r.Due <= now).OrderBy(r => r.Due).ToArray();

    public PetModel(SaveState? saved, DateTimeOffset now)
    {
        Saved = saved ?? new SaveState();
        Saved.Count = Math.Max(0, Saved.Count);
        Saved.Lifetime = Math.Max(Saved.Count, Saved.Lifetime);
        if (Saved.SleepSeconds is not (30 or 60 or 120)) Saved.SleepSeconds = 60;
        if (Saved.RestMinutes is not (0 or 20 or 30 or 45 or 60)) Saved.RestMinutes = 45;
        Saved.Size = double.IsFinite(Saved.Size) ? Math.Clamp(Saved.Size, .5, 1.8) : 1;
        if (Saved.Outfit is int id && (id < 0 || id >= Unlocked)) Saved.Outfit = null;
        Saved.Reminders = (Saved.Reminders ?? []).Where(r => r != null && !string.IsNullOrWhiteSpace(r.Title)).Take(200).ToList();
        foreach (var r in Saved.Reminders) r.Title = r.Title[..Math.Min(200, r.Title.Length)];
        lastTick = lastActivity = stateBegan = now;
        Tick(now);
    }

    public void Tick(DateTimeOffset now)
    {
        string day = now.ToLocalTime().ToString("yyyy-MM-dd");
        if (day != Saved.Day) { Saved.Day = day; Saved.Count = 0; Dirty = true; }
        while (recent.Count > 0 && (recent.Peek() <= now.AddSeconds(-60) || recent.Peek() > now)) recent.Dequeue();
        var delta = (now - lastTick).TotalSeconds;
        if (delta < 0) { recent.Clear(); lastActivity = now; }
        var idle = (now - lastActivity).TotalSeconds;
        if (idle >= 300) { workSeconds = 0; RestDue = false; }
        else if (!Paused && idle <= 90 && delta is > 0 and <= 2) workSeconds += delta;
        if (Saved.RestMinutes > 0 && workSeconds >= Saved.RestMinutes * 60) RestDue = true;
        if (Saved.RestMinutes == 0) RestDue = false;
        lastTick = now;
        var mood = Mood(now);
        if (mood != previousMood && mood is "drowsy" or "sleeping")
            Say(mood == "drowsy" ? "没动静了，我眯会儿。" : "呼……叫我就醒。", now, 4, mood, 15);
        previousMood = mood;
    }
    public int Rate(DateTimeOffset now) { Tick(now); return recent.Count; }
    public string Mood(DateTimeOffset now)
    {
        if (Paused) return "sleeping";
        var idle = Math.Max(0, (now - lastActivity).TotalSeconds);
        return idle >= Saved.SleepSeconds ? "sleeping" : idle >= Saved.SleepSeconds - 5 ? "drowsy" : "idle";
    }
    public void Activity(DateTimeOffset now)
    {
        Tick(now); if (Paused) return;
        bool waking = Mood(now) is "sleeping" or "drowsy";
        lastActivity = now;
        if (waking) { React("waking", now, .6); Say("醒啦，继续陪你！", now); }
    }
    public void Press(DateTimeOffset now, bool deleting = false)
    {
        Tick(now);
        if (Paused) return;
        var oldMood = Mood(now);
        lastActivity = LastPress = now;
        InputSerial++;
        if (Saved.Count < long.MaxValue) Saved.Count++;
        long oldMilestone = Saved.Lifetime / 100;
        if (Saved.Lifetime < long.MaxValue) Saved.Lifetime++;
        recent.Enqueue(now);
        Dirty = true;
        if (deleting) deletes.Enqueue(now);
        while (deletes.Count > 0 && deletes.Peek() < now.AddSeconds(-2)) deletes.Dequeue();
        string state = deleting && deletes.Count >= 3 ? "deleting" : recent.Count(t => t > now.AddSeconds(-1)) >= 8 ? "fast" : "typing";
        React(state, now, .35);
        if (Saved.Lifetime / 100 > oldMilestone)
        {
            if (Saved.Automatic) Saved.Outfit = (int)((Saved.Lifetime / 100 - 1) % 100);
            Say(Saved.Automatic ? "新装扮！我穿上啦。" : "衣柜又多一套啦。", now);
        }
        else if (state == "deleting") Say("慢慢改，我陪你。", now, 4, "deleting", 12);
        else if (state == "fast") Say("哇，爪子跟不上啦！", now, 4, "fast", 18);
        else if (oldMood == "sleeping") Say("醒啦，继续陪你！", now);
    }
    public void React(string state, DateTimeOffset now, double seconds = 1.2) { reaction = state; reactionUntil = now.AddSeconds(seconds); }
    public void Say(string message, DateTimeOffset now, double seconds = 4, string? key = null, double cooldown = 0)
    {
        if (key != null && spoken.TryGetValue(key, out var before) && (now - before).TotalSeconds < cooldown) return;
        if (key != null) spoken[key] = now;
        Speech = message; SpeechUntil = now.AddSeconds(seconds);
    }
    public (string State, double Elapsed) Animation(DateTimeOffset now, bool reminderVisible = false)
    {
        var active = now < reactionUntil ? reaction : Mood(now);
        if (reminderVisible && (now - LastPress).TotalSeconds >= .25 && active is not ("dragging" or "resizing" or "petting")) active = "reminder";
        if (active != lastState || now < stateBegan) { stateBegan = now; lastState = active; }
        return (active, Math.Max(0, (now - stateBegan).TotalSeconds));
    }
    public void SetPaused(bool paused, DateTimeOffset now)
    {
        Paused = paused; recent.Clear(); lastActivity = lastTick = now;
        Say(paused ? "那就一起歇一会儿。" : "准备好啦！", now);
    }
    public bool Equip(int? id, DateTimeOffset now)
    {
        if (id is int n && (n < 0 || n >= Unlocked)) return false;
        Saved.Outfit = id; Dirty = true;
        React("petting", now); Say(id == null ? "原来的样子也不错。" : "换好啦，好看吗？", now); return true;
    }
    public void SetAutomatic(bool enabled, DateTimeOffset now)
    {
        Saved.Automatic = enabled; Dirty = true;
        if (enabled && Saved.Lifetime >= 100) Equip((int)((Saved.Lifetime / 100 - 1) % 100), now);
        else Say("记住啦。", now);
    }
    public void Rest(DateTimeOffset now, bool snooze = false)
    {
        RestDue = false; workSeconds = snooze ? Math.Max(0, Saved.RestMinutes * 60 - 600) : 0;
        Say(snooze ? "十分钟后再叫你。" : "回来啦，我们慢慢来。", now);
        React("rest", now);
    }
    public bool AddReminder(string title, DateTimeOffset due, DateTimeOffset now, Guid? editing = null)
    {
        title = title.Trim();
        if (title.Length is 0 or > 200 || due <= now) return false;
        var r = editing == null ? null : Saved.Reminders.FirstOrDefault(r => r.Id == editing);
        if (r == null && Saved.Reminders.Count >= 200) return false;
        if (r == null) { r = new Reminder(); Saved.Reminders.Add(r); }
        r.Title = title; r.Due = due; r.Done = false; r.Acknowledged = false;
        Dirty = true; React("petting", now); Say("记好啦，到点叫你。", now); return true;
    }
    public void ActOnReminder(Guid id, string action, DateTimeOffset now)
    {
        var r = Saved.Reminders.FirstOrDefault(r => r.Id == id); if (r == null) return;
        switch (action)
        {
            case "done": r.Done = true; Say("又完成一件，真不错。", now); break;
            case "snooze": r.Due = now.AddMinutes(10); r.Acknowledged = false; Say("十分钟后再叫你。", now); break;
            case "delete": Saved.Reminders.Remove(r); Say("已经划掉啦。", now); break;
            default: r.Acknowledged = true; Say("我收在提醒本里。", now); break;
        }
        Dirty = true; React("petting", now);
    }
}

public static class StateStore
{
    public static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true, PropertyNameCaseInsensitive = true };
    public static SaveState Load(string path)
    {
        foreach (var candidate in new[] { path, path + ".bak" })
            try { if (File.Exists(candidate)) return JsonSerializer.Deserialize<SaveState>(File.ReadAllText(candidate), JsonOptions) ?? new(); }
            catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { }
        return new();
    }
    public static void Save(string path, SaveState state)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        string temp = path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(state, JsonOptions));
        if (File.Exists(path)) File.Copy(path, path + ".bak", true);
        File.Move(temp, path, true);
    }
}
