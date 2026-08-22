using Hvp.Core.Playback;

namespace Hvp.Playback;

/// <summary>Semantic commands for the minimal libmpv playback spike.</summary>
public interface IPlaybackController : IPlaybackEngine
{
    event EventHandler<PlaybackSnapshot>? SnapshotChanged;

    Task InitializeAsync(nint videoHost, CancellationToken cancellationToken = default);

    Task OpenAsync(string path, CancellationToken cancellationToken = default);

    Task SetPausedAsync(bool paused, CancellationToken cancellationToken = default);

    Task SeekAsync(TimeSpan position, CancellationToken cancellationToken = default);

    Task SeekRelativeAsync(TimeSpan offset, CancellationToken cancellationToken = default);

    Task SeekToPercentAsync(double percent, CancellationToken cancellationToken = default);

    Task SetVolumeAsync(double volume, CancellationToken cancellationToken = default);

    Task SetSubtitleAsync(int? trackId, CancellationToken cancellationToken = default);

    Task StopAsync(CancellationToken cancellationToken = default);
}
