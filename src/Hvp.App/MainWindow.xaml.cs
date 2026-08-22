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
    private System.Windows.Controls.ContextMenu? videoContextMenu;
    private bool isSeekDragging;
    private bool seekCommandInFlight;
    private (int Generation, double Percent)? pendingSeek;
    private int seekGeneration;
    private Task? seekDrainTask;
    private bool isMediaTransition;
    private Task mediaTransitionTask = Task.CompletedTask;
    private int pendingMediaTransitions;

    public MainWindow()
    {
        InitializeComponent();
        VideoHost.HandleCreated += VideoHost_HandleCreated;
        VideoHost.KeyPressed += VideoHost_KeyPressed;
        VideoHost.ContextMenuRequested += VideoHost_ContextMenuRequested;
        VideoHost.VideoClicked += VideoHost_VideoClicked;
        VideoHost.VideoDoubleClicked += VideoHost_VideoDoubleClicked;
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

        await QueueMediaTransitionAsync(() => playback.OpenAsync(path));
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
        await QueueMediaTransitionAsync(() => playback.StopAsync());
    }

    private void SeekSlider_PreviewMouseLeftButtonDown(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (!videoHostReady || !SeekSlider.IsEnabled || SeekSlider.ActualWidth <= 0)
        {
            return;
        }

        isSeekDragging = true;
        _ = SeekSlider.CaptureMouse();
        UpdateSeekFromPointer(e.GetPosition(SeekSlider));
        e.Handled = true;
    }

    private void SeekSlider_PreviewMouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (!isSeekDragging)
        {
            return;
        }

        if (e.LeftButton != System.Windows.Input.MouseButtonState.Pressed)
        {
            EndSeekDrag();
            return;
        }

        UpdateSeekFromPointer(e.GetPosition(SeekSlider));
        e.Handled = true;
    }

    private void SeekSlider_PreviewMouseLeftButtonUp(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (!isSeekDragging)
        {
            return;
        }

        UpdateSeekFromPointer(e.GetPosition(SeekSlider));
        EndSeekDrag();
        e.Handled = true;
    }

    private void UpdateSeekFromPointer(System.Windows.Point point)
    {
        double ratio = Math.Clamp(point.X / SeekSlider.ActualWidth, 0, 1);
        double percent = SeekSlider.Minimum + ((SeekSlider.Maximum - SeekSlider.Minimum) * ratio);
        SeekSlider.Value = percent;
        QueueSeek(percent);
    }

    private void EndSeekDrag()
    {
        isSeekDragging = false;
        if (SeekSlider.IsMouseCaptured)
        {
            SeekSlider.ReleaseMouseCapture();
        }
    }

    private void QueueSeek(double percent)
    {
        if (isMediaTransition)
        {
            return;
        }

        pendingSeek = (seekGeneration, percent);
        if (!seekCommandInFlight)
        {
            seekDrainTask = ProcessSeekQueueAsync();
        }
    }

    private async Task ProcessSeekQueueAsync()
    {
        seekCommandInFlight = true;
        try
        {
            while (!closeRequested && pendingSeek is { } pending)
            {
                pendingSeek = null;
                if (pending.Generation != seekGeneration)
                {
                    continue;
                }

                await playback.SeekToPercentAsync(pending.Percent);
            }
        }
        catch (Exception exception)
        {
            ShowPlaybackError(exception.Message);
        }
        finally
        {
            seekCommandInFlight = false;
            if (!closeRequested && pendingSeek is { } pending && pending.Generation == seekGeneration)
            {
                seekDrainTask = ProcessSeekQueueAsync();
            }
        }
    }

    private async Task InvalidatePendingSeekAsync()
    {
        seekGeneration++;
        pendingSeek = null;
        EndSeekDrag();
        if (seekDrainTask is not null)
        {
            await seekDrainTask;
        }
    }

    private Task QueueMediaTransitionAsync(Func<Task> action)
    {
        Task previous = mediaTransitionTask;
        pendingMediaTransitions++;
        isMediaTransition = true;
        Task next = ExecuteMediaTransitionAsync(previous, action);
        mediaTransitionTask = next;
        return next;
    }

    private async Task ExecuteMediaTransitionAsync(Task previous, Func<Task> action)
    {
        try
        {
            await previous;
            await InvalidatePendingSeekAsync();
            await action();
        }
        catch (Exception exception)
        {
            ShowPlaybackError(exception.Message);
        }
        finally
        {
            pendingMediaTransitions--;
            isMediaTransition = pendingMediaTransitions > 0;
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
    }

    private void VideoHost_ContextMenuRequested(object? sender, EventArgs e)
    {
        RequestVideoContextMenu();
    }

    private void VideoHost_PreviewMouseRightButtonUp(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        e.Handled = true;
        RequestVideoContextMenu();
    }

    private void VideoHost_VideoClicked(object? sender, EventArgs e)
    {
        if (PlayPauseButton.IsEnabled)
        {
            _ = ExecuteShortcutAsync(() => playback.SetPausedAsync(playback.Snapshot.State is Hvp.Core.Playback.PlaybackState.Playing));
        }
    }

    private void VideoHost_VideoDoubleClicked(object? sender, EventArgs e)
    {
        if (PlayPauseButton.IsEnabled)
        {
            ToggleFullscreen();
        }
    }

    private void RequestVideoContextMenu()
    {
        if (videoContextMenu?.IsOpen == true)
        {
            return;
        }

        // Open after the input message has been processed. This works for both
        // the native child HWND and WPF's routed mouse-input fallback.
        _ = Dispatcher.BeginInvoke(OpenVideoContextMenu);
    }

    private void OpenVideoContextMenu()
    {
        if (videoContextMenu?.IsOpen == true)
        {
            return;
        }

        System.Windows.Controls.ContextMenu menu = new();
        System.Windows.Controls.MenuItem fullscreen = new() { Header = isFullscreen ? "Exit fullscreen" : "Enter fullscreen" };
        fullscreen.Click += (_, _) => ToggleFullscreen();
        menu.Items.Add(fullscreen);

        System.Windows.Controls.MenuItem video = new() { Header = "Video" };
        IReadOnlyList<Hvp.Core.Playback.VideoTrack> videoTracks = playback.Snapshot.VideoTracks ?? [];
        if (videoTracks.Count == 0)
        {
            video.Items.Add(new System.Windows.Controls.MenuItem { Header = "No video tracks available", IsEnabled = false });
        }
        else
        {
            foreach (Hvp.Core.Playback.VideoTrack track in videoTracks)
            {
                System.Windows.Controls.MenuItem item = new()
                {
                    Header = track.IsExternal ? $"{track.Label} (external)" : track.Label,
                    IsCheckable = true,
                    IsChecked = playback.Snapshot.SelectedVideoTrackId == track.Id,
                };
                item.Click += async (_, _) => await SetVideoAsync(track.Id);
                video.Items.Add(item);
            }
        }

        menu.Items.Add(video);
        System.Windows.Controls.MenuItem audio = new() { Header = "Audio" };
        IReadOnlyList<Hvp.Core.Playback.AudioTrack> audioTracks = playback.Snapshot.AudioTracks ?? [];
        if (audioTracks.Count == 0)
        {
            audio.Items.Add(new System.Windows.Controls.MenuItem { Header = "No audio tracks available", IsEnabled = false });
        }
        else
        {
            foreach (Hvp.Core.Playback.AudioTrack track in audioTracks)
            {
                System.Windows.Controls.MenuItem item = new()
                {
                    Header = track.IsExternal ? $"{track.Label} (external)" : track.Label,
                    IsCheckable = true,
                    IsChecked = playback.Snapshot.SelectedAudioTrackId == track.Id,
                };
                item.Click += async (_, _) => await SetAudioAsync(track.Id);
                audio.Items.Add(item);
            }
        }

        menu.Items.Add(audio);
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
        menu.Closed += (_, _) => videoContextMenu = null;
        VideoHost.ContextMenu = menu;
        videoContextMenu = menu;
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

    private async Task SetAudioAsync(int trackId)
    {
        try
        {
            await playback.SetAudioAsync(trackId);
        }
        catch (Exception exception)
        {
            ShowPlaybackError(exception.Message);
        }
    }

    private async Task SetVideoAsync(int trackId)
    {
        try
        {
            await playback.SetVideoAsync(trackId);
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
        VideoHost.VideoClicked -= VideoHost_VideoClicked;
        VideoHost.VideoDoubleClicked -= VideoHost_VideoDoubleClicked;
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
