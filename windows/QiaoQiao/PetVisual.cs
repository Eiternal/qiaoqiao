using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using QiaoQiao.Core;

namespace QiaoQiao;

internal sealed class Catalog
{
    public Outfit[] Outfits { get; set; } = [];
    public string[] Themes { get; set; } = [];
    public Dictionary<string, Cel> States { get; set; } = [];
    public static Catalog Load() => JsonSerializer.Deserialize<Catalog>(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Assets/catalog.json")), StateStore.JsonOptions)!;
}
internal sealed class Outfit
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public string Style { get; set; } = "";
    public int Theme { get; set; }
    public string[] Layers { get; set; } = [];
}
internal sealed class Cel
{
    public int[][] Exposures { get; set; } = [];
    public bool Loops { get; set; }
    public Rig[] Rig { get; set; } = [];
    public int Frame(double elapsed, bool reduced)
    {
        if (reduced) return Exposures.Length == 1 ? Exposures[0][0] : 0;
        int total = Exposures.Sum(e => e[1]);
        long ticks = (long)Math.Min(long.MaxValue / 2, Math.Floor(Math.Max(0, elapsed) * 24 + 1e-7));
        long tick = Loops ? ticks % total : Math.Min(total - 1, ticks);
        foreach (var e in Exposures) { if (tick < e[1]) return e[0]; tick -= e[1]; }
        return Exposures[^1][0];
    }
}
internal sealed class Rig { public double X { get; set; } public double Y { get; set; } public double Angle { get; set; } public double HeadScale { get; set; } public double FaceScale { get; set; } }

