using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using Microsoft.Win32;
using QiaoQiao.Core;

namespace QiaoQiao;

internal static class Program
{
    [STAThread] public static int Main(string[] args)
    {
        bool smoke = args.Contains("--smoke-test"), render = args.Contains("--render-previews");
        using var mutex = new Mutex(true, smoke || render ? $"Local\\QiaoQiao.Test.{Guid.NewGuid()}" : "Local\\QiaoQiao.Desktop", out bool created);
        if (!created) { MessageBox.Show("敲敲已经在陪你啦。可以在系统托盘里找到它。", "敲敲"); return 0; }
        try
        {
            var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
            string? testRoot = smoke || render ? Path.Combine(Path.GetTempPath(), "QiaoQiao-" + Guid.NewGuid()) : null;
            var window = new PetWindow(testRoot, smoke, render ? args.Last() : null);
            app.Run(window);
            return window.SmokeSucceeded ? 0 : 1;
        }
        catch (Exception e)
        {
            if (smoke || render) Console.Error.WriteLine(e);
            string folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "QiaoQiao");
            Directory.CreateDirectory(folder);
            // Only exception type/message, never input or user reminder contents.
            File.WriteAllText(Path.Combine(folder, "startup-error.txt"), e.GetType().Name + ": " + e.Message);
            if (!smoke && !render) MessageBox.Show("敲敲没能启动。请确认已完整解压下载包，再运行 QiaoQiao.exe。\n" + e.Message, "敲敲");
            return 1;
        }
    }
}

internal sealed class PetWindow : Window
{
    internal readonly PetModel Model;
    internal readonly Catalog Catalog;
    internal readonly PetVisual Pet;
    private readonly string savePath;
    private readonly DispatcherTimer clock = new() { Interval = TimeSpan.FromSeconds(1.0 / 24) };
    private RawInput? input;
    private HwndSource? source;
    private System.Windows.Forms.NotifyIcon? tray;
    private DateTimeOffset lastSave, lastReminderPoll;
    private Window? wardrobeWindow, reminderWindow, balloon;
    private Guid? balloonReminder;
    private string? balloonTitle;
    private DateTimeOffset balloonDue;
    private Point? dragStart;
    private Native.Rect dragRect;
    private bool resizing, moved, settingSize, wasPausedForLock;
    private double resizeStart;
    private readonly bool smoke;
    private readonly string? renderPath;
    private readonly string? testRoot;
    public bool SmokeSucceeded { get; private set; } = true;
    private bool ReadyToClose;

