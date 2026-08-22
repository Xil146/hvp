using System.Runtime.InteropServices;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;

namespace Hvp.Platform.Windows;

/// <summary>Owns the child HWND used by libmpv's <c>wid</c> option.</summary>
public sealed class VideoHost : HwndHost
{
    private const int WsChild = unchecked((int)0x40000000);
    private const int WsVisible = 0x10000000;
    private const int WhMouse = 7;
    private const uint WmLButtonUp = 0x0202;
    private const uint WmLButtonDblClk = 0x0203;
    private const uint WmRButtonUp = 0x0205;
    private readonly MouseHookProcedure mouseHookProcedure;
    private readonly DispatcherTimer singleClickTimer;
    private bool ignoreNextLeftButtonUp;
    private int pendingVideoClicks;
    private nint mouseHook;
    private nint videoHostHandle;

    public VideoHost()
    {
        mouseHookProcedure = MouseHookProc;
        singleClickTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(GetDoubleClickTime()) };
        singleClickTimer.Tick += SingleClickTimer_Tick;
    }

    public event EventHandler<nint>? HandleCreated;

    public event EventHandler<VideoHostKeyEventArgs>? KeyPressed;

    public event EventHandler? ContextMenuRequested;

    public event EventHandler? VideoClicked;

    public event EventHandler? VideoDoubleClicked;

    protected override HandleRef BuildWindowCore(HandleRef hwndParent)
    {
        nint handle = CreateWindowEx(
            0,
            "STATIC",
            string.Empty,
            WsChild | WsVisible,
            0,
            0,
            1,
            1,
            hwndParent.Handle,
            nint.Zero,
            nint.Zero,
            nint.Zero);

        if (handle == nint.Zero)
        {
            throw new InvalidOperationException($"Could not create the video host window (Win32 error {Marshal.GetLastWin32Error()}).");
        }

        try
        {
            videoHostHandle = handle;
            InstallMouseHook(handle);
            HandleCreated?.Invoke(this, handle);
            return new HandleRef(this, handle);
        }
        catch
        {
            RemoveMouseHook();
            videoHostHandle = nint.Zero;
            _ = DestroyWindow(handle);
            throw;
        }
    }

    protected override void DestroyWindowCore(HandleRef hwnd)
    {
        singleClickTimer.Stop();
        pendingVideoClicks = 0;
        RemoveMouseHook();
        videoHostHandle = nint.Zero;
        if (hwnd.Handle != nint.Zero && !DestroyWindow(hwnd.Handle))
        {
            throw new InvalidOperationException($"Could not destroy the video host window (Win32 error {Marshal.GetLastWin32Error()}).");
        }
    }

    protected override bool TranslateAcceleratorCore(ref MSG msg, ModifierKeys modifiers)
    {
        if (msg.message is 0x0100 or 0x0104)
        {
            VideoHostKeyEventArgs args = new(KeyInterop.KeyFromVirtualKey((int)msg.wParam), modifiers);
            KeyPressed?.Invoke(this, args);
            if (args.Handled)
            {
                return true;
            }
        }

        return base.TranslateAcceleratorCore(ref msg, modifiers);
    }

    private void InstallMouseHook(nint hwnd)
    {
        uint threadId = GetWindowThreadProcessId(hwnd, out _);
        mouseHook = SetWindowsHookEx(WhMouse, mouseHookProcedure, nint.Zero, threadId);
        if (mouseHook == nint.Zero)
        {
            throw new InvalidOperationException($"Could not install the video-host mouse handler (Win32 error {Marshal.GetLastWin32Error()}).");
        }
    }

    private void RemoveMouseHook()
    {
        if (mouseHook != nint.Zero)
        {
            _ = UnhookWindowsHookEx(mouseHook);
            mouseHook = nint.Zero;
        }
    }

    private nint MouseHookProc(int code, nint wParam, nint lParam)
    {
        try
        {
            if (code >= 0)
            {
                uint message = unchecked((uint)wParam.ToInt64());
                MouseHookStruct mouse = Marshal.PtrToStructure<MouseHookStruct>(lParam);
                if (!IsPointerOverVideoHost(mouse.X, mouse.Y))
                {
                    return CallNextHookEx(mouseHook, code, wParam, lParam);
                }

                switch (message)
                {
                    case WmRButtonUp:
                        _ = Dispatcher.BeginInvoke(() => ContextMenuRequested?.Invoke(this, EventArgs.Empty));
                        return new nint(1);
                    case WmLButtonUp when ignoreNextLeftButtonUp:
                        ignoreNextLeftButtonUp = false;
                        return new nint(1);
                    case WmLButtonUp:
                        _ = Dispatcher.BeginInvoke(ArmSingleClick);
                        return new nint(1);
                    case WmLButtonDblClk:
                        ignoreNextLeftButtonUp = true;
                        _ = Dispatcher.BeginInvoke(() =>
                        {
                            if (pendingVideoClicks > 0)
                            {
                                pendingVideoClicks--;
                            }

                            if (pendingVideoClicks == 0)
                            {
                                singleClickTimer.Stop();
                            }
                            VideoDoubleClicked?.Invoke(this, EventArgs.Empty);
                        });
                        return new nint(1);
                }
            }
        }
        catch
        {
            // Never allow managed exceptions to escape the native hook procedure.
        }

        return CallNextHookEx(mouseHook, code, wParam, lParam);
    }

    private void ArmSingleClick()
    {
        pendingVideoClicks++;
        singleClickTimer.Stop();
        singleClickTimer.Start();
    }

    private void SingleClickTimer_Tick(object? sender, EventArgs e)
    {
        singleClickTimer.Stop();
        int clickCount = pendingVideoClicks;
        pendingVideoClicks = 0;
        if ((clickCount & 1) == 1)
        {
            VideoClicked?.Invoke(this, EventArgs.Empty);
        }
    }

    private bool IsPointerOverVideoHost(int x, int y)
    {
        if (videoHostHandle == nint.Zero)
        {
            return false;
        }

        nint target = WindowFromPoint(new NativePoint(x, y));
        return target == videoHostHandle || (target != nint.Zero && IsChild(videoHostHandle, target));
    }

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern nint CreateWindowEx(
        int extendedStyle,
        string className,
        string windowName,
        int style,
        int x,
        int y,
        int width,
        int height,
        nint parent,
        nint menu,
        nint instance,
        nint parameter);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyWindow(nint hwnd);

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct MouseHookStruct
    {
        public readonly int X;
        public readonly int Y;
        public readonly nint Hwnd;
        public readonly nuint HitTestCode;
        public readonly nint ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct NativePoint(int x, int y)
    {
        public readonly int X = x;
        public readonly int Y = y;
    }

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate nint MouseHookProcedure(int code, nint wParam, nint lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint SetWindowsHookEx(int hookType, MouseHookProcedure procedure, nint module, uint threadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(nint hook);

    [DllImport("user32.dll")]
    private static extern nint CallNextHookEx(nint hook, int code, nint wParam, nint lParam);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint hwnd, out uint processId);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsChild(nint parent, nint child);

    [DllImport("user32.dll")]
    private static extern nint WindowFromPoint(NativePoint point);

    [DllImport("user32.dll")]
    private static extern uint GetDoubleClickTime();

}

public sealed class VideoHostKeyEventArgs(Key key, ModifierKeys modifiers) : EventArgs
{
    public Key Key { get; } = key;

    public ModifierKeys Modifiers { get; } = modifiers;

    public bool Handled { get; set; }
}