internal sealed class PetVisual : FrameworkElement
{
    public readonly PetModel Model;
    public readonly Catalog Catalog;
    public bool Connected { get; set; }
    public bool ReminderVisible { get; set; }
    public bool Hovered { get; set; }
    public string? PreviewState { get; set; }
    public double PreviewElapsed { get; set; }
    public int? PreviewOutfit { get; set; }
    public bool Preview { get; set; }
    public DeskTimer? TimerDisplay { get; set; }
    public double LogicalHeight => TimerDisplay == null ? 236 : 274;
    public string LastDrawnState { get; private set; } = "";
    public int LastDrawnCel { get; private set; }
    private readonly Dictionary<string, BitmapImage> images = [];
    internal static readonly Brush Ink = ColorBrush(0x51434E);
    internal static Brush ColorBrush(uint hex, byte alpha = 255)
    { var b = new SolidColorBrush(Color.FromArgb(alpha, (byte)(hex >> 16), (byte)(hex >> 8), (byte)hex)); b.Freeze(); return b; }
    public PetVisual(PetModel model, Catalog catalog)
    {
        Model = model; Catalog = catalog; Width = 264; Height = 236;
        foreach (var state in catalog.States.Keys) for (int i = 0; i < 4; i++) Image($"Frames/{state}_{i}.png");
        Focusable = false;
        System.Windows.Automation.AutomationProperties.SetName(this, "敲敲头像与按下计数");
    }
    private BitmapImage Image(string path)
    {
        if (images.TryGetValue(path, out var image)) return image;
        image = new BitmapImage(); image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad;
        image.UriSource = new Uri(Path.Combine(AppContext.BaseDirectory, "Assets", path)); image.EndInit(); image.Freeze(); images[path] = image;
        return image;
    }
    private void Layer(DrawingContext d, Outfit outfit, string layer, Rig rig)
    {
        if (!outfit.Layers.Contains(layer)) return;
        bool face = layer == "face" && outfit.Style != "astronaut";
        var transform = new TransformGroup();
        transform.Children.Add(new TranslateTransform(-132, -121));
        transform.Children.Add(new ScaleTransform(face ? rig.FaceScale : rig.HeadScale, rig.HeadScale));
        transform.Children.Add(new RotateTransform(rig.Angle * 180 / Math.PI));
        transform.Children.Add(new TranslateTransform(rig.X, rig.Y));
        d.PushClip(new RectangleGeometry(new Rect(18, 43, 228, 144)));
        d.PushTransform(transform); d.DrawImage(Image($"outfits/{outfit.Id}-{layer}.png"), new Rect(0, 0, 264, 236)); d.Pop(); d.Pop();
    }
    protected override void OnRender(DrawingContext d)
    {
        base.OnRender(d);
        var now = DateTimeOffset.Now;
        var (state, elapsed) = Model.Animation(now, ReminderVisible);
        if (PreviewState != null) { state = PreviewState; elapsed = PreviewElapsed; }
        bool reduced = Model.Saved.ReducedMotion || !SystemParameters.ClientAreaAnimation;
        var definition = Catalog.States[state];
        int cel = definition.Frame(elapsed, reduced);
        if (PreviewState == null && state is "typing" or "fast" or "deleting")
        {
            double age = Math.Max(0, (now - Model.LastPress).TotalSeconds);
            cel = state == "deleting" ? (age < .09 ? (Model.InputSerial % 2 == 0 ? 2 : 1) : 3) : age < .09 ? (Model.InputSerial % 2 == 0 ? 3 : 1) : (Model.InputSerial % 2 == 0 ? 2 : 0);
            if (reduced) cel = state == "deleting" ? 3 : 1;
        }
        LastDrawnState = state; LastDrawnCel = cel;
        // Transparent hit-test region is limited to the pet and numeric pill.
        d.DrawRoundedRectangle(Brushes.Transparent, null, new Rect(48, 46, 190, 146), 45, 45);
        if (Hovered) d.DrawEllipse(ColorBrush(0xE6CB9E, 33), null, new Point(132, 122), 76, 61.5);
        double breath = state == "sleeping" && !reduced ? (1 - Math.Cos(elapsed % 4.8 / 4.8 * 2 * Math.PI)) / 2 : 0;
        d.PushTransform(new ScaleTransform(1 + .003 * breath, 1 + .008 * breath, 132, 182));
        int? selected = Preview ? PreviewOutfit : Model.Saved.Outfit;
        var outfit = selected is int id ? Catalog.Outfits[id] : null;
        var rig = definition.Rig[cel];
        if (outfit != null) Layer(d, outfit, "behind", rig);
        d.DrawImage(Image($"Frames/{state}_{cel}.png"), new Rect(36, 32, 200, 160));
        if (outfit != null) { Layer(d, outfit, "hat", rig); Layer(d, outfit, "face", rig); }
        d.Pop();
        if (state == "sleeping")
            for (int i = 0; i < 3; i++)
            {
                double phase = reduced ? .5 : (elapsed / 3.2 + i * .23) % 1;
                d.PushOpacity(Math.Sin(phase * Math.PI) * .82);
                double x = 211 + i * 13, y = 109 - i * 21 - (reduced ? 0 : phase * 6), w = 7 + i * 3, h = 8 + i * 3;
                var g = new StreamGeometry(); using (var c = g.Open()) { c.BeginFigure(new Point(x, y), false, false); c.PolyLineTo([new Point(x + w, y), new Point(x, y + h), new Point(x + w, y + h)], true, false); }
                d.DrawGeometry(null, new Pen(ColorBrush(0xFFFAEF, 204), 3.4), g);
                d.DrawGeometry(null, new Pen(ColorBrush(0x98718C), 1.8), g); d.Pop();
            }
        if (state == "typing" && cel is 1 or 3 && !reduced)
            for (int i = -1; i <= 1; i++) { double x = (cel == 1 ? 107 : 157) + i * 7; d.DrawLine(new Pen(ColorBrush(0xDCAD50, 153), 1.5), new Point(x, 188), new Point(x + i * 2, 193)); }
        d.DrawRoundedRectangle(ColorBrush(0xFFFDF9, Model.Paused ? (byte)166 : (byte)240), new Pen(ColorBrush(0xE7DDE4, 204), 1), new Rect(24, 195, 216, 35), 16, 16);
        if (!Preview && (!Connected || Model.Paused)) d.DrawEllipse(ColorBrush(Model.Paused ? 0xB1A6AFu : 0xD39A42u), null, new Point(37, 212), 3, 3);
        string count = $"{Model.Saved.Count:N0}｜{Model.Rate(now)}/min";
        Text(d, count, 132, 202, count.Length > 19 ? 13 : count.Length > 16 ? 15 : 17, Ink, "Consolas");
        if (Hovered)
            for (int i = 0; i < 3; i++) d.DrawLine(new Pen(ColorBrush(0xA894A1, 150), 1.4), new Point(229 + i * 4, 224), new Point(237, 216 + i * 4));
        if (TimerDisplay is DeskTimer timer)
        {
            var accent = ColorBrush(timer.State == TimerState.Awaiting ? 0xB97867u : timer.Kind == TimerKind.Pomodoro ? 0xB78D9Cu : 0x8A9D91u);
            d.DrawRoundedRectangle(ColorBrush(0xFFFCF8, 245), new Pen(accent, .7), new Rect(42, 237, 180, 28), 13, 13);
            Text(d, timer.Symbol + "  " + DeskTimer.TimeText(timer.Seconds(now)), 132, 242, 14, accent, "Consolas");
            d.DrawRoundedRectangle(accent, null, new Rect(57, 261, 150 * timer.Progress(now), 2), 1, 1);
        }
        if (!ReminderVisible && now < Model.SpeechUntil && !Preview)
        {
            var text = new FormattedText(Model.Speech, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, new Typeface("Microsoft YaHei UI"), 12, Ink, VisualTreeHelper.GetDpi(this).PixelsPerDip) { MaxTextWidth = 226, TextAlignment = TextAlignment.Center };
            double h = Math.Max(27, text.Height + 12);
            d.DrawRoundedRectangle(ColorBrush(0xFFFAEF, 248), new Pen(ColorBrush(0xD7BFAE), 1), new Rect(13, 5, 238, h), 12, 12);
            d.DrawText(text, new Point(19, 11));
        }
    }
    internal static void Text(DrawingContext d, string value, double cx, double y, double size, Brush brush, string font = "Microsoft YaHei UI")
    {
        var t = new FormattedText(value, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, new Typeface(font), size, brush, 1);
        d.DrawText(t, new Point(cx - t.Width / 2, y));
    }
    public void Export(string path)
    {
        Height = LogicalHeight; Measure(new Size(264, LogicalHeight)); Arrange(new Rect(0, 0, 264, LogicalHeight)); InvalidateVisual(); UpdateLayout();
        var b = new RenderTargetBitmap(528, (int)(LogicalHeight * 2), 192, 192, PixelFormats.Pbgra32); b.Render(this);
        var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(b)); using var stream = File.Create(path); png.Save(stream);
    }
}
