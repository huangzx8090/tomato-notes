using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace TomatoNotes.Windows.Controls;

/// 便签编辑器：在纸色背景上按行绘制横线，对应 macOS 的 LinedTextView。
/// 线距取当前字体的一行高度，滚动时线一起移动，保持纸面行线与文字对齐。
public sealed class LinedTextBox : TextBox
{
    private ScrollViewer? host;

    public override void OnApplyTemplate()
    {
        if (host is not null) host.ScrollChanged -= ScrollChanged;
        base.OnApplyTemplate();
        host = GetTemplateChild("PART_ContentHost") as ScrollViewer;
        if (host is not null) host.ScrollChanged += ScrollChanged;
    }

    private void ScrollChanged(object sender, ScrollChangedEventArgs e) => InvalidateVisual();

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        if (ActualWidth <= 0 || ActualHeight <= 0) return;
        if (TryFindResource("NoteRule") is not Brush rule) return;

        var typeface = new Typeface(FontFamily, FontStyle, FontWeight, FontStretch);
        var pixelsPerDip = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var sample = new FormattedText("Ag", CultureInfo.CurrentCulture, System.Windows.FlowDirection.LeftToRight,
            typeface, FontSize, Brushes.Black, pixelsPerDip);
        var pitch = Math.Max(6, sample.Height);
        var offset = host?.VerticalOffset ?? 0;
        var left = Padding.Left;
        var right = Math.Max(left, ActualWidth - Padding.Right);
        var pen = new Pen(rule, 0.5);
        pen.Freeze();

        // 从当前滚动偏移取模，滚动时线随内容上移，不会固定在视口。
        var y = Padding.Top + pitch - 0.5 - offset % pitch;
        for (; y <= ActualHeight; y += pitch)
            drawingContext.DrawLine(pen, new Point(left, y), new Point(right, y));
    }
}
