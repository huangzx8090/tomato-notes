using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
using System.Windows.Input;
using System.Windows.Media;

namespace TomatoNotes.Windows.Controls;

/// macOS RotaryDial 的 WPF 实现：表盘刻度、渐变边框与指针、拖动 / 方向键调节，
/// 以及下方 − 范围 ＋ 微调行，全部在一个自绘元素里完成，几何与交互与 Swift 版一致。
public sealed class RotaryDial : FrameworkElement
{
    private const double Spacing = 10;
    private const double ButtonSize = 23;
    private const double Diameter = 124;

    private int dragStartValue;
    private double previousAngle;
    private double accumulatedAngle;
    private bool dragging;
    private bool verticalMode;
    private bool subscribed;
    private Point dragStartPoint;
    private Rect dialRect;
    private Rect minusRect;
    private Rect plusRect;

    public static readonly DependencyProperty TitleProperty = DependencyProperty.Register(
        nameof(Title), typeof(string), typeof(RotaryDial), new FrameworkPropertyMetadata("", FrameworkPropertyMetadataOptions.AffectsRender));
    public static readonly DependencyProperty UnitProperty = DependencyProperty.Register(
        nameof(Unit), typeof(string), typeof(RotaryDial), new FrameworkPropertyMetadata("", FrameworkPropertyMetadataOptions.AffectsRender));
    public static readonly DependencyProperty TintProperty = DependencyProperty.Register(
        nameof(Tint), typeof(Brush), typeof(RotaryDial), new FrameworkPropertyMetadata(Brushes.Firebrick, FrameworkPropertyMetadataOptions.AffectsRender));
    public static readonly DependencyProperty MinimumProperty = DependencyProperty.Register(
        nameof(Minimum), typeof(int), typeof(RotaryDial), new FrameworkPropertyMetadata(1, FrameworkPropertyMetadataOptions.AffectsRender, OnBoundsChanged));
    public static readonly DependencyProperty MaximumProperty = DependencyProperty.Register(
        nameof(Maximum), typeof(int), typeof(RotaryDial), new FrameworkPropertyMetadata(60, FrameworkPropertyMetadataOptions.AffectsRender, OnBoundsChanged));
    public static readonly DependencyProperty SmallChangeProperty = DependencyProperty.Register(
        nameof(SmallChange), typeof(int), typeof(RotaryDial), new FrameworkPropertyMetadata(1));
    public static readonly DependencyProperty ValueProperty = DependencyProperty.Register(
        nameof(Value), typeof(int), typeof(RotaryDial),
        new FrameworkPropertyMetadata(25, FrameworkPropertyMetadataOptions.AffectsRender | FrameworkPropertyMetadataOptions.BindsTwoWayByDefault, OnValueChanged));

    public string Title { get => (string)GetValue(TitleProperty); set => SetValue(TitleProperty, value); }
    public string Unit { get => (string)GetValue(UnitProperty); set => SetValue(UnitProperty, value); }
    public Brush Tint { get => (Brush)GetValue(TintProperty); set => SetValue(TintProperty, value); }
    public int Minimum { get => (int)GetValue(MinimumProperty); set => SetValue(MinimumProperty, value); }
    public int Maximum { get => (int)GetValue(MaximumProperty); set => SetValue(MaximumProperty, value); }
    public int SmallChange { get => (int)GetValue(SmallChangeProperty); set => SetValue(SmallChangeProperty, value); }
    public int Value { get => (int)GetValue(ValueProperty); set => SetCurrentValue(ValueProperty, value); }

    public RotaryDial()
    {
        Focusable = true;
        SnapsToDevicePixels = true;
        Loaded += (_, _) => SubscribeTheme();
        Unloaded += (_, _) => UnsubscribeTheme();
    }

    private void SubscribeTheme()
    {
        if (subscribed) return;
        subscribed = true;
        ThemeService.Changed += OnThemeChanged;
    }

    private void UnsubscribeTheme()
    {
        if (!subscribed) return;
        subscribed = false;
        ThemeService.Changed -= OnThemeChanged;
    }

    private void OnThemeChanged() => Dispatcher.BeginInvoke(new Action(InvalidateVisual));

