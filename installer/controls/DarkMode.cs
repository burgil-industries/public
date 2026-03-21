using System;
using System.Runtime.InteropServices;

// Dark title bar via DWM - makes Windows render the chrome in dark mode
public static class DarkMode {
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
    public static void Enable(IntPtr hwnd) {
        int v = 1;
        DwmSetWindowAttribute(hwnd, 20, ref v, 4);  // DWMWA_USE_IMMERSIVE_DARK_MODE (Win10 20H1+)
        DwmSetWindowAttribute(hwnd, 19, ref v, 4);  // older Win10 fallback
        int noColor = unchecked((int)0xFFFFFFFE);   // DWMWA_COLOR_NONE
        DwmSetWindowAttribute(hwnd, 34, ref noColor, 4);  // DWMWA_BORDER_COLOR - remove blue accent border
    }
}