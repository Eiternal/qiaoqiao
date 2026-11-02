using QiaoQiao.Core;
using System.Text.Json;

int checks = 0;
var failures = new List<string>();
void Check(bool condition, string label) { checks++; if (!condition) failures.Add(label); }
var now = new DateTimeOffset(2026, 11, 2, 10, 0, 0, TimeSpan.Zero);
PetModel New(long count = 0) => new(new SaveState { Day = now.ToLocalTime().ToString("yyyy-MM-dd"), Count = count, Lifetime = count }, now);
var filter = new PressFilter();
Check(filter.Accept(1, 30, 65, 0), "physical key down");
Check(!filter.Accept(1, 30, 65, 0), "OS autorepeat excluded");
Check(!filter.Accept(1, 30, 65, 1), "key release excluded");
Check(filter.Accept(1, 30, 65, 0), "next physical press counts");
Check(filter.Accept(2, 30, 65, 0), "two keyboards independent");
filter.Remove(1);
Check(filter.Accept(1, 30, 65, 0), "disconnect clears held keys for device");
Check(!filter.Accept(2, 30, 65, 0), "other device held state preserved");
filter.Reset();
Check(filter.Accept(1, 42, 16, 0) && filter.Accept(1, 54, 16, 0), "left/right Shift count independently");
Check(filter.Accept(1, 29, 17, 0) && filter.Accept(1, 29, 17, 2), "left/right Control extended scan codes");
Check(!filter.Accept(1, 255, 65, 0) && !filter.Accept(1, 0, 255, 0), "invalid input ignored");
Check(filter.Accept(1, 69, 19, 4) && filter.Accept(1, 69, 19, 4), "Pause without break can be pressed again");

var model = New();
model.Press(now); model.Press(now.AddSeconds(1));
Check(model.Saved.Count == 2 && model.Saved.Lifetime == 2, "actual presses counted");
Check(model.Rate(now.AddSeconds(59.99)) == 2, "rolling minute before boundary");
Check(model.Rate(now.AddSeconds(60)) == 1, "rolling minute exact boundary");
Check(model.Rate(now.AddSeconds(61)) == 0, "rolling minute decays with clock");
var activity = New(); activity.Activity(now.AddSeconds(55));
Check(activity.Saved.Count == 0 && activity.Saved.Lifetime == 0, "movement and scroll do not count");
Check(activity.Mood(now.AddSeconds(60)) == "idle", "movement keeps pet awake");
var sleep = New();
Check(sleep.Mood(now.AddSeconds(54.9)) == "idle", "awake before lead-in");
Check(sleep.Mood(now.AddSeconds(55)) == "drowsy", "five-second drowsy lead-in");
Check(sleep.Mood(now.AddSeconds(60)) == "sleeping", "actual sleep at deadline");
Check(sleep.Mood(now.AddHours(2)) == "sleeping", "sleep stays settled");
sleep.Press(now.AddSeconds(61));
Check(sleep.Animation(now.AddSeconds(61)).State == "typing", "wake press responds immediately");
Check(sleep.Speech.Contains("醒啦"), "wake speech feedback");
sleep.SetPaused(true, now.AddSeconds(62)); long before = sleep.Saved.Count; sleep.Press(now.AddSeconds(63));
Check(sleep.Saved.Count == before && sleep.Rate(now.AddSeconds(63)) == 0, "pause counts nothing");
sleep.SetPaused(false, now.AddSeconds(64)); sleep.Press(now.AddSeconds(65));
Check(sleep.Saved.Count == before + 1, "resume counts normally");

var midnight = new DateTimeOffset(now.LocalDateTime.Date.AddHours(23).AddMinutes(59).AddSeconds(59), TimeZoneInfo.Local.GetUtcOffset(now));
var dayModel = new PetModel(new SaveState(), midnight); dayModel.Press(midnight); dayModel.Tick(midnight.AddSeconds(2));
Check(dayModel.Saved.Count == 0 && dayModel.Saved.Lifetime == 1, "midnight resets today only");
var wardrobe = New(99); wardrobe.Press(now);
Check(wardrobe.Unlocked == 1 && wardrobe.Saved.Outfit == 0, "first hundred unlocks and equips");
Check(!wardrobe.Equip(1, now), "locked outfit rejected");
wardrobe.SetAutomatic(false, now);
for (int i = 0; i < 100; i++) wardrobe.Press(now.AddMilliseconds(i + 1));
Check(wardrobe.Unlocked == 2 && wardrobe.Saved.Outfit == 0, "manual mode still unlocks");
wardrobe.SetAutomatic(true, now);
Check(wardrobe.Saved.Outfit == 1, "auto mode equips latest milestone");
Check(wardrobe.Equip(null, now) && wardrobe.Saved.Outfit == null, "original appearance selectable");
var cycle = New(10099); cycle.Press(now);
Check(cycle.Unlocked == 100 && cycle.Saved.Outfit == 0, "collection cycles after all hundred");
var actions = New(); actions.React("rest", now, 8); actions.Press(now.AddMilliseconds(1));
Check(actions.Animation(now.AddMilliseconds(1)).State == "typing", "input interrupts long pose immediately");
for (int i = 0; i < 8; i++) actions.Press(now.AddMilliseconds(20 * (i + 1)));
Check(actions.Animation(now.AddMilliseconds(180)).State == "fast", "fast feedback");
var deleting = New(); for (int i = 0; i < 3; i++) deleting.Press(now.AddMilliseconds(i * 100), true);
Check(deleting.Animation(now.AddMilliseconds(210)).State == "deleting", "repeated deletion feedback");

