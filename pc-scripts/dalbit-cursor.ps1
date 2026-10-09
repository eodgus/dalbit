# Keeps the PC's mouse cursor where the mouse left it when the tablet is touched.
# Windows moves the cursor to every touch, so touching the tablet's extended screen pulled the cursor off the
# main monitor. The touch still lands where it should; the next time the real mouse moves, the cursor carries on
# from where the mouse last had it instead of from the touch point.
# Touch input never reaches a low-level mouse hook, and the cursor position read while handling a mouse event can
# lag behind or run ahead of it, so a touch is recognized from the mouse events alone: the next one starts far from
# where the last one ended, in a way Windows' easing of the cursor across monitor borders does not explain. This
# runs only while the extended screen is in use, since a program moving the cursor far would be undone as well.
# Started by dalbit-on.cmd and stopped by dalbit-off.cmd, or by the Sunshine app's prep commands; only one copy
# runs at a time. -Stop ends a running copy. -Log writes a line to %TEMP%\dalbit-cursor.log each time the cursor is
# put back.
param([switch]$Log, [switch]$Stop)
if ($Stop) {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*dalbit-cursor.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId }
    exit
}
$created = $false
$mutex = New-Object Threading.Mutex($true, 'Local\DalbitCursorKeeper', [ref]$created)
if (-not $created) { exit }

