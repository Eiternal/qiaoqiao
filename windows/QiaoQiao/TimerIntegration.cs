using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Text.Json;
using QiaoQiao.Core;

namespace QiaoQiao;

internal sealed partial class PetWindow
{
    internal readonly TimerBook Timers;
    private Window? timerWindow, timerBalloon;
    private Guid? activeTimer;
    private bool hadPomodoro;
    internal void OpenTimers()
    {
        if (timerWindow == null) { timerWindow = Editors.Timers(this); timerWindow.Closed += (_, _) => timerWindow = null; }
        timerWindow.Show(); timerWindow.Activate(); Model.Say("给时间安排个小位置。", DateTimeOffset.Now); Model.React("petting", DateTimeOffset.Now);
    }
    internal void TimersChanged(string line)
    {
        Model.Dirty = true; UpdateTimerDisplay(); PollTimers(DateTimeOffset.Now); Save();
        Model.Say(line, DateTimeOffset.Now); Model.React("petting", DateTimeOffset.Now); Pet.InvalidateVisual();
    }
    private void UpdateTimerDisplay()
    {
        Pet.TimerDisplay = Timers.Display;
        if (Pet.Height != Pet.LogicalHeight && dragStart == null) { Pet.Height = Pet.LogicalHeight; ApplySize(); }
    }
    private void PollTimers(DateTimeOffset now)
    {
        if (Timers.Tick(now)) { Model.Dirty = true; Save(); }
        bool activePomodoro = Timers.Items.Any(t => t.Kind == TimerKind.Pomodoro && t.Active);
        if (hadPomodoro && !activePomodoro) Model.Rest(now);
        hadPomodoro = activePomodoro; UpdateTimerDisplay();
        if (timerBalloon != null)
        {
            if (Timers.Pending.Any(t => t.Id == activeTimer)) return;
            timerBalloon.Close();
        }
        if (hadPomodoro && balloon != null && balloonReminder == null) balloon.Close();
        if (balloon != null || dragStart != null || ReadyToClose) return;
        var pending = Timers.Pending; if (pending.Count == 0) return;
        var timer = pending[0]; activeTimer = timer.Id;
        timerBalloon = Editors.TimerBalloon(this, timer, pending.Count);
        timerBalloon.Closed += (_, _) => { timerBalloon = null; activeTimer = null; Pet.ReminderVisible = balloon != null; };
        if (!IsVisible) Show(); Pet.ReminderVisible = true; timerBalloon.Show();
    }
    private bool RunTimerSmoke(string folder)
    {
        long count = Model.Saved.Count; var now = DateTimeOffset.Now;
        Timers.Countdown("喝水", 180, now); Timers.Workday(now.AddHours(1), false, now);
        var id = Timers.Pomodoro(now); UpdateTimerDisplay(); Pet.Export(Path.Combine(folder, "timer-badge.png"));
        var editor = Editors.Timers(this); editor.Show(); editor.UpdateLayout();
        CaptureTimerWindow(editor, Path.Combine(folder, "timer-center.png"));
        static IEnumerable<T> Find<T>(DependencyObject root) where T : DependencyObject
        {
            for (int i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
            {
                var child = VisualTreeHelper.GetChild(root, i); if (child is T match) yield return match;
                foreach (var nested in Find<T>(child)) yield return nested;
            }
        }
        var pause = Find<Button>(editor).First(b => b.Content as string == "暂停");
        pause.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); bool paused = Timers.Items.First(t => t.Id == id).State == TimerState.Paused;
        pause.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); bool resumed = Timers.Items.First(t => t.Id == id).State == TimerState.Running;
        var tabs = Find<TabControl>(editor).First(); tabs.SelectedIndex = 2; editor.UpdateLayout();
        CaptureTimerWindow(editor, Path.Combine(folder, "pomodoro-settings.png")); editor.Close();
        Timers.Tick(DateTimeOffset.Now.AddSeconds(1501)); var pomo = Timers.Items.First(t => t.Id == id);
        bool waits = pomo.State == TimerState.Awaiting && pomo.CompletedFocus == 1;
        var completion = Editors.TimerBalloon(this, pomo, 1); completion.Show(); completion.UpdateLayout();
        CaptureTimerWindow(completion, Path.Combine(folder, "pomodoro-complete.png"));
        bool noActivate = !completion.ShowActivated && !completion.IsActive; completion.Close();
        bool noCounts = Model.Saved.Count == count;
        File.WriteAllText(Path.Combine(folder, "timer-report.json"), JsonSerializer.Serialize(new { pauseButton = paused, resumeButton = resumed, waitsForConfirmation = waits, timerCannotCreateInputCounts = noCounts, nonActivatingReminder = noActivate, badgeHeight = Pet.LogicalHeight }, StateStore.JsonOptions));
        return paused && resumed && waits && noCounts && noActivate;
    }
    private static void CaptureTimerWindow(Window window, string path)
    {
        window.UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(window.ActualWidth), (int)Math.Ceiling(window.ActualHeight), 96, 96, PixelFormats.Pbgra32); bitmap.Render(window);
        var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(bitmap)); using var file = File.Create(path); png.Save(file);
    }
}