var reminders = New();
Check(!reminders.AddReminder("", now.AddMinutes(1), now), "empty reminder rejected");
Check(!reminders.AddReminder("a", now, now), "past time rejected");
Check(!reminders.AddReminder(new string('x', 201), now.AddMinutes(1), now), "title bounded");
Check(reminders.AddReminder("喝水", now.AddMinutes(1), now), "reminder scheduled");
Check(reminders.Due(now).Count == 0 && reminders.Due(now.AddMinutes(1)).Count == 1, "reminder due exactly on time");
var id = reminders.Saved.Reminders[0].Id;
reminders.ActOnReminder(id, "snooze", now.AddMinutes(1));
Check(reminders.Due(now.AddMinutes(10)).Count == 0 && reminders.Due(now.AddMinutes(11)).Count == 1, "ten-minute snooze");
reminders.ActOnReminder(id, "ack", now.AddMinutes(11));
Check(reminders.Due(now.AddHours(1)).Count == 0 && !reminders.Saved.Reminders[0].Done, "acknowledgement distinct from completion");
Check(reminders.AddReminder("伸懒腰", now.AddMinutes(30), now, id) && reminders.Saved.Reminders.Count == 1, "edit reuses reminder");
reminders.ActOnReminder(id, "done", now.AddMinutes(31));
Check(reminders.Due(now.AddHours(1)).Count == 0 && reminders.Saved.Reminders[0].Done, "completed reminder never alerts again");
reminders.ActOnReminder(id, "delete", now);
Check(reminders.Saved.Reminders.Count == 0, "delete removes reminder");
var rest = New(); rest.Saved.RestMinutes = 20;
for (int s = 1; s <= 1200; s++) { var t = now.AddSeconds(s); rest.Activity(t); rest.Tick(t); }
Check(rest.RestDue, "continuous activity prompts break");
rest.Rest(now.AddSeconds(1200), true);
Check(!rest.RestDue, "rest snooze dismisses current prompt");
rest.Tick(now.AddSeconds(1600));
Check(!rest.RestDue, "five-minute inactivity resets work session");
var invalid = new PetModel(new SaveState { SleepSeconds = 1, RestMinutes = -1, Size = double.NaN, Outfit = 900 }, now);
Check(invalid.Saved.SleepSeconds == 60 && invalid.Saved.RestMinutes == 45 && invalid.Saved.Size == 1 && invalid.Saved.Outfit == null, "invalid preferences recovered");

var folder = Path.Combine(Path.GetTempPath(), "qiaoqiao-tests-" + Guid.NewGuid()); Directory.CreateDirectory(folder);
try
{
    string path = Path.Combine(folder, "state.json");
    var saved = New(530); saved.Equip(2, now); saved.AddReminder("待办", now.AddDays(1), now);
    StateStore.Save(path, saved.Saved); var restored = new PetModel(StateStore.Load(path), now);
    Check(restored.Saved.Count == 530 && restored.Saved.Outfit == 2 && restored.Saved.Reminders.Count == 1, "progress and reminder round trip");
    Check(restored.Rate(now) == 0, "restart does not invent rolling rate");
    StateStore.Save(path, saved.Saved); File.WriteAllText(path, "broken");
    Check(StateStore.Load(path).Lifetime == 530, "backup restores corrupted save");
    File.WriteAllText(path + ".bak", "broken");
    Check(StateStore.Load(path).Count == 0, "invalid saves start safely");
    string json = JsonSerializer.Serialize(saved.Saved);
    Check(!json.Contains("scan") && !json.Contains("VirtualKey") && !json.Contains("trajectory"), "save contains no key identities or pointer trajectory");
}
finally { Directory.Delete(folder, true); }

var repo = args.FirstOrDefault();
if (repo != null)
{
    using var catalog = JsonDocument.Parse(File.ReadAllText(Path.Combine(repo, "assets/catalog.json")));
    var outfits = catalog.RootElement.GetProperty("outfits"); var states = catalog.RootElement.GetProperty("states");
    Check(outfits.GetArrayLength() == 100, "exported hundred outfits");
    foreach (var o in outfits.EnumerateArray()) foreach (var layer in o.GetProperty("layers").EnumerateArray())
        Check(File.Exists(Path.Combine(repo, $"assets/outfits/{o.GetProperty("id").GetInt32()}-{layer.GetString()}.png")), "outfit layer exists");
    foreach (var state in states.EnumerateObject())
    {
        Check(state.Value.GetProperty("rig").GetArrayLength() == 4, "four registered rig anchors");
        for (int i = 0; i < 4; i++) Check(File.Exists(Path.Combine(repo, $"macos/Assets/Frames/{state.Name}_{i}.png")), "sprite exists");
    }
    var sleeping = states.GetProperty("sleeping");
    Check(sleeping.GetProperty("exposures").GetArrayLength() == 1 && sleeping.GetProperty("exposures")[0][0].GetInt32() == 1, "sleep holds closed eyes");
    Check(!states.GetProperty("drowsy").GetProperty("loops").GetBoolean(), "drowsy animation runs once");
}
Console.WriteLine($"QiaoQiao core/assets: {checks - failures.Count}/{checks} passed");
foreach (var failure in failures) Console.Error.WriteLine("FAIL: " + failure);
return failures.Count == 0 ? 0 : 1;
