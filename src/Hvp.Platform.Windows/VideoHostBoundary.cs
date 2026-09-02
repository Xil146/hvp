using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Input;
using System.Windows.Interop;

namespace Hvp.Platform.Windows;

/// <summary>Owns the child HWND used by libmpv's <c>wid</c> option.</summary>
public sealed class VideoHost : HwndHost
{
    private const int WsChild = unchecked((int)0x40000000);
    private const int WsVisible = 0x10000000;
    private const int SsNotify = 0x00000100;
    private const int WmLButtonUp = 0x0202;
    private const int WmLButtonDoubleClick = 0x0203;
    private const int WmRButtonUp = 0x0205;
    private const int WmDropFiles = 0x0233;
    private bool suppressNextLeftButtonUp;

    public event EventHandler<nint>? HandleCreated;

    public event EventHandler<VideoHostKeyEventArgs>? KeyPressed;

    public event EventHandler<VideoHostContextMenuEventArgs>? ContextMenuRequested;

    public event EventHandler<VideoHostFilesDroppedEventArgs>? FilesDropped;

    public event EventHandler? VideoClicked;

    public event EventHandler? VideoDoubleClicked;

    protected override HandleRef BuildWindowCore(HandleRef hwndParent)
    {
        nint handle = CreateWindowEx(
            0,
            "STATIC",
            string.Empty,
            WsChild | WsVisible | SsNotify,
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
            DragAcceptFiles(handle, true);
            HandleCreated?.Invoke(this, handle);
            return new HandleRef(this, handle);
        }
        catch
        {
            DragAcceptFiles(handle, false);
            _ = DestroyWindow(handle);
            throw;
        }
    }

    protected override void DestroyWindowCore(HandleRef hwnd)
    {
        suppressNextLeftButtonUp = false;
        if (hwnd.Handle != nint.Zero)
        {
            DragAcceptFiles(hwnd.Handle, false);
        }

        if (hwnd.Handle != nint.Zero && !DestroyWindow(hwnd.Handle))
        {
            throw new InvalidOperationException($"Could not destroy the video host window (Win32 error {Marshal.GetLastWin32Error()}).");
        }
    }

    protected override nint WndProc(nint hwnd, int msg, nint wParam, nint lParam, ref bool handled)
    {
        switch (msg)
        {
            case WmLButtonDoubleClick:
                suppressNextLeftButtonUp = true;
                VideoDoubleClicked?.Invoke(this, EventArgs.Empty);
                handled = true;
                return nint.Zero;

            case WmLButtonUp:
                if (suppressNextLeftButtonUp)
                {
                    suppressNextLeftButtonUp = false;
                }
                else
                {
                    VideoClicked?.Invoke(this, EventArgs.Empty);
                }

                handled = true;
                return nint.Zero;

            case WmRButtonUp:
                NativePoint position = new(GetSignedLowWord(lParam), GetSignedHighWord(lParam));
                if (ClientToScreen(hwnd, ref position))
                {
                    ContextMenuRequested?.Invoke(this, new VideoHostContextMenuEventArgs(position.X, position.Y));
                }

                handled = true;
                return nint.Zero;

            case WmDropFiles:
                HandleFileDrop(wParam);
                handled = true;
                return nint.Zero;
        }

        return base.WndProc(hwnd, msg, wParam, lParam, ref handled);
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

    private void HandleFileDrop(nint dropHandle)
    {
        try
        {
            uint count = DragQueryFile(dropHandle, uint.MaxValue, null, 0);
            List<string> paths = new(checked((int)count));
            for (uint index = 0; index < count; index++)
            {
                uint length = DragQueryFile(dropHandle, index, null, 0);
                StringBuilder path = new(checked((int)length + 1));
                if (DragQueryFile(dropHandle, index, path, checked((uint)path.Capacity)) > 0)
                {
                    paths.Add(path.ToString());
                }
            }

            FilesDropped?.Invoke(this, new VideoHostFilesDroppedEventArgs(paths));
        }
        catch
        {
            // A malformed native drop payload must not escape HwndHost's
            // window procedure. DragFinish still releases the drop handle.
        }
        finally
        {
            DragFinish(dropHandle);
        }
    }

    private static int GetSignedLowWord(nint value) => unchecked((short)(value.ToInt64() & 0xffff));

    private static int GetSignedHighWord(nint value) => unchecked((short)((value.ToInt64() >> 16) & 0xffff));

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

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ClientToScreen(nint hwnd, ref NativePoint point);

    [DllImport("shell32.dll")]
    private static extern void DragAcceptFiles(nint hwnd, [MarshalAs(UnmanagedType.Bool)] bool accept);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern uint DragQueryFile(nint drop, uint fileIndex, StringBuilder? fileName, uint fileNameSize);

    [DllImport("shell32.dll")]
    private static extern void DragFinish(nint drop);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint(int x, int y)
    {
        public int X = x;
        public int Y = y;
    }
}

public sealed class VideoHostKeyEventArgs(Key key, ModifierKeys modifiers) : EventArgs
{
    public Key Key { get; } = key;

    public ModifierKeys Modifiers { get; } = modifiers;

    public bool Handled { get; set; }
}

/// <summary>Provides the native screen coordinates for a video-surface context menu.</summary>
public sealed class VideoHostContextMenuEventArgs(int screenX, int screenY) : EventArgs
{
    public int ScreenX { get; } = screenX;

    public int ScreenY { get; } = screenY;
}

/// <summary>Provides paths dropped directly on the native video surface.</summary>
public sealed class VideoHostFilesDroppedEventArgs(IReadOnlyList<string> paths) : EventArgs
{
    public IReadOnlyList<string> Paths { get; } = paths;
}