Add-Type -ReferencedAssemblies System.Windows.Forms @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class DalbitCursorKeeper {
    delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct MSLLHOOKSTRUCT { public POINT pt; public uint mouseData, flags, time; public IntPtr extraInfo; }
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct MONITORINFO { public int cbSize; public RECT rcMonitor, rcWork; public int dwFlags; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr extraInfo; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public MOUSEINPUT mi; }


    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int idHook, HookProc fn, IntPtr hMod, uint threadId);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hhk, int code, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT pt);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("user32.dll")] static extern bool GetClipCursor(out RECT r);
    [DllImport("user32.dll")] static extern bool ClipCursor(ref RECT r);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);

    [DllImport("user32.dll")] static extern IntPtr MonitorFromPoint(POINT pt, int flags);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO mi);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string name);

    const int WH_MOUSE_LL = 14, WM_MOUSEMOVE = 0x200;
    const uint LLMHF_INJECTED = 1, LLMHF_LOWER_IL_INJECTED = 2;
    // A real mouse moves the cursor far less than this between two events
    const int TOUCH_JUMP = 150;
    // How close to a monitor border a mouse move that Windows eased across it ends up
    const int BORDER = 30;
    // Windows keeps pulling the cursor toward a touch while the finger is down; after this long, let it
    const int HELD_MS = 150;

    static readonly HookProc proc = Hook;  // kept referenced so it is not collected
    static POINT mouse;                     // where the real mouse last put the cursor
    static int putBackSince;                // when the current run of put-backs started (ms tick)
    static int putBackLast;                 // when its last event came
    static string logPath;

    public static void Run(string log) {
        logPath = String.IsNullOrEmpty(log) ? null : log;  // PowerShell passes $null as ""
        // The hook reports physical pixels; SetCursorPos and MonitorFromPoint have to use the same
        SetProcessDpiAwarenessContext((IntPtr)(-4));  // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
        GetCursorPos(out mouse);
        SetWindowsHookEx(WH_MOUSE_LL, proc, GetModuleHandle(null), 0);
        Application.Run();
    }

    static IntPtr Hook(int code, IntPtr wParam, IntPtr lParam) {
        // An exception escaping a hook callback ends the process, so a failure just passes the event on
        try {
            if (code >= 0 && Handle((int)wParam, (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT)))) {
                return (IntPtr)1;
            }
        } catch (Exception) {
        }
        return CallNextHookEx(IntPtr.Zero, code, wParam, lParam);
    }

    // Returns true to drop the event
    static bool Handle(int msg, MSLLHOOKSTRUCT m) {
        // Injected input (remote tools, Sunshine's own mouse) is not the mouse on the desk
        if ((m.flags & (LLMHF_INJECTED | LLMHF_LOWER_IL_INJECTED)) != 0) {
            return false;
        }
        if (TouchMovedIt(m.pt)) {
            // Windows keeps pulling the cursor toward a touch while the finger is down; after a moment, let it.
            // Only events right after one another are the same pull; a later touch starts over.
            int now = Environment.TickCount;
            if (now - putBackLast > 50) {
                putBackSince = now;
            }
            putBackLast = now;
            if (now - putBackSince <= HELD_MS) {
                Log(String.Format("msg=0x{0:X} at {1},{2} back to {3},{4}", msg, m.pt.X, m.pt.Y, mouse.X, mouse.Y));
                PutBack();
                if (msg != WM_MOUSEMOVE) {
                    // Windows would still deliver the button where the touch left the cursor. Send it again from
                    // the mouse's position, after a one-pixel move there and back: without a move first, Windows
                    // did not take it as a click while the cursor was still hidden from the touch.
                    Send(Input(1, 0, 0x0001, 0), Input(-1, 0, 0x0001, 0),
                         Input(0, 0, ButtonFlags(msg), (uint)(short)(m.mouseData >> 16)));  // wheel delta is signed
                }
                // A move is dropped too, losing only its few pixels
                return true;
            }
            Log(String.Format("at {0},{1} still held, letting it be", m.pt.X, m.pt.Y));
        }
        if (msg == WM_MOUSEMOVE) {
            // The hook reports points past a monitor's edge when the mouse pushes against it; Windows keeps the
            // cursor on the nearest monitor's edge instead
            RECT r = MonitorRect(m.pt);
            mouse.X = Math.Max(r.Left, Math.Min(m.pt.X, r.Right - 1));
            mouse.Y = Math.Max(r.Top, Math.Min(m.pt.Y, r.Bottom - 1));
        }
        return false;
    }

    // Tools like LittleBigMouse keep the cursor clipped to the monitor it is on and move it across themselves, so
    // SetCursorPos alone stops at that monitor's edge. Clip to the mouse's monitor first, but only if something
    // clips the cursor at all.
    static void PutBack() {
        RECT clip;
        GetClipCursor(out clip);
        bool clipped = clip.Left != GetSystemMetrics(76) || clip.Top != GetSystemMetrics(77) ||  // SM_X/YVIRTUALSCREEN
                clip.Right - clip.Left != GetSystemMetrics(78) || clip.Bottom - clip.Top != GetSystemMetrics(79);
        if (clipped) {
            RECT r = MonitorRect(mouse);
            ClipCursor(ref r);
        }
        SetCursorPos(mouse.X, mouse.Y);
    }

    static INPUT Input(int dx, int dy, uint flags, uint data) {
        var input = new INPUT();
        input.mi.dx = dx;
        input.mi.dy = dy;
        input.mi.dwFlags = flags;
        input.mi.mouseData = data;
        return input;
    }

    static void Send(params INPUT[] inputs) {
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
    }

    static uint ButtonFlags(int msg) {
        switch (msg) {
            case 0x201: return 0x0002;  // left down
            case 0x202: return 0x0004;  // left up
            case 0x204: return 0x0008;  // right down
            case 0x205: return 0x0010;  // right up
            case 0x207: return 0x0020;  // middle down
            case 0x208: return 0x0040;  // middle up
            case 0x20B: return 0x0080;  // X button down
            case 0x20C: return 0x0100;  // X button up
            case 0x20A: return 0x0800;  // wheel
            case 0x20E: return 0x1000;  // horizontal wheel
            default: return 0;
        }
    }

    // Whether this event starts from somewhere a touch put the cursor rather than from where the mouse left it
    static bool TouchMovedIt(POINT pt) {
        if (Distance(pt, mouse) <= TOUCH_JUMP) {
            return false;
        }
        // When the mouse crosses between monitors of different sizes, Windows or a tool like LittleBigMouse moves the
        // cursor along the border: the coordinate across the border stays, the one along it is scaled, and the hook
        // only reported the point before that. So the next event jumps along a border it is right next to. A touch
        // puts the cursor anywhere, and when the cursor is clipped to a monitor, lifting the finger moves it toward
        // the touch point until that monitor's edge stops it, far along both axes.
        RECT r = MonitorRect(pt);
        bool besideSideBorder = pt.X - r.Left <= BORDER || r.Right - 1 - pt.X <= BORDER;
        bool besideTopOrBottom = pt.Y - r.Top <= BORDER || r.Bottom - 1 - pt.Y <= BORDER;
        bool eased = (besideSideBorder && Math.Abs(pt.X - mouse.X) <= BORDER) ||
                (besideTopOrBottom && Math.Abs(pt.Y - mouse.Y) <= BORDER);
        return !eased;
    }

    static int Distance(POINT a, POINT b) {
        return Math.Abs(a.X - b.X) + Math.Abs(a.Y - b.Y);
    }

    static RECT MonitorRect(POINT pt) {
        var mi = new MONITORINFO();
        mi.cbSize = Marshal.SizeOf(mi);
        GetMonitorInfo(MonitorFromPoint(pt, 2), ref mi);  // MONITOR_DEFAULTTONEAREST
        return mi.rcMonitor;
    }

    static void Log(string line) {
        if (logPath != null) {
            System.IO.File.AppendAllText(logPath, DateTime.Now.ToString("HH:mm:ss.fff ") + line + "\r\n");
        }
    }}
'@
[DalbitCursorKeeper]::Run($(if ($Log) { "$env:TEMP\dalbit-cursor.log" } else { $null }))