    private static void OnBoundsChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var dial = (RotaryDial)d;
        dial.SetCurrentValue(ValueProperty, dial.Clamp(dial.Value));
    }

    private static void OnValueChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var dial = (RotaryDial)d;
        var next = dial.Clamp((int)e.NewValue);
        // 用 SetCurrentValue 夹取，避免把双向绑定改成本地值。
        if (next != (int)e.NewValue) dial.SetCurrentValue(ValueProperty, next);
        if (UIElementAutomationPeer.FromElement(dial) is { } peer)
            peer.RaiseAutomationEvent(AutomationEvents.PropertyChanged);
    }

    private int Clamp(int value) => Math.Clamp(value, Math.Min(Minimum, Maximum), Math.Max(Minimum, Maximum));

    /// 供 − / ＋ 按钮和键盘调用；符号决定方向，步长取 SmallChange。
    public void Step(int delta)
    {
        if (delta == 0) return;
        var step = Math.Max(1, Math.Abs(SmallChange)) * Math.Sign(delta);
        SetCurrentValue(ValueProperty, Clamp(Value + step));
    }

    private double Progress => Maximum == Minimum ? 0 : (double)(Value - Minimum) / (Maximum - Minimum);

    protected override Size MeasureOverride(Size availableSize)
    {
        var title = FormatText(Title, 12, FontWeights.Medium, Token("Secondary"));
        var range = FormatText(RangeLabel, 9, FontWeights.Regular, Token("Secondary"), monospaced: true);
        var width = Math.Max(Diameter, Math.Max(title.Width, range.Width + ButtonSize * 2 + 22));
        var height = TotalHeight(title.Height);
        return new Size(double.IsInfinity(availableSize.Width) ? width : Math.Min(width, availableSize.Width), height);
    }

    private string RangeLabel => $"{Minimum}–{Maximum}";

    private static double TotalHeight(double titleHeight) => titleHeight + Spacing + Diameter + Spacing + ButtonSize;

    protected override void OnRender(DrawingContext dc)
    {
        var width = Math.Max(ActualWidth, Diameter);
        var title = FormatText(Title, 12, FontWeights.Medium, Token("Secondary"));
        dc.DrawText(title, new Point((width - title.Width) / 2, 0));

        dialRect = new Rect((width - Diameter) / 2, title.Height + Spacing, Diameter, Diameter);
        DrawDial(dc, dialRect);
        DrawAdjustRow(dc, dialRect.Bottom + Spacing, width);
    }

    private void DrawDial(DrawingContext dc, Rect rect)
    {
        var size = rect.Width;
        var center = new Point(rect.X + size / 2, rect.Y + size / 2);
        var progress = Progress;

        if (dragging) dc.PushTransform(new ScaleTransform(0.985, 0.985, center.X, center.Y));

        // macOS 用真实投影；WPF 自绘里用径向渐变近似同一种柔和落影。
        var shadow = TokenColor("DialShadow");
        var shadowBrush = new RadialGradientBrush
        {
            Center = new Point(0.5, 0.5),
            GradientOrigin = new Point(0.5, 0.5),
            RadiusX = 0.5,
            RadiusY = 0.5,
        };
        shadowBrush.GradientStops.Add(new GradientStop(Color.FromArgb((byte)(255 * (dragging ? 0.26 : 0.36)), shadow.R, shadow.G, shadow.B), 0.72));
        shadowBrush.GradientStops.Add(new GradientStop(Color.FromArgb(0, shadow.R, shadow.G, shadow.B), 1));
        shadowBrush.Freeze();
        var rimRadius = (size - 32) / 2;
        dc.DrawEllipse(shadowBrush, null, new Point(center.X, center.Y + (dragging ? 2 : 5)), rimRadius + 7, rimRadius + 7);

        var borderPen = new Pen(FrozenBrush(TokenColor("Border"), 0.45), 1);
        borderPen.Freeze();
        dc.DrawEllipse(null, borderPen, center, (size - 6) / 2, (size - 6) / 2);

        // 37 根进度刻度，扫过 270°
        var tint = (Tint as SolidColorBrush)?.Color ?? Colors.Firebrick;
        var tickFilled = FrozenBrush(Color.FromArgb(191, tint.R, tint.G, tint.B), 1);
        var tickIdle = FrozenBrush(TokenColor("Border"), 1);
        for (var index = 0; index < 37; index++)
        {
            var major = index % 3 == 0;
            DrawTick(dc, center, size / 2 - 8, -135 + index * 7.5,
                major ? 2 : 1, major ? 7 : 4, index / 36.0 <= progress ? tickFilled : tickIdle);
        }

        dc.DrawEllipse(DiagonalGradient(TokenColor("DialRimLight"), TokenColor("DialRimShadow"), TokenColor("DialRimEnd")),
            null, center, rimRadius, rimRadius);

        // 60 根滚花细纹
        var knurlEven = FrozenBrush(Color.FromArgb(71, 0xAF, 0xA6, 0x9A), 1);
        var knurlOdd = FrozenBrush(Color.FromArgb(33, 0xAF, 0xA6, 0x9A), 1);
        for (var index = 0; index < 60; index++)
            DrawTick(dc, center, size / 2 - 19, index * 6, 1, 3, index % 2 == 0 ? knurlEven : knurlOdd);

        var faceRadius = (size - 46) / 2;
        dc.DrawEllipse(DiagonalGradient(TokenColor("DialFaceLight"), TokenColor("DialFaceShadow"), null), null, center, faceRadius, faceRadius);
        var highlightPen = new Pen(FrozenBrush(TokenColor("DialHighlight"), 0.95), 1);
        highlightPen.Freeze();
        dc.DrawEllipse(null, highlightPen, center, faceRadius, faceRadius);

        DrawTick(dc, center, size / 2 - 28, -135 + progress * 270, 3, 10, FrozenBrush(tint, 1));

        var value = FormatText(Value.ToString(CultureInfo.InvariantCulture), 23, FontWeights.Medium, Token("Ink"), monospaced: true);
        var unit = FormatText(Unit, 9, FontWeights.Medium, Token("Secondary"));
        var top = center.Y - (value.Height + 1 + unit.Height) / 2 + 3;
        dc.DrawText(value, new Point(center.X - value.Width / 2, top));
        dc.DrawText(unit, new Point(center.X - unit.Width / 2, top + value.Height + 1));

        if (dragging) dc.Pop();
    }

    private static void DrawTick(DrawingContext dc, Point center, double radius, double angleDegrees, double width, double height, Brush brush)
    {
        dc.PushTransform(new RotateTransform(angleDegrees, center.X, center.Y));
        var corner = Math.Min(width, height) / 2;
        dc.DrawRoundedRectangle(brush, null,
            new Rect(center.X - width / 2, center.Y - radius - height / 2, width, height), corner, corner);
        dc.Pop();
    }

    private static Brush DiagonalGradient(Color start, Color middle, Color? end)
    {
        var brush = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(1, 1) };
        brush.GradientStops.Add(new GradientStop(start, 0));
        brush.GradientStops.Add(new GradientStop(middle, end is null ? 1 : 0.55));
        if (end is Color last) brush.GradientStops.Add(new GradientStop(last, 1));
        brush.Freeze();
        return brush;
    }

    private void DrawAdjustRow(DrawingContext dc, double top, double width)
    {
        var range = FormatText(RangeLabel, 9, FontWeights.Regular, Token("Secondary"), monospaced: true);
        const double gap = 11;
        var rowWidth = ButtonSize + gap + range.Width + gap + ButtonSize;
        var left = (width - rowWidth) / 2;
        minusRect = new Rect(left, top, ButtonSize, ButtonSize);
        plusRect = new Rect(left + rowWidth - ButtonSize, top, ButtonSize, ButtonSize);

        DrawRoundButton(dc, minusRect, Value <= Minimum, plus: false);
        dc.DrawText(range, new Point(minusRect.Right + gap, top + (ButtonSize - range.Height) / 2));
        DrawRoundButton(dc, plusRect, Value >= Maximum, plus: true);
    }

    private void DrawRoundButton(DrawingContext dc, Rect rect, bool disabled, bool plus)
    {
        var pen = new Pen(FrozenBrush(TokenColor("Border"), 0.8), 0.6);
        pen.Freeze();
        var center = new Point(rect.X + rect.Width / 2, rect.Y + rect.Height / 2);
        dc.DrawEllipse(Token("Background"), pen, center, rect.Width / 2, rect.Height / 2);

        var ink = FrozenBrush(TokenColor("Secondary"), disabled ? 0.4 : 1);
        var glyph = new Pen(ink, 1.4) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        glyph.Freeze();
        // 用矢量线段画 − / ＋，避免依赖字体里是否存在 U+2212、U+FF0B。
        dc.DrawLine(glyph, new Point(center.X - 4, center.Y), new Point(center.X + 4, center.Y));
        if (plus) dc.DrawLine(glyph, new Point(center.X, center.Y - 4), new Point(center.X, center.Y + 4));
    }

    private static Brush FrozenBrush(Color color, double opacity)
    {
        var brush = new SolidColorBrush(color) { Opacity = opacity };
        brush.Freeze();
        return brush;
    }

    private static Color TokenColor(string key) => (Token(key) as SolidColorBrush)?.Color ?? Colors.Transparent;

    private static Brush Token(string key) => ThemeService.Token(key);

    private FormattedText FormatText(string text, double size, FontWeight weight, Brush brush, bool monospaced = false)
    {
        var family = monospaced
            ? new FontFamily("Consolas, Microsoft YaHei UI, Segoe UI")
            : Application.Current?.TryFindResource("UIFont") as FontFamily ?? new FontFamily("Microsoft YaHei UI, Segoe UI");
        return new FormattedText(text, CultureInfo.CurrentUICulture, System.Windows.FlowDirection.LeftToRight,
            new Typeface(family, FontStyles.Normal, weight, FontStretches.Normal), size, brush,
            VisualTreeHelper.GetDpi(this).PixelsPerDip);
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        var point = e.GetPosition(this);
        if (minusRect.Contains(point)) { Step(-1); e.Handled = true; return; }
        if (plusRect.Contains(point)) { Step(1); e.Handled = true; return; }
        if (!dialRect.Contains(point)) return;
        Focus();
        dragStartValue = Value;
        dragStartPoint = point;
        accumulatedAngle = 0;
        var relative = ToDialSpace(point);
        verticalMode = Math.Sqrt(relative.X * relative.X + relative.Y * relative.Y) < 22;
        previousAngle = AngleOf(relative);
        dragging = true;
        CaptureMouse();
        InvalidateVisual();
        e.Handled = true;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (!dragging || e.LeftButton != MouseButtonState.Pressed) return;
        var point = e.GetPosition(this);
        if (verticalMode)
        {
            // 表盘中心难以确定旋转角度，改用上下拖动，避免数值跳变。
            SetCurrentValue(ValueProperty, Clamp(dragStartValue + (int)Math.Round((dragStartPoint.Y - point.Y) / 3)));
            return;
        }
        var current = AngleOf(ToDialSpace(point));
        var delta = current - previousAngle;
        if (delta > 180) delta -= 360;
        if (delta < -180) delta += 360;
        accumulatedAngle += delta;
        previousAngle = current;
        SetCurrentValue(ValueProperty, Clamp(dragStartValue + (int)Math.Round(accumulatedAngle / 270 * (Maximum - Minimum))));
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        if (!dragging) return;
        dragging = false;
        ReleaseMouseCapture();
        InvalidateVisual();
    }

    private Point ToDialSpace(Point point)
    {
        var center = new Point(dialRect.X + dialRect.Width / 2, dialRect.Y + dialRect.Height / 2);
        return new Point(point.X - center.X, center.Y - point.Y);
    }

    /// 与 Swift 版相同：atan2(x, y) 得到「自正上方顺时针」的角度。
    private static double AngleOf(Point relative) => Math.Atan2(relative.X, relative.Y) * 180 / Math.PI;

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        switch (e.Key)
        {
            case Key.Up:
            case Key.Right: Step(1); break;
            case Key.Down:
            case Key.Left: Step(-1); break;
            case Key.PageUp: Step(5); break;
            case Key.PageDown: Step(-5); break;
            case Key.Home: SetCurrentValue(ValueProperty, Minimum); break;
            case Key.End: SetCurrentValue(ValueProperty, Maximum); break;
            default: return;
        }
        e.Handled = true;
    }

    protected override void OnMouseEnter(MouseEventArgs e)
    {
        base.OnMouseEnter(e);
        Cursor = Cursors.Hand;
    }

    protected override void OnMouseLeave(MouseEventArgs e)
    {
        base.OnMouseLeave(e);
        Cursor = null;
    }

    protected override AutomationPeer OnCreateAutomationPeer() => new RotaryDialAutomationPeer(this);

    private sealed class RotaryDialAutomationPeer(RotaryDial owner) : FrameworkElementAutomationPeer(owner), IRangeValueProvider
    {
        public bool IsReadOnly => false;
        public double LargeChange => Math.Max(1, owner.SmallChange) * 5;
        public double Maximum => owner.Maximum;
        public double Minimum => owner.Minimum;
        public double SmallChange => Math.Max(1, owner.SmallChange);
        public double Value => owner.Value;
        public void SetValue(double value) => owner.SetCurrentValue(ValueProperty, (int)Math.Round(value));
        protected override string GetClassNameCore() => nameof(RotaryDial);
        protected override string GetNameCore() => string.IsNullOrEmpty(owner.Title) ? base.GetNameCore() : owner.Title;
        protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.Custom;
        public override object? GetPattern(PatternInterface patternInterface)
            => patternInterface == PatternInterface.RangeValue ? this : base.GetPattern(patternInterface);
    }
}
