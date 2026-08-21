using Hvp.Core.Playback;

namespace Hvp.Playback;

/// <summary>
/// Defines the Phase 0 boundary for the future libmpv adapter. Native loading,
/// callbacks, and commands are intentionally deferred to the Phase 1 spike.
/// </summary>
public sealed class PlaybackEngineBoundary : IPlaybackEngine
{
    public PlaybackSnapshot Snapshot => PlaybackSnapshot.Idle;

    public ValueTask DisposeAsync() => ValueTask.CompletedTask;
}
