using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Media.Animation;

namespace TomatoNotes.Windows.Controls;

/// macOS PanelNavigation 的 WPF 版：胶囊轨道 + 会滑动的选中块 + 五个带图标的标签。
/// 标签用 RadioButton 承载，保留键盘方向键切换与 UIA 选中语义；
/// 选中块在移动途中轻微拉长、到位时收圆，复刻 Swift 版的 FlowingTabShape 手感。
public partial class SegmentedNav : UserControl
{
    private static readonly (string Label, Wpf.Ui.Controls.SymbolRegular Symbol)[] Items =
    [
        ("专注", Wpf.Ui.Controls.SymbolRegular.Timer24),
        ("待办", Wpf.Ui.Controls.SymbolRegular.TaskListSquareLtr24),
        ("今日", Wpf.Ui.Controls.SymbolRegular.WeatherSunny24),
        ("便签", Wpf.Ui.Controls.SymbolRegular.Notepad24),
        ("设置", Wpf.Ui.Controls.SymbolRegular.Settings24),
    ];

    private const double AnimationSeconds = 0.52;
    private readonly List<RadioButton> buttons = [];
    private int currentIndex;
    private bool suppressEvent;

    public static readonly DependencyProperty SelectedIndexProperty = DependencyProperty.Register(
        nameof(SelectedIndex), typeof(int), typeof(SegmentedNav),
        new FrameworkPropertyMetadata(0, FrameworkPropertyMetadataOptions.BindsTwoWayByDefault, OnSelectedIndexChanged));

    public int SelectedIndex { get => (int)GetValue(SelectedIndexProperty); set => SetCurrentValue(SelectedIndexProperty, value); }

    /// 用户点击或方向键切换后触发；外部绑定改动 SelectedIndex 不会触发。
    public event Action<int>? SelectionChanged;

    public SegmentedNav()
    {
        InitializeComponent();
        BuildTabs();
        // SizeChanged 只在构造函数里订阅一次：窗口隐藏 / 显示会让 Loaded 重复触发。
        Tabs.SizeChanged += OnTabsResized;
        Loaded += (_, _) => MoveIndicator(currentIndex, currentIndex, false);
    }

    private void BuildTabs()
    {
        for (var index = 0; index < Items.Length; index++)
        {
            var (label, symbol) = Items[index];
            var icon = new Wpf.Ui.Controls.SymbolIcon { Symbol = symbol, FontSize = 14, Margin = new Thickness(0, 1, 5, 0) };
            // IconElement.Foreground 未必继承父级，这里显式跟随标签前景，选中态才会变成强调色。
            icon.SetBinding(Wpf.Ui.Controls.IconElement.ForegroundProperty,
                new Binding("Foreground") { RelativeSource = new RelativeSource(RelativeSourceMode.FindAncestor, typeof(RadioButton), 1) });
            var button = new RadioButton
            {
                GroupName = "TomatoNotesNav",
                Style = (Style)FindResource("NavTab"),
                Tag = index,
                Content = new StackPanel
                {
                    Orientation = Orientation.Horizontal,
                    Children = { icon, new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center } },
                },
            };
            AutomationProperties.SetName(button, label);
            AutomationProperties.SetAutomationId(button, $"navigation.{label}");
            button.Checked += OnTabChecked;
            buttons.Add(button);
            Tabs.Children.Add(button);
        }
        if (buttons.Count > 0) buttons[0].IsChecked = true;
    }

    private void OnTabChecked(object sender, RoutedEventArgs e)
    {
        if (suppressEvent) return;
        var index = buttons.IndexOf((RadioButton)sender);
        if (index < 0 || index == currentIndex) return;
        var from = currentIndex;
        currentIndex = index;
        SetCurrentValue(SelectedIndexProperty, index);
        MoveIndicator(from, index, true);
        SelectionChanged?.Invoke(index);
    }

    private static void OnSelectedIndexChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var nav = (SegmentedNav)d;
        var index = Math.Clamp((int)e.NewValue, 0, Items.Length - 1);
        if (index == nav.currentIndex) return;
        var from = nav.currentIndex;
        nav.currentIndex = index;
        nav.suppressEvent = true;
        nav.buttons[index].IsChecked = true;
        nav.suppressEvent = false;
        nav.MoveIndicator(from, index, nav.IsLoaded);
    }

    private void OnTabsResized(object sender, SizeChangedEventArgs e) => MoveIndicator(currentIndex, currentIndex, false);

    private void MoveIndicator(int from, int to, bool animate)
    {
        var width = Tabs.ActualWidth;
        if (width <= 0 || Items.Length == 0) return;
        var slot = width / Items.Length;
        var target = to * slot;

        // 先落定最终值，动画用 FillBehavior.Stop，结束后自然回落到本地值，避免动画长期占住属性。
        Canvas.SetLeft(Indicator, target);
        Indicator.Width = slot;
        Indicator.Visibility = Visibility.Visible;
        if (!animate || from == to || !SystemParameters.ClientAreaAnimation) return;

        var origin = from * slot;
        var stretch = Math.Min(30, Math.Abs(to - from) * slot * 0.28);
        var midLeft = (origin + target) / 2 - stretch / 2;

        var left = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromSeconds(AnimationSeconds), FillBehavior = FillBehavior.Stop };
        left.KeyFrames.Add(new LinearDoubleKeyFrame(origin, KeyTime.FromPercent(0)));
        left.KeyFrames.Add(new EasingDoubleKeyFrame(midLeft, KeyTime.FromPercent(0.5), new CubicEase { EasingMode = EasingMode.EaseInOut }));
        left.KeyFrames.Add(new EasingDoubleKeyFrame(target, KeyTime.FromPercent(1), new CubicEase { EasingMode = EasingMode.EaseOut }));

        var size = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromSeconds(AnimationSeconds), FillBehavior = FillBehavior.Stop };
        size.KeyFrames.Add(new LinearDoubleKeyFrame(slot, KeyTime.FromPercent(0)));
        size.KeyFrames.Add(new EasingDoubleKeyFrame(slot + stretch, KeyTime.FromPercent(0.5), new CubicEase { EasingMode = EasingMode.EaseInOut }));
        size.KeyFrames.Add(new EasingDoubleKeyFrame(slot, KeyTime.FromPercent(1), new CubicEase { EasingMode = EasingMode.EaseOut }));

        Indicator.BeginAnimation(Canvas.LeftProperty, left);
        Indicator.BeginAnimation(WidthProperty, size);
    }
}
