namespace Hvp.App;

public partial class MainWindow : System.Windows.Window
{
    private readonly Hvp.Playback.IPlaybackController playback = new Hvp.Playback.LibmpvPlaybackEngine();
    private bool videoHostReady;
    private bool closeRequested;
    private bool closeCompleted;
    private bool isFullscreen;
    private System.Windows.Rect normalBounds;
    private System.Windows.WindowState normalWindowState;
    private System.Windows.Controls.ContextMenu? subtitleContextMenu;

    public MainWindow()
    {
        InitializeComponent();
        VideoHost.HandleCreated += VideoHost_HandleCreated;
        VideoHost.KeyPressed += VideoHost_KeyPressed;
        VideoHost.ContextMenuRequested += VideoHost_ContextMenuRequested;
        playback.SnapshotChanged += Playback_SnapshotChanged;
    }

    private async void VideoHost_HandleCreated(object? sender, nint handle)
    {
        try
        {
            await playback.InitializeAsync(handle);
            videoHostReady = true;
        }
        catch (Exception exception)
        {
            ShowPlaybackError(exception.Message);
        }
    }

    private async void Open_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        Microsoft.Win32.OpenFileDialog dialog = new()
        {
            Title = "Open local video",
            Filter = "Video files|*.mp4;*.mkv;*.mov;*.avi;*.webm;*.m4v|All files|*.*",
            CheckFileExists = true,
            Multiselect = false,
        };
        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        await OpenFileAsync(dialog.FileName);
    }

    private async Task OpenFileAsync(string path)
    {
        if (closeRequested)
        {
            return;
        }

        if (!videoHostReady)
        {
            ShowPlaybackError("The video surface is not ready yet.");
            return;
        }

        try
        {
            await playback.OpenAsync(path);
        }
        catch (Exception exception)
        {
            ShowPlaybackError(exception.Message);
        }
    }

    private void Window_PreviewDragOver(object sender, System.Windows.DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent(System.Windows.DataFormats.FileDrop) && !closeRequested
            ? System.Windows.DragDropEffects.Copy
            : System.Windows.DragDropEffects.None;
        e.Handled = true;
    }

    private async void Window_Drop(object sender, System.Windows.DragEventArgs e)
    {
        if (!e.Data.GetDataPresent(System.Windows.DataFormats.FileDrop))
        {
            ShowStatus("Drop one local video file to open it.");
            return;
        }

        string[]? paths = e.Data.GetData(System.Windows.DataFormats.FileDrop) as string[];
        if (!Hvp.Core.Playback.LocalMediaDropValidator.TryGetSingleLocalVideoFile(paths, out string? fullPath, out string message))
        {
            ShowStatus(message);
            return;
        }

        await OpenFileAsync(fullPath!);
    }

    private async void PlayPause_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        try
        {
            await playback.SetPausedAsync(playback.Snapshot.State is Hvp.Core.Playback.PlaybackState.Playing);
        }
        catch (Exception exception)
        {
            ShowPlaybackError(exception.Message);
        }
    }

    private async void Stop_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        try
        {
            await playback.StopAsync();
        }
        catch (Exception exception)
        {
            ShowPlaybackError(exception.Message);
        }
    }

    private async void Seek_ValueChanged(object sender, System.Windows.RoutedPropertyChangedEventArgs<double> e)
    {
        if (!videoHostReady || !SeekSlider.IsEnabled || !SeekSlider.IsMouseCaptureWithin)
        {
            return;
        }

        try
        {
            await playback.SeekToPercentAsync(e.NewValue);
        }
        catch (Exception exception)
        {
            ShowPlaybackError(exception.Message);
        }
    }

    private async void Volume_ValueChanged(object sender, System.Windows.RoutedPropertyChangedEventArgs<double> e)
    {
        if (!videoHostReady)
        {
            return;
        }

        try
        {
            await playback.SetVolumeAsync(e.NewValue);
        }
        catch (Exception exception)
        {
            ShowPlaybackError(exception.Message);
        }
    }

    private void Window_PreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        e.Handled = HandleShortcut(e.Key, System.Windows.Input.Keyboard.Modifiers);
    }

    private void VideoHost_KeyPressed(object? sender, Hvp.Platform.Windows.VideoHostKeyEventArgs e)
    {
        e.Handled = HandleShortcut(e.Key, e.Modifiers);
    }

    private bool HandleShortcut(System.Windows.Input.Key key, System.Windows.Input.ModifierKeys modifiers)
    {
        if (modifiers != System.Windows.Input.ModifierKeys.None)
        {
            return false;
        }

        switch (key)
        {
            case System.Windows.Input.Key.Space when PlayPauseButton.IsEnabled:
                _ = ExecuteShortcutAsync(() => playback.SetPausedAsync(playback.Snapshot.State is Hvp.Core.Playback.PlaybackState.Playing));
                return true;
            case System.Windows.Input.Key.Left when SeekSlider.IsEnabled:
                _ = ExecuteShortcutAsync(() => playback.SeekRelativeAsync(TimeSpan.FromSeconds(-10)));
                return true;
            case System.Windows.Input.Key.Right when SeekSlider.IsEnabled:
                _ = ExecuteShortcutAsync(() => playback.SeekRelativeAsync(TimeSpan.FromSeconds(10)));
                return true;
            case System.Windows.Input.Key.Up:
                VolumeSlider.Value = Math.Min(100, VolumeSlider.Value + 5);
                return true;
            case System.Windows.Input.Key.Down:
                VolumeSlider.Value = Math.Max(0, VolumeSlider.Value - 5);
                return true;
            case System.Windows.Input.Key.F:
                ToggleFullscreen();
                return true;
            case System.Windows.Input.Key.Escape when isFullscreen:
                ExitFullscreen();
                return true;
        }

        return false;
    }

    private async Task ExecuteShortcutAsync(Func<Task> action)
    {
        try { await action(); }
        catch (Exception exception) { ShowPlaybackError(exception.Message); }
    }

    private void Fullscreen_Click(object sender, System.Windows.RoutedEventArgs e) => ToggleFullscreen();

    private void ToggleFullscreen()
    {
        if (isFullscreen)
        {
            ExitFullscreen();
            return;
        }

        normalBounds = RestoreBounds;
        normalWindowState = WindowState;
        isFullscreen = true;
        WindowStyle = System.Windows.WindowStyle.None;
        ResizeMode = System.Windows.ResizeMode.NoResize;
        WindowState = System.Windows.WindowState.Maximized;
        FullscreenButton.Content = "Exit fullscreen";
    }

    private void ExitFullscreen()
    {
        if (!isFullscreen)
        {
            return;
        }

        isFullscreen = false;
        WindowState = System.Windows.WindowState.Normal;
        WindowStyle = System.Windows.WindowStyle.SingleBorderWindow;
        ResizeMode = System.Windows.ResizeMode.CanResize;
        Left = normalBounds.Left;
        Top = normalBounds.Top;
        Width = normalBounds.Width;
        Height = normalBounds.Height;
        WindowState = normalWindowState;
        FullscreenButton.Content = "Fullscreen";
    }

    private void VideoHost_ContextMenuRequested(object? sender, EventArgs e)
    {
        RequestSubtitleContextMenu();
    }

    private void VideoHost_PreviewMouseRightButtonUp(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        e.Handled = true;
        RequestSubtitleContextMenu();
    }

    private void RequestSubtitleContextMenu()
    {
        if (subtitleContextMenu?.IsOpen == true)
        {
            return;
        }

        // Open after the input message has been processed. This works for both
        // the native child HWND and WPF's routed mouse-input fallback.
        _ = Dispatcher.BeginInvoke(OpenSubtitleContextMenu);
    }

    private void OpenSubtitleContextMenu()
    {
        if (subtitleContextMenu?.IsOpen == true)
        {
            return;
        }

        System.Windows.Controls.ContextMenu menu = new();
        System.Windows.Controls.MenuItem subtitles = new() { Header = "Subtitles" };
        System.Windows.Controls.MenuItem off = new() { Header = "Off", IsCheckable = true, IsChecked = playback.Snapshot.SelectedSubtitleTrackId is null };
        off.Click += async (_, _) => await SetSubtitleAsync(null);
        subtitles.Items.Add(off);

        IReadOnlyList<Hvp.Core.Playback.SubtitleTrack> tracks = playback.Snapshot.SubtitleTracks ?? [];
        if (tracks.Count == 0)
        {
            subtitles.Items.Add(new System.Windows.Controls.MenuItem { Header = "No subtitle tracks available", IsEnabled = false });
        }
        else
        {
            foreach (Hvp.Core.Playback.SubtitleTrack track in tracks)
            {
                System.Windows.Controls.MenuItem item = new()
                {
                    Header = track.IsExternal ? $"{track.Label} (external)" : track.Label,
                    IsCheckable = true,
                    IsChecked = playback.Snapshot.SelectedSubtitleTrackId == track.Id,
                };
                item.Click += async (_, _) => await SetSubtitleAsync(track.Id);
                subtitles.Items.Add(item);
            }
        }

        menu.Items.Add(subtitles);
        menu.PlacementTarget = VideoHost;
        menu.Placement = System.Windows.Controls.Primitives.PlacementMode.MousePoint;
        menu.Closed += (_, _) => subtitleContextMenu = null;
        VideoHost.ContextMenu = menu;
        subtitleContextMenu = menu;
        menu.IsOpen = true;
    }

    private async Task SetSubtitleAsync(int? trackId)
    {
        try
        {
            await playback.SetSubtitleAsync(trackId);
        }
        catch (Exception exception)
        {
            ShowPlaybackError(exception.Message);
        }
    }

    private void Playback_SnapshotChanged(object? sender, Hvp.Core.Playback.PlaybackSnapshot snapshot)
    {
        _ = Dispatcher.InvokeAsync(() =>
        {
            StatusText.Text = snapshot.Message ?? snapshot.State.ToString();
            StreamStatusText.Text = snapshot.Stream?.ToCompactText() ?? "Stream: unavailable";
            PlayPauseButton.IsEnabled = snapshot.State is Hvp.Core.Playback.PlaybackState.Playing or Hvp.Core.Playback.PlaybackState.Paused;
            PlayPauseButton.Content = snapshot.State is Hvp.Core.Playback.PlaybackState.Playing ? "Pause" : "Play";
            SeekSlider.IsEnabled = snapshot.State is Hvp.Core.Playback.PlaybackState.Playing or Hvp.Core.Playback.PlaybackState.Paused;
            StopButton.IsEnabled = snapshot.State is Hvp.Core.Playback.PlaybackState.Opening or Hvp.Core.Playback.PlaybackState.Playing or Hvp.Core.Playback.PlaybackState.Paused;
        });
    }

    private void ShowPlaybackError(string message)
    {
        StatusText.Text = message;
        PlayPauseButton.IsEnabled = false;
        StopButton.IsEnabled = false;
    }

    private void ShowStatus(string message) => StatusText.Text = message;

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        if (closeCompleted)
        {
            base.OnClosing(e);
            return;
        }

        e.Cancel = true;
        if (closeRequested)
        {
            return;
        }

        closeRequested = true;
        playback.SnapshotChanged -= Playback_SnapshotChanged;
        VideoHost.KeyPressed -= VideoHost_KeyPressed;
        VideoHost.ContextMenuRequested -= VideoHost_ContextMenuRequested;
        _ = DisposeThenCloseAsync();
    }

    private async Task DisposeThenCloseAsync()
    {
        try
        {
            await playback.DisposeAsync();
        }
        finally
        {
            closeCompleted = true;
            Close();
        }
    }
}
