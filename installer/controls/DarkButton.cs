using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class DarkButton : Control {
    private bool _hov, _dn;
    public Color NormalColor { get; set; }
    public Color HoverColor  { get; set; }
    public Color PressColor  { get; set; }
    public Color BorderColor { get; set; }
    public int   Corner      { get; set; }

    public DarkButton() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                 ControlStyles.UserMouse | ControlStyles.SupportsTransparentBackColor, true);
        SetStyle(ControlStyles.Selectable, false);
        BackColor = Color.Transparent;
        TabStop = false;
        Cursor      = Cursors.Hand;
        NormalColor = Color.FromArgb(33, 38, 45);
        HoverColor  = Color.FromArgb(48, 54, 61);
        PressColor  = Color.FromArgb(22, 27, 34);
        BorderColor = Color.FromArgb(48, 54, 61);
        Corner      = 0;
        ForeColor   = Color.FromArgb(240, 246, 252);
        Font        = new Font("Segoe UI", 9.5f);
    }

    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
    private static extern int SetWindowTheme(IntPtr hwnd, string app, string idList);

    protected override void OnHandleCreated(EventArgs e) {
        base.OnHandleCreated(e);
        SetWindowTheme(Handle, "", "");  // disable all uxtheme styling on this control
        UpdateRegion();
    }

    protected override void OnParentChanged(EventArgs e) {
        base.OnParentChanged(e);
        if (Parent != null) BackColor = Parent.BackColor;
        Invalidate();
    }

    protected override void OnSizeChanged(EventArgs e) {
        base.OnSizeChanged(e);
        UpdateRegion();
    }

    protected override bool ShowFocusCues    { get { return false; } }
    protected override bool ShowKeyboardCues { get { return false; } }
    protected override void OnPaintBackground(PaintEventArgs e) {
        Color bg = Parent != null ? Parent.BackColor : BackColor;
        using (var b = new SolidBrush(bg)) e.Graphics.FillRectangle(b, ClientRectangle);
    }

    protected override void OnMouseEnter(EventArgs e)      { _hov = true;  Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e)      { _hov = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e)  {
        if (e.Button == MouseButtons.Left) { _dn = true; Invalidate(); }
        base.OnMouseDown(e);
    }
    // Intercept WM_LBUTTONUP directly so click fires exactly once,
    // bypassing Control.WmMouseUp whose auto-fire behaviour varies by .NET version.
    protected override void WndProc(ref Message m) {
        const int WM_LBUTTONUP = 0x0202;
        if (m.Msg == WM_LBUTTONUP && Enabled && _dn) {
            int lp = m.LParam.ToInt32();
            int x  = (short)(lp & 0xFFFF);
            int y  = (short)(lp >> 16);
            _dn = false; Invalidate();
            this.Capture = false;  // release OS mouse capture (set by base.WndProc on MouseDown)
            var me = new MouseEventArgs(MouseButtons.Left, 1, x, y, 0);
            if (ClientRectangle.Contains(x, y)) {
                OnClick(EventArgs.Empty);  // may close/destroy the form+controls
            }
            // Guard: OnClick may have destroyed this handle (e.g. form was closed)
            if (IsHandleCreated) {
                OnMouseClick(me);
                OnMouseUp(me);
                DefWndProc(ref m);
            }
            return;
        }
        base.WndProc(ref m);
    }
    protected override void OnEnabledChanged(EventArgs e)  { Invalidate(); base.OnEnabledChanged(e); }

    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics;
        g.SmoothingMode     = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
        var rect = new Rectangle(0, 0, Width - 1, Height - 1);

        Color bg = !Enabled ? Color.FromArgb(22,27,34) : _dn ? PressColor : _hov ? HoverColor : NormalColor;
        using (var gp = Round(rect, Corner)) {
            using (var b = new SolidBrush(bg)) g.FillPath(b, gp);
            using (var p = new Pen(BorderColor, 1f)) g.DrawPath(p, gp);
        }

        Color fg = Enabled ? ForeColor : Color.FromArgb(80, ForeColor);
        using (var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
        using (var b  = new SolidBrush(fg))
            g.DrawString(Text, Font, b, new RectangleF(0, 0, Width, Height), sf);
    }

    void UpdateRegion() {
        if (Width <= 0 || Height <= 0) return;
        if (Corner <= 0) {
            Region = new Region(new Rectangle(0, 0, Width, Height));
            return;
        }
        using (var gp = Round(new Rectangle(0, 0, Width, Height), Corner)) {
            Region = new Region(gp);
        }
    }

    static GraphicsPath Round(Rectangle r, int rad) {
        int d = rad * 2; var p = new GraphicsPath();
        if (rad <= 0) { p.AddRectangle(r); return p; }
        p.AddArc(r.Left,      r.Top,       d, d, 180, 90);
        p.AddArc(r.Right - d, r.Top,       d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom- d, d, d,   0, 90);
        p.AddArc(r.Left,      r.Bottom- d, d, d,  90, 90);
        p.CloseFigure(); return p;
    }
}