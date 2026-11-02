using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using QiaoQiao.Core;

namespace QiaoQiao;

internal static class Editors
{
    private static readonly Brush Cream = PetVisual.ColorBrush(0xFFFAF2);
    private static Window Window(string title, double w, double h)
        => new() { Title = title, Width = w, Height = h, MinWidth = 360, MinHeight = 260, Background = Cream, FontFamily = new FontFamily("Microsoft YaHei UI"), FontSize = 13, WindowStartupLocation = WindowStartupLocation.CenterScreen };
    private static TextBlock Label(string text, double size = 13) => new() { Text = text, FontSize = size, Foreground = PetVisual.Ink, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 8) };
    private static Button Button(string title, Action action)
    { var b = new Button { Content = title, Padding = new Thickness(12, 7, 12, 7), Margin = new Thickness(0, 4, 8, 4) }; b.Click += (_, _) => action(); return b; }

    internal static Window Wardrobe(PetWindow owner)
    {
        var window = Window("敲敲 · 小衣柜", 660, 580);
        var root = new DockPanel { Margin = new Thickness(18) }; window.Content = root;
        var top = new StackPanel(); DockPanel.SetDock(top, Dock.Top); root.Children.Add(top);
        top.Children.Add(Label($"已收集 {owner.Model.Unlocked}/100 · 每 100 次按下解锁一套", 18));
        var automatic = new CheckBox { Content = "解锁后自动换装", IsChecked = owner.Model.Saved.Automatic, Margin = new Thickness(0, 8, 0, 10) };
        automatic.Checked += (_, _) => owner.Model.SetAutomatic(true, DateTimeOffset.Now);
        automatic.Unchecked += (_, _) => owner.Model.SetAutomatic(false, DateTimeOffset.Now); top.Children.Add(automatic);
        top.Children.Add(Button("原来的样子", () => owner.Model.Equip(null, DateTimeOffset.Now)));
        var tabs = new TabControl(); root.Children.Add(tabs);
        var preview = new PetVisual(owner.Model, owner.Catalog) { Preview = true, PreviewState = "idle", PreviewElapsed = 0 };
        for (int theme = 0; theme < 10; theme++)
        {
            var wrap = new WrapPanel();
            foreach (var outfit in owner.Catalog.Outfits.Where(o => o.Theme == theme))
            {
                preview.PreviewOutfit = outfit.Id; preview.Measure(new Size(264, 236)); preview.Arrange(new Rect(0, 0, 264, 236)); preview.InvalidateVisual(); preview.UpdateLayout();
                var bitmap = new RenderTargetBitmap(264, 236, 96, 96, PixelFormats.Pbgra32); bitmap.Render(preview); bitmap.Freeze();
                var stack = new StackPanel { Width = 150 };
                stack.Children.Add(new Image { Source = bitmap, Width = 140, Height = 125 });
                bool unlocked = outfit.Id < owner.Model.Unlocked;
                stack.Children.Add(new TextBlock { Text = unlocked ? outfit.Name : $"{(outfit.Id + 1) * 100:N0} 次解锁", TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap });
                int id = outfit.Id;
                var button = new Button { Content = stack, IsEnabled = unlocked, Opacity = unlocked ? 1 : .45, Margin = new Thickness(5), Padding = new Thickness(2), ToolTip = outfit.Name };
                button.Click += (_, _) => { owner.Model.Equip(id, DateTimeOffset.Now); owner.Pet.InvalidateVisual(); };
                wrap.Children.Add(button);
            }
            tabs.Items.Add(new TabItem { Header = owner.Catalog.Themes[theme], Content = new ScrollViewer { Content = wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto } });
        }
        return window;
    }

    internal static Window Reminders(PetWindow owner)
    {
        var window = Window("敲敲 · 定时提醒", 620, 580);
        var root = new DockPanel { Margin = new Thickness(20) }; window.Content = root;
        var editor = new StackPanel(); DockPanel.SetDock(editor, Dock.Top); root.Children.Add(editor);
        editor.Children.Add(Label("到点，叫你一声。", 20));
        var title = new TextBox { MaxLength = 200, Padding = new Thickness(8), Margin = new Thickness(0, 6, 0, 6) };
        title.SetValue(System.Windows.Automation.AutomationProperties.NameProperty, "提醒事项"); editor.Children.Add(title);
        var soon = DateTime.Now.AddMinutes(5);
        var date = new DatePicker { SelectedDate = soon.Date, Width = 180, Margin = new Thickness(0, 0, 12, 0) };
        var time = new TextBox { Text = soon.ToString("HH:mm"), Width = 80, Padding = new Thickness(6) };
        time.SetValue(System.Windows.Automation.AutomationProperties.NameProperty, "提醒时间，24小时制");
        var line = new StackPanel { Orientation = Orientation.Horizontal }; line.Children.Add(date); line.Children.Add(time); editor.Children.Add(line);
        editor.Children.Add(Label("本地时间 · 需要保持敲敲运行；关机错过的提醒会在下次启动时出现。", 11));
        var error = Label(""); editor.Children.Add(error);
        var list = new ListBox { Margin = new Thickness(0, 12, 0, 0) };
        Guid? editing = null;
        void Refresh()
        {
            list.Items.Clear();
            foreach (var r in owner.Model.Saved.Reminders.OrderByDescending(r => r.Due))
                list.Items.Add(new ListBoxItem { Tag = r.Id, Content = new TextBlock { Text = $"{(r.Done ? "✓ " : "")}{r.Title}\n{r.Due.ToLocalTime():yyyy-MM-dd HH:mm}" + (r.Acknowledged && !r.Done ? " · 已看过" : ""), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(5) }, HorizontalContentAlignment = HorizontalAlignment.Stretch });
        }
        Guid? Selected() => (list.SelectedItem as ListBoxItem)?.Tag as Guid?;
        var buttons = new WrapPanel(); editor.Children.Add(buttons);
        buttons.Children.Add(Button("保存提醒", () =>
        {
            if (date.SelectedDate == null || !TimeOnly.TryParseExact(time.Text.Trim(), "H:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var t) && !TimeOnly.TryParseExact(time.Text.Trim(), "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out t))
            { error.Text = "请选日期，并按 09:30 这样的格式输入时间。"; return; }
            var local = DateTime.SpecifyKind(date.SelectedDate.Value.Date + t.ToTimeSpan(), DateTimeKind.Unspecified);
            if (TimeZoneInfo.Local.IsInvalidTime(local)) { error.Text = "这个时间处于夏令时跳过的时段，请换一个时间。"; return; }
            var due = new DateTimeOffset(local, TimeZoneInfo.Local.GetUtcOffset(local));
            bool ok = owner.Model.AddReminder(title.Text, due, DateTimeOffset.Now, editing);
            error.Text = ok ? "记好啦。" : "请填写 1–200 字的事项及未来时间，最多保存 200 条。";
            if (ok) { editing = null; title.Clear(); Refresh(); }
        }));
        buttons.Children.Add(Button("新建", () => { editing = null; title.Clear(); error.Text = ""; title.Focus(); }));
        buttons.Children.Add(Button("编辑", () =>
        {
            var r = owner.Model.Saved.Reminders.FirstOrDefault(r => r.Id == Selected()); if (r == null) return;
            editing = r.Id; title.Text = r.Title; date.SelectedDate = r.Due.LocalDateTime.Date; time.Text = r.Due.ToLocalTime().ToString("HH:mm"); title.Focus(); error.Text = "编辑后点击保存提醒。";
        }));
        buttons.Children.Add(Button("完成", () => { if (Selected() is Guid id) owner.Model.ActOnReminder(id, "done", DateTimeOffset.Now); Refresh(); }));
        buttons.Children.Add(Button("十分钟后", () => { if (Selected() is Guid id) owner.Model.ActOnReminder(id, "snooze", DateTimeOffset.Now); Refresh(); }));
        buttons.Children.Add(Button("删除", () => { if (Selected() is Guid id) owner.Model.ActOnReminder(id, "delete", DateTimeOffset.Now); Refresh(); }));
        root.Children.Add(list); Refresh(); return window;
    }

    internal static Window Balloon(PetWindow owner, Reminder? reminder, int count)
    {
        var window = new Window { Title = "敲敲提醒", Width = 330, SizeToContent = SizeToContent.Height, MaxHeight = 380, WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent, ShowInTaskbar = false, ShowActivated = false, Topmost = true, ResizeMode = ResizeMode.NoResize };
        var border = new Border { Background = Cream, BorderBrush = PetVisual.ColorBrush(0xD7BFAE), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(18), Padding = new Thickness(18) };
        var stack = new StackPanel(); border.Child = stack; window.Content = border;
        stack.Children.Add(Label(reminder == null ? "陪你忙很久啦，休息一下？" : reminder.Title, 17));
        if (count > 1) stack.Children.Add(Label($"还有 {count - 1} 条提醒，处理这条后继续。", 11));
        var buttons = new WrapPanel(); stack.Children.Add(buttons);
        void Act(string action)
        {
            if (reminder == null) owner.Model.Rest(DateTimeOffset.Now, action == "snooze");
            else owner.Model.ActOnReminder(reminder.Id, action, DateTimeOffset.Now);
            window.Close();
        }
        buttons.Children.Add(Button(reminder == null ? "休息好了" : "完成", () => Act("done")));
        buttons.Children.Add(Button("十分钟后", () => Act("snooze")));
        if (reminder != null) buttons.Children.Add(Button("知道啦", () => Act("ack")));
        window.SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(window).Handle;
            Native.SetWindowLongPtr(handle, -20, new IntPtr(Native.GetWindowLongPtr(handle, -20).ToInt64() | 0x08000080));
            HwndSource.FromHwnd(handle)!.AddHook((IntPtr hwnd, int msg, IntPtr w, IntPtr l, ref bool handled) => { if (msg == 0x21) { handled = true; return new IntPtr(3); } return IntPtr.Zero; });
        };
        window.Loaded += (_, _) =>
        {
            var handle = new WindowInteropHelper(owner).Handle; Native.GetWindowRect(handle, out var r);
            var area = System.Windows.Forms.Screen.FromHandle(handle).WorkingArea;
            uint dpi = 96; var monitor = Native.MonitorFromPoint(new Native.Point(r.Left, r.Top), 2); Native.GetDpiForMonitor(monitor, 0, out dpi, out _); double f = dpi / 96.0;
            int w = (int)(window.ActualWidth * f), h = (int)(window.ActualHeight * f);
            int x = Math.Clamp(r.Right - w, area.Left, Math.Max(area.Left, area.Right - w));
            int y = r.Top - h >= area.Top ? r.Top - h : Math.Min(area.Bottom - h, r.Bottom);
            Native.SetWindowPos(new WindowInteropHelper(window).Handle, IntPtr.Zero, x, y, 0, 0, 0x15);
        };
        return window;
    }
}
