using System.Runtime.InteropServices;
using System.Windows.Input;
using System.Windows.Interop;

namespace Hvp.Platform.Windows;

/// <summary>Owns the child HWND used by libmpv's <c>wid</c> option.</summary>
public sealed class VideoHost : HwndHost
{
    private const int WsChild = unchecked((int)0x40000000);
    private const int WsVisible = 0x10000000;
    private const int WhMouse = 7;
    private const uint WmRButtonUp = 0x0205;
    private readonly MouseHookProcedure mouseHookProcedure;
    private nint mouseHook;
    private nint videoHostHandle;

    public VideoHost() => mouseHookProcedure = MouseHookProc;

    public event EventHandler<nint>? HandleCreated;

    public event EventHandler<VideoHostKeyEventArgs>? KeyPressed;

    public event EventHandler? ContextMenuRequested;

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
            if (code >= 0 && unchecked((uint)wParam.ToInt64()) == WmRButtonUp)
            {
                MouseHookStruct mouse = Marshal.PtrToStructure<MouseHookStruct>(lParam);
                if (IsPointInsideVideoHost(mouse.X, mouse.Y))
                {
                    _ = Dispatcher.BeginInvoke(() => ContextMenuRequested?.Invoke(this, EventArgs.Empty));
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

    private bool IsPointInsideVideoHost(int x, int y)
    {
        if (videoHostHandle == nint.Zero || !GetWindowRect(videoHostHandle, out NativeRect bounds))
        {
            return false;
        }

        return x >= bounds.Left && x < bounds.Right && y >= bounds.Top && y < bounds.Bottom;
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
    private readonly struct NativeRect
    {
        public readonly int Left;
        public readonly int Top;
        public readonly int Right;
        public readonly int Bottom;
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
    private static extern bool GetWindowRect(nint hwnd, out NativeRect rectangle);
}

public sealed class VideoHostKeyEventArgs(Key key, ModifierKeys modifiers) : EventArgs
{
    public Key Key { get; } = key;

    public ModifierKeys Modifiers { get; } = modifiers;

    public bool Handled { get; set; }
}
