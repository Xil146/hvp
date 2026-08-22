namespace Hvp.App;

public partial class MainWindow : System.Windows.Window
{
    private readonly Hvp.Playback.IPlaybackController playback = new Hvp.Playback.LibmpvPlaybackEngine();
    private bool videoHostReady;
    private bool closeRequested;
    private bool closeCompleted;

    public MainWindow()
    {
        InitializeComponent();
        VideoHost.HandleCreated += VideoHost_HandleCreated;
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

    private async void Window_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        try
        {
            switch (e.Key)
            {
                case System.Windows.Input.Key.Space when PlayPauseButton.IsEnabled:
                    await playback.SetPausedAsync(playback.Snapshot.State is Hvp.Core.Playback.PlaybackState.Playing);
                    e.Handled = true;
                    break;
                case System.Windows.Input.Key.Left when SeekSlider.IsEnabled:
                    await playback.SeekRelativeAsync(TimeSpan.FromSeconds(-10));
                    e.Handled = true;
                    break;
                case System.Windows.Input.Key.Right when SeekSlider.IsEnabled:
                    await playback.SeekRelativeAsync(TimeSpan.FromSeconds(10));
                    e.Handled = true;
                    break;
                case System.Windows.Input.Key.Up:
                    VolumeSlider.Value = Math.Min(100, VolumeSlider.Value + 5);
                    e.Handled = true;
                    break;
                case System.Windows.Input.Key.Down:
                    VolumeSlider.Value = Math.Max(0, VolumeSlider.Value - 5);
                    e.Handled = true;
                    break;
            }
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
