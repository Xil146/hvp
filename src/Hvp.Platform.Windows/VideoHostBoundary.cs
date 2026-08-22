using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace Hvp.Platform.Windows;

/// <summary>Owns the child HWND used by libmpv's <c>wid</c> option.</summary>
public sealed class VideoHost : HwndHost
{
    private const int WsChild = unchecked((int)0x40000000);
    private const int WsVisible = 0x10000000;

    public event EventHandler<nint>? HandleCreated;

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

        HandleCreated?.Invoke(this, handle);
        return new HandleRef(this, handle);
    }

    protected override void DestroyWindowCore(HandleRef hwnd)
    {
        if (hwnd.Handle != nint.Zero && !DestroyWindow(hwnd.Handle))
        {
            throw new InvalidOperationException($"Could not destroy the video host window (Win32 error {Marshal.GetLastWin32Error()}).");
        }
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
}