    public PetWindow(string? testRoot, bool smoke, string? renderPath)
    {
        this.testRoot = testRoot; this.smoke = smoke; this.renderPath = renderPath;
        savePath = Path.Combine(testRoot ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "QiaoQiao"), "state.json");
        Model = new PetModel(StateStore.Load(savePath), DateTimeOffset.Now);
        Catalog = Catalog.Load(); Pet = new PetVisual(Model, Catalog);
        Title = "敲敲"; Width = 264; Height = 236;
        WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = System.Windows.Media.Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize; ShowInTaskbar = false; ShowActivated = false; Topmost = true;
        Content = new System.Windows.Controls.Viewbox { Child = Pet, Stretch = System.Windows.Media.Stretch.Uniform };
        SourceInitialized += (_, _) => InitializeNative();
        MouseLeftButtonDown += OnDown; MouseMove += OnMove; MouseLeftButtonUp += OnUp;
        LostMouseCapture += (_, _) => { if (dragStart != null) FinishDrag(); };
        MouseRightButtonUp += (_, e) => { Menu().IsOpen = true; e.Handled = true; };
        MouseEnter += (_, _) => { Pet.Hovered = true; Pet.InvalidateVisual(); };
        MouseLeave += (_, _) => { Pet.Hovered = false; Pet.InvalidateVisual(); };
        clock.Tick += (_, _) => Pulse();
        Closed += (_, _) => Cleanup();
        SystemEvents.DisplaySettingsChanged += DisplayChanged;
        SystemEvents.SessionSwitch += SessionChanged;
        SystemEvents.PowerModeChanged += PowerChanged;
        Loaded += (_, _) =>
        {
            ApplySize(true);
            if (renderPath != null) { RenderPreviews(renderPath); Close(); }
            else if (smoke)
            {
                var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
                timer.Tick += (_, _) => { timer.Stop(); RunSmoke(); Close(); }; timer.Start();
            }
        };
    }
    private void InitializeNative()
    {
        var handle = new WindowInteropHelper(this).Handle;
        Native.SetWindowLongPtr(handle, -20, new IntPtr(Native.GetWindowLongPtr(handle, -20).ToInt64() | 0x08000080));
        source = HwndSource.FromHwnd(handle)!;
        source.AddHook((IntPtr hwnd, int msg, IntPtr w, IntPtr l, ref bool handled) =>
        { if (msg == 0x2E0 && !settingSize) Dispatcher.BeginInvoke(() => ApplySize()); return IntPtr.Zero; });
        input = new RawInput(source, Model, () => Pet.InvalidateVisual()); Pet.Connected = input.Connected;
        if (!smoke && renderPath == null)
        {
            tray = new System.Windows.Forms.NotifyIcon { Text = "敲敲", Icon = new System.Drawing.Icon(Path.Combine(AppContext.BaseDirectory, "AppIcon.ico")), Visible = true };
            tray.MouseClick += (_, e) => Dispatcher.Invoke(() => { if (e.Button == System.Windows.Forms.MouseButtons.Left) { Show(); ApplySize(); Model.Say("我回来啦。", DateTimeOffset.Now); } else { var menu = Menu(); menu.Placement = System.Windows.Controls.Primitives.PlacementMode.MousePoint; menu.IsOpen = true; } });
        }
        Model.Say(input.Connected ? "听见你的键盘啦！" : "输入连接失败，点数字重试。", DateTimeOffset.Now);
        clock.Start();
    }
    private void Pulse()
    {
        var now = DateTimeOffset.Now; Model.Tick(now);
        Pet.InvalidateVisual();
        if ((now - lastReminderPoll).TotalSeconds >= 1) { lastReminderPoll = now; PollReminder(now); }
        if (Model.Dirty && (now - lastSave).TotalSeconds >= 5) Save();
    }
    private void Save()
    {
        try
        {
            if (source != null && Native.GetWindowRect(source.Handle, out var r)) { Model.Saved.Left = r.Left; Model.Saved.Top = r.Top; }
            StateStore.Save(savePath, Model.Saved); Model.Dirty = false; lastSave = DateTimeOffset.Now;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Model.Say("进度暂时存不下来，请检查磁盘空间。", DateTimeOffset.Now); }
    }
    private void OnDown(object sender, MouseButtonEventArgs e)
    {
        if (source == null) return;
        Point p = e.GetPosition(Pet);
        if (p.Y >= 195 && p.X < 220 && (!Pet.Connected || Model.Paused))
        {
            if (Model.Paused) Model.SetPaused(false, DateTimeOffset.Now);
            if (!Pet.Connected) { input?.Register(); Pet.Connected = input?.Connected == true; Model.Say(Pet.Connected ? "听见你的键盘啦！" : $"输入连接失败（{input?.LastError}），请重新打开。", DateTimeOffset.Now); }
            e.Handled = true; return;
        }
        Native.GetCursorPos(out var cursor); dragStart = new Point(cursor.X, cursor.Y);
        Native.GetWindowRect(source.Handle, out dragRect); resizing = p.X >= 220 && p.Y >= 207; moved = false; resizeStart = Model.Saved.Size;
        CaptureMouse(); Model.React(resizing ? "resizing" : "petting", DateTimeOffset.Now, 10); Pet.InvalidateVisual(); e.Handled = true;
    }
    private void OnMove(object sender, MouseEventArgs e)
    {
        if (dragStart is not Point start || source == null) return;
        Native.GetCursorPos(out var cursor); double dx = cursor.X - start.X, dy = cursor.Y - start.Y;
        if (Math.Abs(dx) + Math.Abs(dy) < 4 && !moved) return;
        if (!moved) Model.Say(resizing ? "变大，还是变小？" : "诶？要搬家吗？", DateTimeOffset.Now);
        moved = true;
        if (resizing) { Model.Saved.Size = Math.Clamp(resizeStart * Math.Max(.2, (dragRect.Right - dragRect.Left + dx) / (dragRect.Right - dragRect.Left)), .5, 1.8); ApplySize(); }
        else Native.SetWindowPos(source.Handle, IntPtr.Zero, dragRect.Left + (int)dx, dragRect.Top + (int)dy, 0, 0, 0x15);
        Model.React(resizing ? "resizing" : "dragging", DateTimeOffset.Now, 10); Pet.InvalidateVisual(); e.Handled = true;
    }
    private void OnUp(object sender, MouseButtonEventArgs e) { if (dragStart != null) FinishDrag(); e.Handled = true; }
    private void FinishDrag()
    {
        dragStart = null; ReleaseMouseCapture(); ApplySize(); Model.Dirty = true;
        Model.React("petting", DateTimeOffset.Now);
        Model.Say(resizing ? "这个大小刚刚好。" : moved ? "这里也不错。" : "喵～在呢。", DateTimeOffset.Now); Save();
    }
    internal void ApplySize(bool restore = false)
    {
        if (source == null || settingSize) return; settingSize = true;
        try
        {
            Native.GetWindowRect(source.Handle, out var r);
            var screen = System.Windows.Forms.Screen.FromHandle(source.Handle);
            if (restore && Model.Saved.Left is double lx && Model.Saved.Top is double ly && double.IsFinite(lx) && double.IsFinite(ly)) screen = System.Windows.Forms.Screen.FromPoint(new System.Drawing.Point((int)Math.Clamp(lx, -100000, 100000), (int)Math.Clamp(ly, -100000, 100000)));
            var area = screen.WorkingArea;
            var monitor = Native.MonitorFromPoint(new Native.Point(area.Left + area.Width / 2, area.Top + area.Height / 2), 2);
            Native.GetDpiForMonitor(monitor, 0, out uint dpi, out _); if (dpi == 0) dpi = 96;
            double factor = dpi / 96.0;
            double aw = area.Width / factor, ah = area.Height / factor;
            double recommended = Math.Clamp(Math.Min(aw / 1440, ah / 900) * .9, .8, 1.25);
            double margin = Math.Min(16, Math.Min(aw, ah) * .04);
            double scale = Math.Min(recommended * Model.Saved.Size, Math.Min((aw - margin * 2) / 264, (ah - margin * 2) / 236));
            Width = 264 * scale; Height = 236 * scale;
            int w = (int)Math.Round(Width * factor), h = (int)Math.Round(Height * factor);
            int x = restore ? (int)(Model.Saved.Left ?? area.Right - w - 25) : r.Left;
            int y = restore ? (int)(Model.Saved.Top ?? area.Bottom - h - 25) : r.Top;
            x = Math.Clamp(x, area.Left, Math.Max(area.Left, area.Right - w)); y = Math.Clamp(y, area.Top, Math.Max(area.Top, area.Bottom - h));
            Native.SetWindowPos(source.Handle, IntPtr.Zero, x, y, w, h, 0x14);
        }
        finally { settingSize = false; }
    }
    private void DisplayChanged(object? sender, EventArgs e) => Dispatcher.BeginInvoke(() => { ApplySize(); Model.Say("新屏幕，调整好啦。", DateTimeOffset.Now); });
    private void SessionChanged(object sender, SessionSwitchEventArgs e) => Dispatcher.BeginInvoke(() =>
    {
        input?.Reset();
        if (e.Reason == SessionSwitchReason.SessionLock) { wasPausedForLock = Model.Paused; Model.SetPaused(true, DateTimeOffset.Now); }
        if (e.Reason == SessionSwitchReason.SessionUnlock) { Model.SetPaused(wasPausedForLock, DateTimeOffset.Now); input?.Register(); }
    });
    private void PowerChanged(object sender, PowerModeChangedEventArgs e) => Dispatcher.BeginInvoke(() => { input?.Reset(); Model.Activity(DateTimeOffset.Now); if (e.Mode == PowerModes.Resume) input?.Register(); });
    private System.Windows.Controls.ContextMenu Menu()
    {
        var menu = new System.Windows.Controls.ContextMenu();
        System.Windows.Controls.MenuItem Add(string title, Action action, bool? check = null)
        {
            var i = new System.Windows.Controls.MenuItem { Header = title, IsCheckable = check != null, IsChecked = check == true }; i.Click += (_, _) => action(); menu.Items.Add(i); return i;
        }
        Add(IsVisible ? "隐藏敲敲（托盘可找回）" : "显示敲敲", () => { if (IsVisible) Hide(); else { Show(); ApplySize(); } });
        Add(Model.Paused ? "继续计数" : "暂停计数", () => Model.SetPaused(!Model.Paused, DateTimeOffset.Now));
        Add("小衣柜…", OpenWardrobe); Add("定时提醒…", OpenReminders);
        var size = Add("大小", () => { });
        foreach (double v in new[] { .5, .75, 1, 1.25, 1.5, 1.8 })
        { var i = new System.Windows.Controls.MenuItem { Header = $"{v:P0}" + (v == 1 ? " · 推荐" : ""), IsCheckable = true, IsChecked = Math.Abs(Model.Saved.Size - v) < .01 }; i.Click += (_, _) => { Model.Saved.Size = v; Model.Dirty = true; ApplySize(); Model.React("resizing", DateTimeOffset.Now); Model.Say("这个大小刚刚好。", DateTimeOffset.Now); }; size.Items.Add(i); }
        var sleep = Add("多久后睡觉", () => { });
        foreach (int s in new[] { 30, 60, 120 }) { var i = new System.Windows.Controls.MenuItem { Header = $"{s} 秒", IsCheckable = true, IsChecked = Model.Saved.SleepSeconds == s }; i.Click += (_, _) => { Model.Saved.SleepSeconds = s; Model.Dirty = true; Model.Say("记住啦。", DateTimeOffset.Now); }; sleep.Items.Add(i); }
        var rest = Add("休息提醒", () => { });
        foreach (int m in new[] { 0, 20, 30, 45, 60 }) { var i = new System.Windows.Controls.MenuItem { Header = m == 0 ? "关闭" : $"{m} 分钟", IsCheckable = true, IsChecked = Model.Saved.RestMinutes == m }; i.Click += (_, _) => { Model.Saved.RestMinutes = m; Model.Rest(DateTimeOffset.Now); Model.Dirty = true; }; rest.Items.Add(i); }
        Add("减少动画", () => { Model.Saved.ReducedMotion = !Model.Saved.ReducedMotion; Model.Dirty = true; Model.Say("记住啦。", DateTimeOffset.Now); }, Model.Saved.ReducedMotion);
        Add(Pet.Connected ? "输入已连接 · 按键＋鼠标点击" : "输入未连接 · 点击重试", () => { input?.Register(); Pet.Connected = input?.Connected == true; Model.Say(Pet.Connected ? "听见你的键盘啦！" : "请重新打开敲敲再试。", DateTimeOffset.Now); });
        menu.Items.Add(new System.Windows.Controls.Separator());
        Add("打开项目主页", () => Process.Start(new ProcessStartInfo("https://github.com/Eiternal/qiaoqiao") { UseShellExecute = true }));
        Add("退出敲敲", Close);
        menu.PlacementTarget = Pet; return menu;
    }
    private void OpenWardrobe() { if (wardrobeWindow == null) { wardrobeWindow = Editors.Wardrobe(this); wardrobeWindow.Closed += (_, _) => wardrobeWindow = null; } wardrobeWindow.Show(); wardrobeWindow.Activate(); Model.Say("来看看我的小衣柜。", DateTimeOffset.Now); }
    private void OpenReminders() { if (reminderWindow == null) { reminderWindow = Editors.Reminders(this); reminderWindow.Closed += (_, _) => reminderWindow = null; } reminderWindow.Show(); reminderWindow.Activate(); Model.Say("告诉我，到点叫你。", DateTimeOffset.Now); }
    private void PollReminder(DateTimeOffset now)
    {
        var due = Model.Due(now);
        if (balloon != null)
        {
            var item = balloonReminder == null ? null : due.FirstOrDefault(r => r.Id == balloonReminder);
            if (balloonReminder == null ? Model.RestDue : item != null && item.Title == balloonTitle && item.Due == balloonDue) return;
            balloon.Close();
        }
        if (due.Count == 0 && !Model.RestDue) { Pet.ReminderVisible = false; return; }
        if (!IsVisible) Show();
        var first = due.FirstOrDefault();
        balloonReminder = first?.Id; balloonTitle = first?.Title; balloonDue = first?.Due ?? default;
        balloon = Editors.Balloon(this, first, due.Count);
        balloon.Closed += (_, _) => { balloon = null; Pet.ReminderVisible = false; };
        Pet.ReminderVisible = true; balloon.Show();
    }
    private void Cleanup()
    {
        if (ReadyToClose) return; ReadyToClose = true; clock.Stop(); Save();
        input?.Dispose(); tray?.Dispose(); wardrobeWindow?.Close(); reminderWindow?.Close(); balloon?.Close();
        SystemEvents.DisplaySettingsChanged -= DisplayChanged; SystemEvents.SessionSwitch -= SessionChanged; SystemEvents.PowerModeChanged -= PowerChanged;
        if (testRoot != null && Directory.Exists(testRoot)) Directory.Delete(testRoot, true);
    }
    private void RunSmoke()
    {
        string folder = Path.GetFullPath("artifacts/windows-smoke"); Directory.CreateDirectory(folder);
        var now = DateTimeOffset.Now;
        Model.Press(now); Pet.InvalidateVisual(); Pet.UpdateLayout();
        Pet.Export(Path.Combine(folder, "live-typing.png"));
        bool connected = input?.Connected == true;
        bool contact = Pet.LastDrawnState == "typing" && Pet.LastDrawnCel is 1 or 3;
        var report = new { version = "0.9.4", registeredRawInput = connected, inputError = input?.LastError, physicalInputTested = false, callbackCount = Model.Saved.Count, immediateContact = contact, sprites = Catalog.States.Count * 4, outfits = Catalog.Outfits.Length, windowVisible = IsVisible, width = ActualWidth, height = ActualHeight };
        File.WriteAllText(Path.Combine(folder, "report.json"), JsonSerializer.Serialize(report, StateStore.JsonOptions));
        SmokeSucceeded = connected && contact && IsVisible && Catalog.Outfits.Length == 100 && Catalog.States.Count == 12;
        RenderPreviews(folder);
    }
    private void RenderPreviews(string folder)
    {
        Directory.CreateDirectory(folder);
        var export = new PetVisual(Model, Catalog) { Preview = true };
        var host = new Window { Width = 264, Height = 236, WindowStyle = WindowStyle.None, ShowActivated = false, ShowInTaskbar = false, Content = export };
        host.Show();
        foreach (string state in Catalog.States.Keys) { export.PreviewState = state; export.PreviewElapsed = state == "sleeping" ? .8 : .12; export.PreviewOutfit = 12; export.Export(Path.Combine(folder, state + ".png")); }
        for (int id = 0; id < Catalog.Outfits.Length; id++) { export.PreviewOutfit = id; export.PreviewState = "idle"; export.Export(Path.Combine(folder, $"outfit-{id:D2}.png")); }
        host.Close();
    }
}

internal static class Native
{
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct Point(int x, int y) { public int X = x, Y = y; }
    [DllImport("user32.dll")] public static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll")] public static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int w, int h, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(Point point, uint flags);
    [DllImport("shcore.dll")] public static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint dpiX, out uint dpiY);
}
