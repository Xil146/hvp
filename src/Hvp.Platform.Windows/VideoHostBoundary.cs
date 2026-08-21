namespace Hvp.Platform.Windows;

/// <summary>
/// Reserves the Windows-owned video-host boundary. The Phase 1 spike will
/// provide the <see cref="System.Windows.Interop.HwndHost"/> implementation.
/// </summary>
public static class VideoHostBoundary
{
    public const string Owner = "Hvp.Platform.Windows";
}
