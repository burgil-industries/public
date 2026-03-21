using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public class DarkProgressBar : Control {
    private int _val;
    public int Value {
        get { return _val; }
        set { _val = Math.Max(Minimum, Math.Min(Maximum, value)); Invalidate(); }
    }
    public int   Minimum  { get; set; }
    public int   Maximum  { get; set; }
    public Color BarStart { get; set; }
    public Color BarEnd   { get; set; }

    public DarkProgressBar() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer, true);
        SetStyle(ControlStyles.SupportsTransparentBackColor, true);
        BackColor = Color.Transparent;
        Minimum  = 0; Maximum = 100;
        BarStart = Color.FromArgb(31, 111, 235);
        BarEnd   = Color.FromArgb(88, 166, 255);
    }

    protected override void OnPaintBackground(PaintEventArgs e) {
        Color bg = Parent != null ? Parent.BackColor : BackColor;
        using (var b = new SolidBrush(bg)) e.Graphics.FillRectangle(b, ClientRectangle);
    }

    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        int r = Height / 2;
        var trackRect = new Rectangle(0, 0, Width - 1, Height - 1);
        using (var trackPath = Round(trackRect, r)) {
            using (var b = new SolidBrush(Color.FromArgb(33, 38, 45))) g.FillPath(b, trackPath);
            if (_val > Minimum && Maximum > Minimum) {
                float pct = (float)(_val - Minimum) / (Maximum - Minimum);
                int fw = (int)Math.Round(pct * (Width - 2));
                if (fw > 0) {
                    g.SetClip(trackPath);
                    var fill = new Rectangle(1, 1, Math.Min(fw, Width - 2), Height - 2);
                    using (var b = new LinearGradientBrush(fill, BarStart, BarEnd, LinearGradientMode.Horizontal))
                        g.FillRectangle(b, fill);
                    g.ResetClip();
                }
            }
            using (var p = new Pen(Color.FromArgb(48, 54, 61), 1f)) g.DrawPath(p, trackPath);
        }
    }

    static GraphicsPath Round(Rectangle rect, int rad) {
        int d = rad * 2; var p = new GraphicsPath();
        if (rad <= 0) { p.AddRectangle(rect); return p; }
        p.AddArc(rect.Left,          rect.Top,          d, d, 180, 90);
        p.AddArc(rect.Right - d,     rect.Top,          d, d, 270, 90);
        p.AddArc(rect.Right - d,     rect.Bottom - d,   d, d,   0, 90);
        p.AddArc(rect.Left,          rect.Bottom - d,   d, d,  90, 90);
        p.CloseFigure(); return p;
    }
}