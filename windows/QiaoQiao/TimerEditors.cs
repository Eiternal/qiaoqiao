using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using QiaoQiao.Core;

namespace QiaoQiao;

internal static partial class Editors
{
    internal static Window Timers(PetWindow owner)
    {
        var window = Window("敲敲 · 小计时器", 740, 700);
        var content = new DockPanel { Margin = new Thickness(20) };
        // Vertical and horizontal scrolling preserve access at small desktop sizes.
        window.Content = new ScrollViewer { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto };
        content.MinWidth = 640;
        var top = new StackPanel(); DockPanel.SetDock(top, Dock.Top); content.Children.Add(top);
        top.Children.Add(Label("小计时器", 22)); top.Children.Add(Label("给工作收个尾，也给自己留点喘气的时间。"));
        var tabs = new TabControl { Height = 230, Margin = new Thickness(0, 8, 0, 8) }; top.Children.Add(tabs);
        var error = Label("");
        void Changed(string line) { error.Text = line; owner.TimersChanged(line); }
        void Perform(Action action)
        {
            try { action(); Changed("开始啦，到点我叫你。"); }
            catch (ArgumentException e) { error.Text = e.Message; }
        }
        StackPanel Tab(string title) { var s = new StackPanel { Margin = new Thickness(14) }; tabs.Items.Add(new TabItem { Header = title, Content = s }); return s; }
        TextBox Number(string initial, string name) { var v = new TextBox { Text = initial, Width = 50, Padding = new Thickness(6), Margin = new Thickness(3, 0, 10, 0) }; System.Windows.Automation.AutomationProperties.SetName(v, name); return v; }
        int Value(TextBox field) => int.TryParse(field.Text, NumberStyles.None, CultureInfo.InvariantCulture, out int v) ? v : throw new ArgumentException("请输入有效的整数时间。");
        var work = Tab("下班倒计时");
        var soon = DateTime.Today.AddHours(18); if (soon <= DateTime.Now) soon = soon.AddDays(1);
        var date = new DatePicker { SelectedDate = soon.Date, Width = 190, Margin = new Thickness(0, 0, 10, 0) };
        var time = new TextBox { Text = soon.ToString("HH:mm"), Width = 90, Padding = new Thickness(6) };
        var dateLine = new StackPanel { Orientation = Orientation.Horizontal }; dateLine.Children.Add(Label("下班时间  ")); dateLine.Children.Add(date); dateLine.Children.Add(time); work.Children.Add(dateLine);
        var repeat = new CheckBox { Content = "之后在工作日重复（周一至周五）", Margin = new Thickness(0, 14, 0, 6) }; work.Children.Add(repeat);
        work.Children.Add(Label("可选具体日期，跨夜下班也可以；首次时间以你的选择为准。", 11));
        work.Children.Add(Button("开始下班倒计时", () => Perform(() =>
        {
            if (date.SelectedDate == null || !TimeOnly.TryParseExact(time.Text.Trim(), "H:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var t) && !TimeOnly.TryParseExact(time.Text.Trim(), "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out t)) throw new ArgumentException("请选择日期并输入下班时间，例如 18:30。");
            var local = DateTime.SpecifyKind(date.SelectedDate.Value.Date + t.ToTimeSpan(), DateTimeKind.Unspecified);
            if (TimeZoneInfo.Local.IsInvalidTime(local)) throw new ArgumentException("这个时刻处于夏令时跳过的时段，请换一个时间。");
            owner.Timers.Workday(new DateTimeOffset(local, TimeZoneInfo.Local.GetUtcOffset(local)), repeat.IsChecked == true, DateTimeOffset.Now);
        })));
        var custom = Tab("自由倒计时");
        var title = new TextBox { MaxLength = 40, Padding = new Thickness(6), Margin = new Thickness(0, 0, 0, 12) }; custom.Children.Add(title);
        TextBox h = Number("0", "小时"), m = Number("20", "分钟"), s = Number("0", "秒");
        var duration = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var (v, unit) in new[] { (h, "时"), (m, "分"), (s, "秒") }) { duration.Children.Add(v); duration.Children.Add(Label(unit)); }
        custom.Children.Add(duration); custom.Children.Add(Label("可给喝水、煮面等小事命名；1 秒到 7 天，支持多个计时。", 11));
        custom.Children.Add(Button("开始倒计时", () => Perform(() =>
        {
            int hv = Value(h), mv = Value(m), sv = Value(s);
            if (hv is < 0 or > 168 || mv is < 0 or > 59 || sv is < 0 or > 59) throw new ArgumentException("小时 0–168，分钟和秒数 0–59。");
            owner.Timers.Countdown(title.Text, hv * 3600 + mv * 60 + sv, DateTimeOffset.Now);
        })));
        var pomo = Tab("番茄钟");
        TextBox focus = Number("25", "专注分钟"), shortBreak = Number("5", "短休息分钟"), longBreak = Number("15", "长休息分钟"), rounds = Number("4", "长休息轮数");
        var intervals = new WrapPanel();
        foreach (var (v, name) in new[] { (focus, "专注"), (shortBreak, "短休息"), (longBreak, "长休息") }) { intervals.Children.Add(Label(name)); intervals.Children.Add(v); intervals.Children.Add(Label("分钟  ")); }
        pomo.Children.Add(intervals);
        var roundLine = new StackPanel { Orientation = Orientation.Horizontal }; roundLine.Children.Add(Label("每")); roundLine.Children.Add(rounds); roundLine.Children.Add(Label("轮专注后长休息")); pomo.Children.Add(roundLine);
        pomo.Children.Add(Label("到点由我提醒，点击后进入下一段；番茄钟期间不重复提醒工作休息。", 11));
        pomo.Children.Add(Button("开始番茄钟", () => Perform(() => owner.Timers.Pomodoro(DateTimeOffset.Now, Value(focus) * 60.0, Value(shortBreak) * 60.0, Value(longBreak) * 60.0, Value(rounds)))));
        top.Children.Add(error);
        var badge = new CheckBox { Content = "在头像下显示选中的计时（仅图标＋时间）", IsChecked = owner.Timers.Saved.ShowBadge, Margin = new Thickness(0, 5, 0, 10) }; top.Children.Add(badge);
        badge.Checked += (_, _) => { owner.Timers.Saved.ShowBadge = true; Changed("计时显示记住啦。"); };
        badge.Unchecked += (_, _) => { owner.Timers.Saved.ShowBadge = false; Changed("计时先藏好，仍会到点提醒。"); };
        var list = new ListBox { MinHeight = 160, Margin = new Thickness(0, 0, 0, 8) }; content.Children.Add(list);
        var buttons = new WrapPanel(); DockPanel.SetDock(buttons, Dock.Bottom); content.Children.Insert(1, buttons);
        Guid? Selected() => (list.SelectedItem as ListBoxItem)?.Tag as Guid?;
        var pause = Button("暂停", () => { if (Selected() is Guid id && owner.Timers.Pause(id, DateTimeOffset.Now)) Changed("按你的节奏，暂停或继续啦。"); });
        var next = Button("下一阶段", () => { if (Selected() is Guid id && owner.Timers.Advance(id, DateTimeOffset.Now)) Changed("下一段开始啦。"); });
        buttons.Children.Add(Button("显示这个", () => { if (Selected() is Guid id) { owner.Timers.Saved.SelectedId = id; owner.Timers.Saved.ShowBadge = true; badge.IsChecked = true; Changed("这一项交给我盯着。"); } }));
        buttons.Children.Add(pause); buttons.Children.Add(next);
        buttons.Children.Add(Button("结束计时", () => { if (Selected() is Guid id && owner.Timers.Stop(id)) Changed("这一项先收起来啦。"); }));
        buttons.Children.Add(Button("删除", () => { if (Selected() is Guid id) { owner.Timers.Remove(id); Changed("已经划掉啦。"); } }));
        void UpdateButtons()
        {
            var t = owner.Timers.Items.FirstOrDefault(t => t.Id == Selected()); pause.IsEnabled = t?.CanPause == true; pause.Content = t?.State == TimerState.Paused ? "继续" : "暂停";
            next.IsEnabled = t?.State == TimerState.Awaiting; next.Content = t?.State == TimerState.Awaiting ? t.AdvanceTitle : "下一阶段";
        }
        void Refresh()
        {
            var selected = Selected() ?? owner.Timers.Saved.SelectedId; list.Items.Clear();
            foreach (var t in owner.Timers.Items)
            {
                string status = t.State == TimerState.Awaiting ? "到时间啦 · 等你确认" : t.State == TimerState.Finished ? "已结束" : t.State == TimerState.Paused ? "已暂停" : t.PhaseTitle + (t.Kind == TimerKind.Pomodoro ? $" · 已完成 {t.CompletedFocus} 轮" : "");
                var item = new ListBoxItem { Tag = t.Id, Content = $"{(owner.Timers.Display?.Id == t.Id ? "● " : "")}{t.Title}   {DeskTimer.TimeText(t.Seconds(DateTimeOffset.Now))}   {status}", Padding = new Thickness(6) }; list.Items.Add(item);
                if (t.Id == selected) list.SelectedItem = item;
            }
            if (list.SelectedItem == null && list.Items.Count > 0) list.SelectedIndex = 0; UpdateButtons();
        }
        list.SelectionChanged += (_, _) => UpdateButtons();
        var refresh = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1) }; refresh.Tick += (_, _) => Refresh();
        window.Closed += (_, _) => refresh.Stop(); refresh.Start(); Refresh(); return window;
    }

    internal static Window TimerBalloon(PetWindow owner, DeskTimer timer, int count)
    {
        var window = new Window { Title = "敲敲计时提醒", Width = 350, SizeToContent = SizeToContent.Height, MaxHeight = 380, WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent, ShowInTaskbar = false, ShowActivated = false, Topmost = true, ResizeMode = ResizeMode.NoResize };
        var stack = new StackPanel(); window.Content = new Border { Background = Cream, BorderBrush = PetVisual.ColorBrush(0xD7BFAE), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(18), Padding = new Thickness(18), Child = stack };
        stack.Children.Add(Label(timer.CompletionText, 17)); if (count > 1) stack.Children.Add(Label($"还有 {count - 1} 项计时到点。", 11));
        var buttons = new WrapPanel(); stack.Children.Add(buttons);
        void Act(int action)
        {
            window.Close();
            if (action == 0) owner.Timers.Advance(timer.Id, DateTimeOffset.Now);
            else if (action == 1 && timer.Kind == TimerKind.Countdown) owner.Timers.Restart(timer.Id, DateTimeOffset.Now);
            else if (action == 2 && timer.Kind != TimerKind.Countdown) owner.Timers.Stop(timer.Id);
            else owner.Timers.Acknowledge(timer.Id);
            owner.TimersChanged(action == 1 && timer.Kind == TimerKind.Countdown ? "再计一次，到点叫你。" : "记好啦，按自己的节奏来。");
            if (action == 1 && timer.Kind == TimerKind.Workday) owner.OpenTimers();
        }
        buttons.Children.Add(Button(timer.AdvanceTitle, () => Act(0)));
        buttons.Children.Add(Button(timer.Kind == TimerKind.Countdown ? "再计一次" : timer.Kind == TimerKind.Workday ? "计时列表" : "稍后查看", () => Act(1)));
        buttons.Children.Add(Button(timer.Kind == TimerKind.Countdown ? "稍后查看" : timer.Kind == TimerKind.Workday ? "结束计时" : "结束番茄", () => Act(2)));
        ConfigureBalloon(owner, window); return window;
    }
}
